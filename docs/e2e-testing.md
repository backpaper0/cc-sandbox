# End-to-end testing

Run the complete acceptance suite with:

```sh
bin/test-e2e
```

The command is the same for local runs and CI. It requires Bash, Bats, and a
real Linux Docker daemon on which the caller can start privileged containers.
The suite does not mock Docker: it builds the sandbox image and exercises the
public `bin/cc-sandbox` CLI against running sandbox and DinD containers. Network
tests also require outbound DNS and HTTPS access.

The command covers the behaviors listed in the spec's Testing Decisions:
project mounting, host-network isolation, internet access, DinD and
Testcontainers, code-server authentication, multi-instance isolation, shared
cache persistence, auth-profile injection, instance listing, and Playwright
MCP navigation/screenshot/cache reuse.

## Running from an interactive terminal

`bats`' `run` does not detach a test's stdin from the terminal it was invoked
from. If `bin/test-e2e` is run directly at an interactive prompt (a real tty on
stdin), `test/auth_profile_injection.bats`'s "up --profile with no name fails
clearly in a non-interactive shell" test can spuriously fall through
`select_profile_interactive`'s `[[ ! -t 0 ]]` guard (see
[docs/adr/0006](adr/0006-interactive-profile-selection.md)) and land on the
real `select` prompt, blocking on genuine keyboard input instead of failing
fast as the test expects.

Run with stdin redirected away from the terminal to avoid this:

```sh
bin/test-e2e < /dev/null
```

## Platform scope

The acceptance baseline is WSL2 or Linux-native Docker. The suite asserts that
the `host.docker.internal` route is unavailable from the sandbox, but that
assertion also passes when the hostname does not resolve. It therefore does not
claim to verify Docker Desktop or OrbStack's macOS host-routing implementation.
That macOS-specific bypass path remains explicitly out of scope in
`.scratch/isolated-dev-sandbox/spec.md`.

The agent execution environment used to work on this repository may expose a
Docker daemon whose data root is backed by a nested overlay/btrfs combination.
Such a daemon can fail image builds with `operation not permitted` or `Invalid
cross-device link`. That is not a supported verification environment; run the
command on the target WSL2/Linux-native Docker host instead.
