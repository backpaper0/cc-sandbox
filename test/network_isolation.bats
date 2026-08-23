#!/usr/bin/env bats
#
# E2E tests for network isolation (ticket 02): `bin/sandbox up` blocks the sandbox's
# non-root user from reaching host-bound services while still allowing internet
# access. Runs against a real Docker daemon and real iptables, no mocks.
#
# The rules are installed inside the container, so these tests need no sudo and run
# identically whether the daemon is native Linux or a VM on macOS.

load helpers

setup_file() {
  export SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/sandbox"
  export PROJECT_DIR
  # Resolve symlinks: on macOS `mktemp -d` hands back a /var/... path that is really
  # a symlink into /private/var, and the CLI records the physical path it mounts.
  # Comparing the two forms below would never match.
  PROJECT_DIR="$(cd "$(mktemp -d)" && pwd -P)"

  # Two host-side listeners: one bound to all interfaces (the case isolation has to
  # actively block, since the sandbox can otherwise route to it), one bound to
  # loopback only (already unreachable from a container, kept here as a control).
  export HOST_PORT_ALL_INTERFACES=18901
  export HOST_PORT_LOOPBACK_ONLY=18902
  python3 -c "
import http.server, threading
def serve(addr, port):
    http.server.HTTPServer((addr, port), http.server.SimpleHTTPRequestHandler).serve_forever()
threading.Thread(target=serve, args=('0.0.0.0', ${HOST_PORT_ALL_INTERFACES}), daemon=True).start()
threading.Thread(target=serve, args=('127.0.0.1', ${HOST_PORT_LOOPBACK_ONLY}), daemon=True).start()
import time; time.sleep(600)
" &
  export HOST_LISTENER_PID=$!
  sleep 1
}

teardown_file() {
  "$SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  kill "$HOST_LISTENER_PID" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR"
}

# The container's bridge gateway -- the host-side address a container can normally
# route to. Reachability of a host service through it varies by platform, so what
# matters here is only that the sandbox cannot get to it.
gateway_ip() {
  docker inspect "$(container_id)" \
    --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'
}

@test "up starts the sandbox with network isolation applied" {
  run "$SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -n "$(container_id)" ]
}

@test "a host service bound to 0.0.0.0 is unreachable via host.docker.internal" {
  run exec_in "curl -sS -m 3 -o /dev/null -w '%{http_code}' http://host.docker.internal:${HOST_PORT_ALL_INTERFACES}/"
  [ "$status" -ne 0 ]
}

@test "a host service bound to 0.0.0.0 is unreachable via the bridge gateway" {
  run exec_in "curl -sS -m 3 -o /dev/null -w '%{http_code}' http://$(gateway_ip):${HOST_PORT_ALL_INTERFACES}/"
  [ "$status" -ne 0 ]
}

@test "a host service bound to 127.0.0.1 is unreachable from the sandbox" {
  run exec_in "curl -sS -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:${HOST_PORT_LOOPBACK_ONLY}/"
  [ "$status" -ne 0 ]
}

@test "the sandbox can still reach the public internet" {
  run exec_in "curl -sS -m 10 -o /dev/null -w '%{http_code}' http://example.com/"
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

# Blocking whole private ranges is easy to get wrong in a way that takes DNS down
# with it (a resolver reachable over one of those ranges stops answering), which
# would look like "no internet" rather than "isolated".
@test "the sandbox can still resolve DNS names" {
  run exec_in "getent hosts example.com"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "re-running up against a live sandbox keeps the isolation in place" {
  run "$SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]

  run exec_in "curl -sS -m 3 -o /dev/null -w '%{http_code}' http://host.docker.internal:${HOST_PORT_ALL_INTERFACES}/"
  [ "$status" -ne 0 ]

  run exec_in "curl -sS -m 10 -o /dev/null -w '%{http_code}' http://example.com/"
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

@test "down removes the sandbox" {
  run "$SANDBOX_BIN" down "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -z "$(container_id)" ]
}
