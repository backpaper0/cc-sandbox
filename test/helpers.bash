# Shared helpers for the sandbox E2E bats suites. Loaded via `load helpers`.

# Identify the sandbox container purely by the externally observable fact that
# it bind-mounts the given project dir (default: $PROJECT_DIR) at /workspace,
# rather than recomputing the CLI's internal compose-project-name/slug scheme
# (which would drift out of sync). Takes an optional project dir so multi-instance
# tests (test/multi_instance_isolation.bats) can look up more than one sandbox at
# once.
container_id() {
  local dir="${1:-${PROJECT_DIR}}"
  local cid
  for cid in $(docker ps -q --filter 'label=com.docker.compose.project'); do
    if docker inspect "${cid}" \
        --format '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{"\n"}}{{end}}{{end}}' \
        | grep -qxF "${dir}"; then
      echo "${cid}"
      return 0
    fi
  done
}

exec_in() {
  docker exec -u dev "$(container_id)" bash -lc "$1"
}

# Like exec_in, but against an explicitly given container id rather than the one
# implied by $PROJECT_DIR -- needed once more than one sandbox is up at a time.
exec_in_container() {
  docker exec -u dev "$1" bash -lc "$2"
}

# The address other containers on the same compose network would use to reach
# this one -- used by test/multi_instance_isolation.bats to build a target
# address that is known-good on its *own* network, then check it's unreachable
# from a different instance's network.
container_ip_of() {
  docker inspect "$1" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
}

# The DinD sidecar (ticket 05) shares the sandbox container's compose project, so
# it's found the same way: by that project label, filtered down to the `dind`
# service.
dind_container_id() {
  local project
  project="$(docker inspect "$(container_id)" --format '{{ index .Config.Labels "com.docker.compose.project" }}')"
  docker ps -q --filter "label=com.docker.compose.project=${project}" --filter "label=com.docker.compose.service=dind"
}

# The bridge gateway of a given container's (single) network -- the host-side
# address it can normally route to. Used by both test/network_isolation.bats (for
# the sandbox container) and test/dind_testcontainers.bats (for the dind sidecar)
# to check that isolation blocks this path regardless of which container it's
# applied to.
gateway_ip_of() {
  docker inspect "$1" --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'
}
