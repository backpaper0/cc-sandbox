#!/usr/bin/env bats
#
# E2E tests for code-server integration (ticket 04): `bin/sandbox up` starts
# code-server inside the sandbox container, reachable only from the host's
# loopback interface and behind password auth. Runs against a real Docker
# daemon, no mocks.

load helpers

setup_file() {
  export SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/sandbox"
  export PROJECT_DIR
  # Resolve symlinks: on macOS `mktemp -d` hands back a /var/... path that is really
  # a symlink into /private/var, and the CLI records the physical path it mounts.
  # Comparing the two forms below would never match.
  PROJECT_DIR="$(cd "$(mktemp -d)" && pwd -P)"
}

teardown_file() {
  "$SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR"
}

# The host-side "IP:port" code-server is published on, read the same way a
# developer would: from `bin/sandbox up`'s own output, not recomputed from the
# CLI's internal compose-project-name scheme.
code_server_addr() {
  "$SANDBOX_BIN" up "$PROJECT_DIR" | sed -n 's/^ *code-server: *http:\/\///p'
}

code_server_password() {
  docker exec -u dev "$(container_id)" grep '^password:' /home/dev/.config/code-server/config.yaml \
    | sed 's/^password: *//'
}

@test "up starts the sandbox with code-server running" {
  run "$SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -n "$(container_id)" ]

  run exec_in "curl -sS -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/"
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

@test "up's output reports a reachable code-server URL and how to fetch the password" {
  local out
  out="$("$SANDBOX_BIN" up "$PROJECT_DIR")"
  [[ "$out" == *"code-server:"*"http://127.0.0.1:"* ]]
  [[ "$out" == *"Password:"*"config.yaml"* ]]

  local addr
  addr="$(sed -n 's/^ *code-server: *http:\/\///p' <<<"$out")"
  [ -n "$addr" ]

  run curl -sS -m 5 -o /dev/null -w '%{http_code}' "http://${addr}/"
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

@test "code-server is bound to the host's loopback interface only" {
  run docker inspect "$(container_id)" --format '{{range $p, $b := .NetworkSettings.Ports}}{{if eq $p "8080/tcp"}}{{range $b}}{{.HostIp}}{{"\n"}}{{end}}{{end}}{{end}}'
  [ "$status" -eq 0 ]
  [ "$output" = "127.0.0.1" ]
}

@test "code-server requires a password to access the workspace" {
  local addr
  addr="$(code_server_addr)"

  # Without a session cookie, code-server serves its login page rather than the
  # editor UI -- the concrete, externally-observable form password auth takes.
  run curl -sS -m 5 "http://${addr}/"
  [ "$status" -eq 0 ]
  [[ "$output" == *"login"* ]]
}

@test "code-server accepts the password from its config file and rejects a wrong one" {
  local addr password
  addr="$(code_server_addr)"
  password="$(code_server_password)"
  [ -n "$password" ]

  run curl -sS -m 5 -c - -o /dev/null -w '%{http_code}' \
    --data-urlencode "password=${password}" "http://${addr}/login"
  [ "$status" -eq 0 ]
  [[ "$output" == "302" || "$output" == "200" ]]

  run curl -sS -m 5 -o /dev/null -w '%{http_code}' \
    --data-urlencode "password=definitely-wrong" "http://${addr}/login"
  [ "$status" -eq 0 ]
  [ "$output" != "302" ]
}

@test "down removes the sandbox and code-server with it" {
  run "$SANDBOX_BIN" down "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -z "$(container_id)" ]
}
