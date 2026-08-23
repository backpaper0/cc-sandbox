#!/usr/bin/env bats
#
# E2E tests for `bin/sandbox list` (ticket 08: sandbox list command).
# Runs against a real Docker daemon, no mocks.

load helpers

instance_name_from_project_dir() {
  printf '%s' "$(basename "$1")" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '-'
}

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
  NAME_A="list-a-$(instance_name_from_project_dir "$PROJECT_DIR_A")"
  NAME_B="list-b-$(instance_name_from_project_dir "$PROJECT_DIR_B")"
}

teardown_file() {
  "$SANDBOX_BIN" down --name "$NAME_A" >/dev/null 2>&1 || true
  "$SANDBOX_BIN" down --name "$NAME_B" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR_A" "$PROJECT_DIR_B"
}

# Runs before either instance is started (see the ordering of the other tests
# below), so this is the one place we can observe the genuinely-empty case.
@test "list reports no instances and exits 0 when none are running" {
  run "$SANDBOX_BIN" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No sandbox instances are running"* ]]
}

@test "list shows both running instances with their project dir and code-server address" {
  run "$SANDBOX_BIN" up "$PROJECT_DIR_A" --name "$NAME_A"
  [ "$status" -eq 0 ]
  run "$SANDBOX_BIN" up "$PROJECT_DIR_B" --name "$NAME_B"
  [ "$status" -eq 0 ]

  run "$SANDBOX_BIN" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"$NAME_A"* ]]
  [[ "$output" == *"$PROJECT_DIR_A"* ]]
  [[ "$output" == *"$NAME_B"* ]]
  [[ "$output" == *"$PROJECT_DIR_B"* ]]
  # code-server's published port, e.g. "127.0.0.1:32768" -- confirms a real
  # port is reported, not a placeholder.
  [[ "$output" =~ 127\.0\.0\.1:[0-9]+ ]]
}

@test "down removes an instance from the list without affecting the other" {
  run "$SANDBOX_BIN" down --name "$NAME_A"
  [ "$status" -eq 0 ]

  run "$SANDBOX_BIN" list
  [ "$status" -eq 0 ]
  [[ "$output" != *"$NAME_A"* ]]
  [[ "$output" == *"$NAME_B"* ]] || {
    echo "expected remaining instance '$NAME_B' in list output:" >&2
    echo "$output" >&2
    false
  }
}
