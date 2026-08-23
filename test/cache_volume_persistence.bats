#!/usr/bin/env bats
#
# E2E tests for shared cache volume persistence (ticket 07): mise/uv/npm/Maven live
# in named volumes shared by every sandbox instance (rather than one per instance);
# the DinD sidecar's Docker image-layer cache does too, except that a concurrently
# running instance falls back to its own instance-scoped volume instead (see
# bin/sandbox's dind_cache_volume_in_use_by_other_project). Either way, `down`
# doesn't lose these volumes, and a freshly (re)created instance reuses whatever's
# already cached instead of re-downloading it. Runs against a real Docker daemon,
# no mocks.

load helpers

# Container-side paths whose caches must be backed by a volume shared across all
# instances -- kept as one table so every test below iterates the same set instead
# of drifting out of sync with sandbox/docker-compose.yml's `sandbox` service.
CACHE_PATHS=(
  "/home/dev/.local/share/mise"
  "/home/dev/.cache/uv"
  "/home/dev/.npm"
  "/home/dev/.m2"
  "/home/dev/.cache/ms-playwright"
)

setup_file() {
  export SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/sandbox"

  export PROJECT_DIR_A PROJECT_DIR_B
  # Resolve symlinks: on macOS `mktemp -d` hands back a /var/... path that is really
  # a symlink into /private/var, and the CLI records the physical path it mounts.
  # Comparing the two forms below would never match.
  PROJECT_DIR_A="$(cd "$(mktemp -d)" && pwd -P)"
  PROJECT_DIR_B="$(cd "$(mktemp -d)" && pwd -P)"

  export NAME_A NAME_B
  NAME_A="cache-a-$(basename "$PROJECT_DIR_A")"
  NAME_B="cache-b-$(basename "$PROJECT_DIR_B")"

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

@test "mise/uv/npm/Maven/Playwright caches are the same named volume in both instances" {
  local cid_a cid_b path vol_a vol_b
  cid_a="$(container_id "$PROJECT_DIR_A")"
  cid_b="$(container_id "$PROJECT_DIR_B")"

  for path in "${CACHE_PATHS[@]}"; do
    vol_a="$(volume_name_at "$cid_a" "$path")"
    vol_b="$(volume_name_at "$cid_b" "$path")"
    [ -n "$vol_a" ]
    [ "$vol_a" = "$vol_b" ]
  done
}

@test "the DinD sidecar's Docker image-layer cache falls back to a per-instance volume when the shared one is already taken" {
  # Sharing /var/lib/docker between two *concurrently running* dind daemons hangs
  # the second one (containerd's metadata store takes an exclusive lock on it) --
  # found in review, see bin/sandbox's dind_cache_volume_in_use_by_other_project
  # and docker-compose.yml's DIND_CACHE_VOLUME comment. So instance A (started
  # first, in setup_file) claims the globally-shared volume, and instance B
  # (started next, while A is still up) must fall back to its own instance-scoped
  # one instead of contending for A's.
  local dind_a dind_b vol_a vol_b
  dind_a="$(dind_container_id "$PROJECT_DIR_A")"
  dind_b="$(dind_container_id "$PROJECT_DIR_B")"
  [ -n "$dind_a" ]
  [ -n "$dind_b" ]

  vol_a="$(volume_name_at "$dind_a" "/var/lib/docker")"
  vol_b="$(volume_name_at "$dind_b" "/var/lib/docker")"
  [ -n "$vol_a" ]
  [ -n "$vol_b" ]

  [ "$vol_a" = "sandbox-cache-docker-layers" ]
  [ "$vol_b" != "sandbox-cache-docker-layers" ]
  [ "$vol_a" != "$vol_b" ]
}

@test "two instances can write distinct files into a shared cache concurrently without conflict" {
  local cid_a cid_b
  cid_a="$(container_id "$PROJECT_DIR_A")"
  cid_b="$(container_id "$PROJECT_DIR_B")"

  exec_in_container "$cid_a" "echo from-a > /home/dev/.cache/uv/concurrent-marker-a" &
  local pid_a=$!
  exec_in_container "$cid_b" "echo from-b > /home/dev/.cache/uv/concurrent-marker-b" &
  local pid_b=$!
  wait "$pid_a"
  wait "$pid_b"

  run exec_in_container "$cid_a" "cat /home/dev/.cache/uv/concurrent-marker-a"
  [ "$status" -eq 0 ]
  [ "$output" = "from-a" ]

  run exec_in_container "$cid_b" "cat /home/dev/.cache/uv/concurrent-marker-b"
  [ "$status" -eq 0 ]
  [ "$output" = "from-b" ]

  exec_in_container "$cid_a" "rm -f /home/dev/.cache/uv/concurrent-marker-a /home/dev/.cache/uv/concurrent-marker-b"
}

# Runs last: recreates instance A, which the earlier tests' cid_a is no longer
# valid after.
@test "down leaves cache volumes in place, and a recreated instance reuses their content" {
  local cid marker_path
  cid="$(container_id "$PROJECT_DIR_A")"
  marker_path="/home/dev/.local/share/mise/sandbox-cache-marker"

  run exec_in_container "$cid" "echo cached-content > ${marker_path}"
  [ "$status" -eq 0 ]

  run "$SANDBOX_BIN" down --name "$NAME_A"
  [ "$status" -eq 0 ]

  run "$SANDBOX_BIN" up "$PROJECT_DIR_A" --name "$NAME_A"
  [ "$status" -eq 0 ]

  local new_cid
  new_cid="$(container_id "$PROJECT_DIR_A")"
  [ -n "$new_cid" ]
  [ "$new_cid" != "$cid" ]

  run exec_in_container "$new_cid" "cat ${marker_path}"
  [ "$status" -eq 0 ]
  [ "$output" = "cached-content" ]

  exec_in_container "$new_cid" "rm -f ${marker_path}"
}
