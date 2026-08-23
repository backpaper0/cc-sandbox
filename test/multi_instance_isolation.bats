#!/usr/bin/env bats
#
# E2E tests for running multiple sandbox instances side by side (ticket 06):
# `bin/sandbox up --name <slug>` lets two instances run at once, each with its own
# Docker network and project bind mount, unreachable from each other, and `down
# --name <slug>` tears one down without touching the other. Runs against a real
# Docker daemon, no mocks.

load helpers

setup_file() {
  export SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/sandbox"

  export PROJECT_DIR_A PROJECT_DIR_B
  # Resolve symlinks: on macOS `mktemp -d` hands back a /var/... path that is really
  # a symlink into /private/var, and the CLI records the physical path it mounts.
  # Comparing the two forms below would never match.
  PROJECT_DIR_A="$(cd "$(mktemp -d)" && pwd -P)"
  PROJECT_DIR_B="$(cd "$(mktemp -d)" && pwd -P)"

  # Derived from each temp dir's own randomness, so re-running the suite never
  # collides with a leftover instance from a prior run that failed to tear down.
  export NAME_A NAME_B
  NAME_A="multi-a-$(basename "$PROJECT_DIR_A")"
  NAME_B="multi-b-$(basename "$PROJECT_DIR_B")"

  export INSTANCE_PORT=8100

  run "$SANDBOX_BIN" up "$PROJECT_DIR_A" --name "$NAME_A"
  [ "$status" -eq 0 ]
  run "$SANDBOX_BIN" up "$PROJECT_DIR_B" --name "$NAME_B"
  [ "$status" -eq 0 ]
}

teardown_file() {
  "$SANDBOX_BIN" down --name "$NAME_A" >/dev/null 2>&1 || true
  "$SANDBOX_BIN" down --name "$NAME_B" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR_A" "$PROJECT_DIR_B"
}

# The other tests below all depend on both containers existing; fail fast and
# legibly here rather than every subsequent test failing on a missing container id.
@test "up starts two named instances at the same time" {
  [ -n "$(container_id "$PROJECT_DIR_A")" ]
  [ -n "$(container_id "$PROJECT_DIR_B")" ]
}

@test "each instance has its own Docker network and its own project bind mount" {
  local cid_a cid_b network_a network_b mount_a mount_b
  cid_a="$(container_id "$PROJECT_DIR_A")"
  cid_b="$(container_id "$PROJECT_DIR_B")"

  network_a="$(docker inspect "$cid_a" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
  network_b="$(docker inspect "$cid_b" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
  [ -n "$network_a" ]
  [ -n "$network_b" ]
  [ "$network_a" != "$network_b" ]

  mount_a="$(docker inspect "$cid_a" --format '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}')"
  mount_b="$(docker inspect "$cid_b" --format '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}')"
  [ "$mount_a" = "$PROJECT_DIR_A" ]
  [ "$mount_b" = "$PROJECT_DIR_B" ]
}

@test "up refuses to reuse a --name that's already running for a different directory" {
  local other_dir
  other_dir="$(cd "$(mktemp -d)" && pwd -P)"

  run "$SANDBOX_BIN" up "$other_dir" --name "$NAME_A"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already running for a different project directory"* ]]

  # Instance A must be untouched -- still bound to its own directory, not
  # silently recreated against $other_dir.
  run docker inspect "$(container_id "$PROJECT_DIR_A")" \
    --format '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}'
  [ "$status" -eq 0 ]
  [ "$output" = "$PROJECT_DIR_A" ]

  rm -rf "$other_dir"
}

@test "a process in one instance cannot reach a service running in the other" {
  local cid_a cid_b ip_b
  cid_a="$(container_id "$PROJECT_DIR_A")"
  cid_b="$(container_id "$PROJECT_DIR_B")"
  ip_b="$(container_ip_of "$cid_b")"
  [ -n "$ip_b" ]

  exec_in_container "$cid_b" "nohup python3 -m http.server ${INSTANCE_PORT} --bind 0.0.0.0 >/tmp/httpd.log 2>&1 & disown; sleep 1"

  # Control: the server really is up, from inside its own instance.
  run exec_in_container "$cid_b" "curl -sS -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:${INSTANCE_PORT}/"
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]

  # The actual assertion: the other instance can't reach it, even by IP.
  run exec_in_container "$cid_a" "curl -sS -m 3 -o /dev/null -w '%{http_code}' http://${ip_b}:${INSTANCE_PORT}/"
  [ "$status" -ne 0 ]
}

@test "tearing down one instance leaves the other running" {
  run "$SANDBOX_BIN" down --name "$NAME_A"
  [ "$status" -eq 0 ]
  [ -z "$(container_id "$PROJECT_DIR_A")" ]

  local cid_b
  cid_b="$(container_id "$PROJECT_DIR_B")"
  [ -n "$cid_b" ]
  run exec_in_container "$cid_b" "curl -sS -m 10 -o /dev/null -w '%{http_code}' http://example.com/"
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}
