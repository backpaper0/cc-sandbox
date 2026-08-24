#!/usr/bin/env bats
#
# E2E tests for the DinD sidecar and Testcontainers support (ticket 05): `bin/cc-sandbox
# up` gives the sandbox container a working `docker` command backed by a nested DinD
# daemon, containers started through it are subject to the same isolation as the
# sandbox container itself, and Testcontainers-based tests succeed. Runs against a
# real Docker daemon, no mocks.

load helpers

setup_file() {
  export CC_SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/cc-sandbox"
  export PROJECT_DIR
  # Resolve symlinks: on macOS `mktemp -d` hands back a /var/... path that is really
  # a symlink into /private/var, and the CLI records the physical path it mounts.
  # Comparing the two forms below would never match.
  PROJECT_DIR="$(cd "$(mktemp -d)" && pwd -P)"

  # A host-side listener bound to all interfaces, the same shape network_isolation.bats
  # uses -- the case DinD-nested containers must not be able to reach either.
  export HOST_PORT_ALL_INTERFACES=18903
  python3 -c "
import http.server, threading
def serve(addr, port):
    http.server.HTTPServer((addr, port), http.server.SimpleHTTPRequestHandler).serve_forever()
threading.Thread(target=serve, args=('0.0.0.0', ${HOST_PORT_ALL_INTERFACES}), daemon=True).start()
import time; time.sleep(600)
" &
  export HOST_LISTENER_PID=$!
  sleep 1

  run "$CC_SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]
}

teardown_file() {
  "$CC_SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  kill "$HOST_LISTENER_PID" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR"
}

@test "docker commands from the sandbox container reach the nested DinD daemon" {
  run exec_in "docker info"
  [ "$status" -eq 0 ]

  # Confirms it's really the DinD sidecar's daemon and not some local one: the
  # sandbox image installs the docker CLI but no local dockerd.
  run exec_in "docker version --format '{{.Server.Version}}'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "a container started via docker run cannot reach a host service bound to 0.0.0.0" {
  run exec_in "docker run --rm curlimages/curl -m 4 -s -o /dev/null -w '%{http_code}' http://$(gateway_ip_of "$(dind_container_id)"):${HOST_PORT_ALL_INTERFACES}/"
  [ "$status" -ne 0 ]
}

@test "a container started via docker run can still reach the public internet" {
  run exec_in "docker run --rm curlimages/curl -m 10 -s -o /dev/null -w '%{http_code}' http://example.com/"
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

@test "a Testcontainers-based test succeeds inside the sandbox" {
  run exec_in "mkdir -p /tmp/tc-smoke && cd /tmp/tc-smoke && npm init -y >/dev/null && npm install --no-audit --no-fund testcontainers >/dev/null 2>&1"
  [ "$status" -eq 0 ]

  docker exec -u dev -i "$(container_id)" bash -lc 'cat > /tmp/tc-smoke/smoke.mjs' <<'JS'
import { GenericContainer } from "testcontainers";

const container = await new GenericContainer("redis:7-alpine")
  .withExposedPorts(6379)
  .start();

console.log(`OK ${container.getHost()}:${container.getMappedPort(6379)}`);
await container.stop();
JS

  run exec_in "cd /tmp/tc-smoke && node smoke.mjs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK "* ]]
}
