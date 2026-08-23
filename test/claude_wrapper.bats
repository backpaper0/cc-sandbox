#!/usr/bin/env bats
#
# E2E tests for the claude wrapper (CONTEXT.md's "claudeラッパー"). The public
# seam is bin/sandbox: tests start a real sandbox instance, then observe how
# `claude` actually resolves and what it actually execs inside the running
# container. No mocking of Docker or of the real `claude` binary -- flag
# injection is observed via `bash -x`, which traces the wrapper's own `exec`
# call before it replaces the process, against the genuine installed script.

load helpers

setup_file() {
  export SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/sandbox"
  export PROJECT_DIR
  PROJECT_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  run "$SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]
}

teardown_file() {
  "$SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR"
}

# The exec trace line names the real binary before any of its arguments, so
# grepping the whole trace for the flags is enough to know they were passed
# to it (rather than, say, appearing only in the wrapper's own source).
traced_exec_args() {
  exec_in "bash -x \$HOME/.local/bin/claude $1 >/dev/null 2>/tmp/claude-wrapper-trace" || true
  exec_in "grep -m1 '^+ exec ' /tmp/claude-wrapper-trace"
}

@test "claude on PATH resolves to the wrapper, not the mise shim" {
  run exec_in "command -v claude"
  [ "$status" -eq 0 ]
  [ "$output" = "/home/dev/.local/bin/claude" ]
}

@test "a bare session start gets both bypass flags" {
  run traced_exec_args "--version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dangerously-skip-permissions"* ]]
  [[ "$output" == *"--permission-mode bypassPermissions"* ]]

  run exec_in "claude --version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Claude Code"* ]]
}

@test "a prompt argument still gets both bypass flags" {
  # --version is appended so the traced real invocation exits immediately
  # instead of dropping into an interactive session with no TTY attached.
  run traced_exec_args "'explain this file' --version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dangerously-skip-permissions"* ]]
  [[ "$output" == *"--permission-mode bypassPermissions"* ]]
}

@test "an explicit permission flag is passed through, not added to" {
  run traced_exec_args "--permission-mode plan --version"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--dangerously-skip-permissions"* ]]
  [[ "$output" == *"--permission-mode plan"* ]]

  run exec_in "claude --permission-mode plan --version"
  [ "$status" -eq 0 ]
}

@test "a known subcommand is passed through unchanged" {
  run traced_exec_args "mcp get playwright"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--dangerously-skip-permissions"* ]]
  [[ "$output" != *"--permission-mode"* ]]

  run exec_in "claude mcp get playwright"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Scope: User config"* ]]
}
