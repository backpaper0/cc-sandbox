# Shared helpers for the sandbox E2E bats suites. Loaded via `load helpers`.

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
