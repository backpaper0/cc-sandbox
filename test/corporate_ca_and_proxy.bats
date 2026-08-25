#!/usr/bin/env bats
#
# E2E tests for corporate CA certificate / proxy support (ticket 12, ADR-0007):
# ~/.cc-sandbox/ca-cert.crt (if present) is baked into the main container's
# trusted CA bundle at build time and installed into the DinD sidecar at run
# time; ~/.cc-sandbox/proxy.env (if present) is injected into both. Runs
# against a real Docker daemon, no mocks.

load helpers

setup_file() {
  export CC_SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/cc-sandbox"
  export DOCKER_CONFIG="${DOCKER_CONFIG:-${HOME}/.docker}"
  export PROJECT_DIR
  PROJECT_DIR="$(cd "$(mktemp -d)" && pwd -P)"

  # A fake $HOME so these tests never touch the real developer's ~/.cc-sandbox.
  export FAKE_HOME
  FAKE_HOME="$(mktemp -d)"
  mkdir -p "${FAKE_HOME}/.cc-sandbox"

  # A throwaway self-signed CA. Only its bytes ending up in the right places
  # matter for these tests, not that anything actually trusts a leaf cert it
  # issues.
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj "/CN=cc-sandbox-test-ca" \
    -keyout "${FAKE_HOME}/ca-key.pem" \
    -out "${FAKE_HOME}/.cc-sandbox/ca-cert.crt" >/dev/null 2>&1

  {
    echo "HTTP_PROXY=http://proxy.example.test:3128"
    echo "HTTPS_PROXY=http://proxy.example.test:3128"
    echo "NO_PROXY=example.test"
  } > "${FAKE_HOME}/.cc-sandbox/proxy.env"

  # A distinctive line from inside the PEM body -- present verbatim in the
  # merged CA bundle iff update-ca-certificates picked our cert up.
  export CA_CERT_MARKER
  CA_CERT_MARKER="$(sed -n '2p' "${FAKE_HOME}/.cc-sandbox/ca-cert.crt")"
}

teardown_file() {
  HOME="${FAKE_HOME}" "$CC_SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR" "$FAKE_HOME"
}

teardown() {
  "$CC_SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
}

sandbox_up_with_home() {
  local sandbox_home="$1"
  env HOME="$sandbox_home" DOCKER_CONFIG="$DOCKER_CONFIG" \
    "$CC_SANDBOX_BIN" up "$PROJECT_DIR"
}

exec_in_dind() {
  docker exec -u root "$(dind_container_id)" sh -c "$1"
}

@test "up without ca-cert.crt or proxy.env is a no-op" {
  local empty_home
  empty_home="$(mktemp -d)"

  run sandbox_up_with_home "$empty_home"
  [ "$status" -eq 0 ]

  run exec_in "[ -s /usr/local/share/ca-certificates/cc-sandbox-ca.crt ]"
  [ "$status" -ne 0 ]

  run exec_in "printenv HTTP_PROXY"
  [ "$status" -ne 0 ]

  # Node/Python's CA env vars (see the next test) are set unconditionally, since
  # they point at the same merged bundle these tools already default to -- that
  # part of the "no-op" claim doesn't apply to them.

  rm -rf "$empty_home"
}

@test "up with ca-cert.crt bakes it into the main container's trusted CA bundle" {
  run sandbox_up_with_home "$FAKE_HOME"
  [ "$status" -eq 0 ]

  run exec_in "sha256sum < /usr/local/share/ca-certificates/cc-sandbox-ca.crt | awk '{print \$1}'"
  [ "$status" -eq 0 ]
  local in_container_hash="$output"
  local host_hash
  host_hash="$(sha256sum "${FAKE_HOME}/.cc-sandbox/ca-cert.crt" | awk '{print $1}')"
  [ "$in_container_hash" = "$host_hash" ]

  run exec_in "grep -qF '${CA_CERT_MARKER}' /etc/ssl/certs/ca-certificates.crt"
  [ "$status" -eq 0 ]
}

@test "up with ca-cert.crt installs it into the DinD sidecar's trusted CA bundle" {
  run sandbox_up_with_home "$FAKE_HOME"
  [ "$status" -eq 0 ]

  run exec_in_dind "grep -qF '${CA_CERT_MARKER}' /etc/ssl/certs/ca-certificates.crt"
  [ "$status" -eq 0 ]
}

@test "up sets Node/Python's CA env vars to the merged bundle regardless of ca-cert.crt" {
  run sandbox_up_with_home "$FAKE_HOME"
  [ "$status" -eq 0 ]

  local var
  for var in NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE PIP_CERT CURL_CA_BUNDLE SSL_CERT_FILE; do
    run exec_in "printenv ${var}"
    [ "$status" -eq 0 ]
    [ "$output" = "/etc/ssl/certs/ca-certificates.crt" ]
  done
}

@test "up with proxy.env injects HTTP_PROXY/HTTPS_PROXY into the main container, with dind exempted from NO_PROXY" {
  run sandbox_up_with_home "$FAKE_HOME"
  [ "$status" -eq 0 ]

  run exec_in "printenv HTTP_PROXY"
  [ "$status" -eq 0 ]
  [ "$output" = "http://proxy.example.test:3128" ]

  run exec_in "printenv HTTPS_PROXY"
  [ "$status" -eq 0 ]
  [ "$output" = "http://proxy.example.test:3128" ]

  # The main container's `docker` CLI dials DOCKER_HOST=tcp://dind:2375 itself,
  # so it -- not the dind sidecar -- is the one that needs "dind" exempted from
  # proxying (see docs/adr/0007 / bin/cc-sandbox's load_proxy_env).
  run exec_in "printenv NO_PROXY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"example.test"* ]]
  [[ "$output" == *"dind"* ]]
}

@test "up with proxy.env injects HTTP_PROXY/HTTPS_PROXY/NO_PROXY into the DinD sidecar unmodified" {
  run sandbox_up_with_home "$FAKE_HOME"
  [ "$status" -eq 0 ]

  run exec_in_dind "printenv HTTP_PROXY"
  [ "$status" -eq 0 ]
  [ "$output" = "http://proxy.example.test:3128" ]

  run exec_in_dind "printenv NO_PROXY"
  [ "$status" -eq 0 ]
  [ "$output" = "example.test" ]
}
