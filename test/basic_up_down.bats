#!/usr/bin/env bats
#
# E2E tests for `bin/cc-sandbox up` / `bin/cc-sandbox down` (ticket 01: basic up/down).
# Runs against a real Docker daemon, no mocks.

load helpers

setup_file() {
  export CC_SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/cc-sandbox"
  export PROJECT_DIR
  # Resolve symlinks: on macOS `mktemp -d` hands back a /var/... path that is really
  # a symlink into /private/var, and the CLI records the physical path it mounts.
  # Comparing the two forms below would never match.
  PROJECT_DIR="$(cd "$(mktemp -d)" && pwd -P)"
}

teardown_file() {
  "$CC_SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR"
}

@test "up starts the sandbox container" {
  run "$CC_SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -n "$(container_id)" ]
}

@test "mise, uv, python, java, node, vim are on PATH" {
  for tool_cmd in "mise --version" "uv --version" "python3 --version" "java -version" "node --version" "vim --version"; do
    run exec_in "$tool_cmd"
    [ "$status" -eq 0 ]
  done
}

@test "project directory is bind-mounted read-write" {
  echo "hello from host" > "${PROJECT_DIR}/host-file.txt"
  run exec_in "cat /workspace/host-file.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello from host"* ]]

  run exec_in "echo 'hello from sandbox' > /workspace/sandbox-file.txt"
  [ "$status" -eq 0 ]
  [ -f "${PROJECT_DIR}/sandbox-file.txt" ]
}

@test "container's initial process runs as a non-root user" {
  run docker top "$(container_id)"
  [ "$status" -eq 0 ]
  # docker top resolves the uid against the *daemon host's* passwd db, not the
  # container's, so the owner column reads "dev" on some hosts and the bare uid
  # on others. Only the non-rootness of it is portable.
  owner="$(awk 'NR==2{print $1}' <<<"$output")"
  [ "$owner" != "root" ]
  [ "$owner" != "0" ]

  # Pin the identity itself to what the image declares, which every host agrees on.
  run docker inspect "$(container_id)" --format '{{.Config.User}}'
  [ "$status" -eq 0 ]
  [ "$output" = "dev" ]
}

@test "dev user has passwordless sudo" {
  run exec_in "sudo -n whoami"
  [ "$status" -eq 0 ]
  [ "$output" = "root" ]
}

@test "down removes the container and compose resources" {
  run "$CC_SANDBOX_BIN" down "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -z "$(container_id)" ]
}
