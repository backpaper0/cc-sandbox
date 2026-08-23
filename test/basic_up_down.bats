#!/usr/bin/env bats
#
# E2E tests for `bin/sandbox up` / `bin/sandbox down` (ticket 01: basic up/down).
# Runs against a real Docker daemon, no mocks.

setup_file() {
  export SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/sandbox"
  export PROJECT_DIR
  PROJECT_DIR="$(mktemp -d)"
}

teardown_file() {
  "$SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR"
}

# Identify the sandbox container purely by the externally observable fact that
# it bind-mounts $PROJECT_DIR at /workspace, rather than recomputing the CLI's
# internal compose-project-name/slug scheme (which would drift out of sync).
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

exec_in() {
  docker exec -u dev "$(container_id)" bash -lc "$1"
}

@test "up starts the sandbox container" {
  run "$SANDBOX_BIN" up "$PROJECT_DIR"
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
  owner="$(awk 'NR==2{print $1}' <<<"$output")"
  [ "$owner" != "root" ]
  [ "$owner" = "dev" ]
}

@test "dev user has passwordless sudo" {
  run exec_in "sudo -n whoami"
  [ "$status" -eq 0 ]
  [ "$output" = "root" ]
}

@test "down removes the container and compose resources" {
  run "$SANDBOX_BIN" down "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ -z "$(container_id)" ]
}
