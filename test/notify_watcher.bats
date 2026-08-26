#!/usr/bin/env bats
#
# E2E tests for the notify watcher (CONTEXT.md's "通知ウォッチャー", docs/adr/0009).
# Runs against a real Docker daemon, no mocks: hooks are invoked by hand
# (`cc-sandbox-notify-hook`) rather than by a genuine Claude Code turn, since
# driving a real Stop/idle_prompt hook firing needs a live session. This is the
# same seam claude_wrapper.bats uses for the wrapper's own flag injection.
#
# What the OS-native notification itself actually looks like (Notification
# Center on macOS, the WSL2 PowerShell balloon) is not verified here -- there's
# no GUI in this suite's CI environment, the same platform-scope limitation
# docs/e2e-testing.md already documents for macOS host-routing. What's verified
# is the pipeline up to (and including) the decision to notify: hook -> log file
# -> host watcher detection -> cooldown.

load helpers

# Mirrors bin/cc-sandbox's own sanitize_name/to_dash_charset (see
# test/sandbox_list.bats): --name is normalized to lowercase letters, digits,
# and dashes before it becomes the instance's actual project name, so a NAME_*
# built from mktemp -d's raw basename (which contains '.' and possibly
# uppercase) would never match what `list`/notify_state_paths actually use
# unless normalized here the same way first.
instance_name_from_project_dir() {
  printf '%s' "$(basename "$1")" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '-'
}

setup_file() {
  export CC_SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/cc-sandbox"

  export PROJECT_DIR_A PROJECT_DIR_B PROJECT_DIR_C
  PROJECT_DIR_A="$(cd "$(mktemp -d)" && pwd -P)"
  PROJECT_DIR_B="$(cd "$(mktemp -d)" && pwd -P)"
  PROJECT_DIR_C="$(cd "$(mktemp -d)" && pwd -P)"

  export NAME_A NAME_B NAME_C
  NAME_A="notify-a-$(instance_name_from_project_dir "$PROJECT_DIR_A")"
  NAME_B="notify-b-$(instance_name_from_project_dir "$PROJECT_DIR_B")"
  NAME_C="notify-c-$(instance_name_from_project_dir "$PROJECT_DIR_C")"
}

teardown_file() {
  "$CC_SANDBOX_BIN" down --name "$NAME_A" >/dev/null 2>&1 || true
  "$CC_SANDBOX_BIN" down --name "$NAME_B" >/dev/null 2>&1 || true
  "$CC_SANDBOX_BIN" down --name "$NAME_C" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR_A" "$PROJECT_DIR_B" "$PROJECT_DIR_C"
}

# The watcher's log file, keyed the same way bin/cc-sandbox's own
# notify_state_paths does (host-side ~/.cc-sandbox/run/<project-name>.log).
watcher_log_for() {
  echo "${HOME}/.cc-sandbox/run/cc-sandbox-$1.log"
}

wait_for_line_in_log() {
  local log_file="$1"
  local needle="$2"
  for _ in $(seq 1 30); do
    if [[ -f "${log_file}" ]] && grep -qF "${needle}" "${log_file}"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

@test "list shows the notify watcher as running after up" {
  run "$CC_SANDBOX_BIN" up "$PROJECT_DIR_A" --name "$NAME_A"
  [ "$status" -eq 0 ]

  run "$CC_SANDBOX_BIN" list
  [ "$status" -eq 0 ]
  [[ "$output" =~ ${NAME_A}[[:space:]]+.*running ]]
}

@test "the notify hook's Stop event reaches the host watcher's log" {
  run exec_in_container "$(container_id "$PROJECT_DIR_A")" \
    '/home/dev/.local/bin/cc-sandbox-notify-hook stop'
  [ "$status" -eq 0 ]

  run wait_for_line_in_log "$(watcher_log_for "$NAME_A")" "notified: stop"
  [ "$status" -eq 0 ]
}

@test "idle_prompt notifications are rate-limited within the cooldown window" {
  export CC_SANDBOX_NOTIFY_COOLDOWN_SECONDS=2
  run "$CC_SANDBOX_BIN" up "$PROJECT_DIR_B" --name "$NAME_B"
  [ "$status" -eq 0 ]

  local log_file
  log_file="$(watcher_log_for "$NAME_B")"

  run exec_in_container "$(container_id "$PROJECT_DIR_B")" \
    '/home/dev/.local/bin/cc-sandbox-notify-hook idle_prompt'
  [ "$status" -eq 0 ]
  run wait_for_line_in_log "$log_file" "notified: idle_prompt"
  [ "$status" -eq 0 ]

  local count_before
  count_before="$(grep -cF "notified: idle_prompt" "$log_file")"

  # Immediately within the cooldown window: should be swallowed, not appended.
  run exec_in_container "$(container_id "$PROJECT_DIR_B")" \
    '/home/dev/.local/bin/cc-sandbox-notify-hook idle_prompt'
  [ "$status" -eq 0 ]
  sleep 1
  local count_after
  count_after="$(grep -cF "notified: idle_prompt" "$log_file")"
  [ "$count_after" -eq "$count_before" ]
}

@test "--no-notify skips starting the watcher" {
  run "$CC_SANDBOX_BIN" up "$PROJECT_DIR_C" --name "$NAME_C" --no-notify
  [ "$status" -eq 0 ]

  run "$CC_SANDBOX_BIN" list
  [ "$status" -eq 0 ]
  [[ "$output" =~ ${NAME_C}[[:space:]]+.*disabled ]]
}

@test "down stops the watcher" {
  local pids_file="${HOME}/.cc-sandbox/run/cc-sandbox-${NAME_A}.pids"
  [ -f "$pids_file" ]
  local exec_pid loop_pid _fifo
  read -r exec_pid loop_pid _fifo <"$pids_file"

  run "$CC_SANDBOX_BIN" down --name "$NAME_A"
  [ "$status" -eq 0 ]

  ! kill -0 "$exec_pid" 2>/dev/null
  ! kill -0 "$loop_pid" 2>/dev/null
  [ ! -f "$pids_file" ]
}
