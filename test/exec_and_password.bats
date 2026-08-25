#!/usr/bin/env bats
#
# E2E tests for `bin/cc-sandbox exec` / `bin/cc-sandbox password`: re-running
# what `up`'s "Enter with:" / "Password:" lines print, as actual subcommands
# instead of copy-pasted command strings. Runs against a real Docker daemon,
# no mocks.

load helpers

setup_file() {
  export CC_SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/cc-sandbox"
  export PROJECT_DIR
  # Resolve symlinks: on macOS `mktemp -d` hands back a /var/... path that is really
  # a symlink into /private/var, and the CLI records the physical path it mounts.
  # Comparing the two forms below would never match.
  PROJECT_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  "$CC_SANDBOX_BIN" up "$PROJECT_DIR" >/dev/null
}

teardown_file() {
  "$CC_SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR"
}

code_server_password() {
  docker exec -u dev "$(container_id)" grep '^password:' /home/dev/.config/code-server/config.yaml \
    | sed 's/^password: *//'
}

@test "exec runs a command inside the running instance and returns its output" {
  run "$CC_SANDBOX_BIN" exec "$PROJECT_DIR" -- echo hello-from-exec
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello-from-exec"* ]]
}

@test "exec propagates the exit code of the command it runs" {
  run "$CC_SANDBOX_BIN" exec "$PROJECT_DIR" -- bash -c 'exit 7'
  [ "$status" -eq 7 ]
}

@test "exec runs as the sandbox user, not root" {
  run "$CC_SANDBOX_BIN" exec "$PROJECT_DIR" -- whoami
  [ "$status" -eq 0 ]
  [ "$output" = "dev" ]
}

@test "exec resolves the target the same way as down: falls back to the sole running instance" {
  run "$CC_SANDBOX_BIN" exec -- echo hello-from-default
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello-from-default"* ]]
}

@test "exec rejects both a project-dir and --name at once" {
  run "$CC_SANDBOX_BIN" exec "$PROJECT_DIR" --name whatever -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"pass either"* ]]
}

@test "exec fails closed with a clear message when no instance matches" {
  run "$CC_SANDBOX_BIN" exec --name totally-bogus-name -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"no running container"* ]]
}

@test "password prints the same value code-server itself was configured with" {
  run "$CC_SANDBOX_BIN" password "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$(code_server_password)" ]
}

@test "password prints the value alone, with no label" {
  run "$CC_SANDBOX_BIN" password "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"password"* ]]
  [ -n "$output" ]
}

@test "password fails closed with a clear message when no instance matches" {
  run "$CC_SANDBOX_BIN" password --name totally-bogus-name
  [ "$status" -ne 0 ]
  [[ "$output" == *"no running container"* ]]
}
