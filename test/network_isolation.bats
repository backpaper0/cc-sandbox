#!/usr/bin/env bats
#
# E2E tests for network isolation (ticket 02): `bin/sandbox up` blocks the sandbox
# from reaching host-bound services while still allowing internet access, and
# `bin/sandbox down` removes the iptables rules it added.
# Runs against a real Docker daemon and real iptables, no mocks.

setup_file() {
  export SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/sandbox"
  export PROJECT_DIR
  PROJECT_DIR="$(mktemp -d)"

  # Two host-side listeners: one bound to all interfaces (the case DOCKER-USER-only
  # isolation would miss, since the sandbox's bridge gateway IP is a locally-owned
  # host address), one bound to loopback only (already unreachable from a container
  # without any extra rules, kept here as a control).
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

  # Baseline rule counts, to check `down` leaves no residue -- not implementation
  # details of how a rule is built, just the observable size of the firewall config.
  export BASELINE_DOCKER_USER_LINES BASELINE_INPUT_LINES
  BASELINE_DOCKER_USER_LINES="$(sudo iptables -S DOCKER-USER | wc -l)"
  BASELINE_INPUT_LINES="$(sudo iptables -S INPUT | wc -l)"
}

teardown_file() {
  "$SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  kill "$HOST_LISTENER_PID" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR"
}

# Identify the sandbox container purely by the externally observable fact that
# it bind-mounts $PROJECT_DIR at /workspace (see test/basic_up_down.bats).
container_id() {
  local cid
  for cid in $(docker ps -q --filter 'label=com.docker.compose.project'); do
    if docker inspect "${cid}" \
        --format '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{"\n"}}{{end}}{{end}}' \
        | grep -qxF "${PROJECT_DIR}"; then
      echo "${cid}"
      return 0
    fi
  done
}

# The container's bridge gateway IP -- the address a host service bound to
# 0.0.0.0 (all interfaces) is reachable at from inside the container.
gateway_ip() {
  docker inspect "$(container_id)" \
    --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'
}

exec_in() {
  docker exec -u dev "$(container_id)" bash -lc "$1"
}

@test "up starts the sandbox with network isolation applied" {
  run "$SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -n "$(container_id)" ]
}

@test "host service bound to 0.0.0.0 is unreachable from the sandbox" {
  run exec_in "curl -sS -m 3 -o /dev/null -w '%{http_code}' http://$(gateway_ip):${HOST_PORT_ALL_INTERFACES}/"
  [ "$status" -ne 0 ]
}

@test "host service bound to 127.0.0.1 is unreachable from the sandbox" {
  run exec_in "curl -sS -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:${HOST_PORT_LOOPBACK_ONLY}/"
  [ "$status" -ne 0 ]
}

@test "the sandbox can still reach the public internet" {
  run exec_in "curl -sS -m 5 -o /dev/null -w '%{http_code}' http://example.com/"
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

@test "down removes the iptables rules and leaves none behind" {
  run "$SANDBOX_BIN" down "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -z "$(container_id)" ]

  local docker_user_lines input_lines
  docker_user_lines="$(sudo iptables -S DOCKER-USER | wc -l)"
  input_lines="$(sudo iptables -S INPUT | wc -l)"
  [ "$docker_user_lines" -eq "$BASELINE_DOCKER_USER_LINES" ]
  [ "$input_lines" -eq "$BASELINE_INPUT_LINES" ]
}
