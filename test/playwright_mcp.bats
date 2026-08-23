#!/usr/bin/env bats
#
# E2E tests for Playwright MCP server integration (ticket 10). The public seam
# is bin/sandbox: tests start a real sandbox instance, then observe the MCP
# server Claude Code sees and the browser behavior it exposes. No project-level
# .mcp.json or mocked Docker/MCP components are used.

load helpers

setup_file() {
  export SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/sandbox"
  export PROJECT_DIR
  PROJECT_DIR="$(cd "$(mktemp -d)" && pwd -P)"
}

teardown_file() {
  "$SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR"
}

@test "up provides Playwright MCP in Claude Code's user scope without project configuration" {
  run "$SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]

  run exec_in "test ! -e /workspace/.mcp.json && claude mcp get playwright"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Scope: User config"* ]]
  [[ "$output" == *"playwright-mcp"* ]]
  [[ "$output" == *"--headless"* ]]
}

@test "Playwright MCP reaches a localhost dev server and takes a screenshot" {
  printf '%s\n' '<title>Ticket 10 Playwright MCP</title><h1>ready</h1>' >"${PROJECT_DIR}/index.html"
  cp "${BATS_TEST_DIRNAME}/fixtures/playwright_mcp_smoke.py" "${PROJECT_DIR}/playwright_mcp_smoke.py"

  exec_in "python3 -m http.server 4173 --bind 127.0.0.1 >/tmp/playwright-fixture.log 2>&1 &"
  run exec_in "python3 /workspace/playwright_mcp_smoke.py"
  [ "$status" -eq 0 ]

  run docker exec -u dev "$(container_id)" bash -lc \
    "find /tmp/playwright-mcp-output -maxdepth 1 -type f -name '*.png' -size +0c | grep -q ."
  [ "$status" -eq 0 ]
}

@test "down and up reuse the Playwright browser cache" {
  local cid browser_path
  cid="$(container_id)"
  browser_path="$(exec_in_container "$cid" "find /home/dev/.cache/ms-playwright -type f -name chrome -print -quit")"
  [ -n "$browser_path" ]
  exec_in_container "$cid" "printf reused > /home/dev/.cache/ms-playwright/ticket-10-marker"

  run "$SANDBOX_BIN" down "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  run "$SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]

  run exec_in "cat /home/dev/.cache/ms-playwright/ticket-10-marker"
  [ "$status" -eq 0 ]
  [ "$output" = "reused" ]
  run exec_in "test -x '$browser_path'"
  [ "$status" -eq 0 ]

  exec_in "rm -f /home/dev/.cache/ms-playwright/ticket-10-marker"
}
