#!/usr/bin/env bats
#
# E2E tests for auth profile injection (ticket 03, extended by ticket 11 to allow
# arbitrary profile names): `bin/sandbox up --profile <name>` loads a host-side
# ~/.sandbox/env.<name> file and injects its variables into the sandbox container.
# Runs against a real Docker daemon, no mocks.

load helpers

setup_file() {
  export SANDBOX_BIN="${BATS_TEST_DIRNAME}/../bin/sandbox"
  export DOCKER_CONFIG="${DOCKER_CONFIG:-${HOME}/.docker}"
  export PROJECT_DIR
  # Resolve symlinks: on macOS `mktemp -d` hands back a /var/... path that is really
  # a symlink into /private/var, and the CLI records the physical path it mounts.
  # Comparing the two forms below would never match.
  PROJECT_DIR="$(cd "$(mktemp -d)" && pwd -P)"

  # A fake $HOME so these tests never touch the real developer's ~/.sandbox.
  # bin/sandbox resolves profile files from $HOME at runtime, so overriding it on
  # invocation is enough -- no code under test needs to know this is a test.
  export FAKE_HOME
  FAKE_HOME="$(mktemp -d)"
  mkdir -p "${FAKE_HOME}/.sandbox"
  echo "CLAUDE_CODE_OAUTH_TOKEN=test-oauth-token-value" > "${FAKE_HOME}/.sandbox/env.private"
  {
    echo "CLAUDE_CODE_USE_BEDROCK=1"
    echo "AWS_BEARER_TOKEN_BEDROCK=test-bedrock-key-value"
    echo "AWS_REGION=us-east-1"
  } > "${FAKE_HOME}/.sandbox/env.work"
  echo "CLAUDE_CODE_OAUTH_TOKEN=test-client-a-token-value" > "${FAKE_HOME}/.sandbox/env.client-a"
}

teardown_file() {
  HOME="${FAKE_HOME}" "$SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR" "$FAKE_HOME"
}

teardown() {
  "$SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
}

sandbox_up_with_home() {
  local sandbox_home="$1"
  shift
  env HOME="$sandbox_home" DOCKER_CONFIG="$DOCKER_CONFIG" \
    "$SANDBOX_BIN" up "$PROJECT_DIR" "$@"
}

@test "up --profile private injects the OAuth token and claude runs with no interactive login" {
  run sandbox_up_with_home "$FAKE_HOME" --profile private
  [ "$status" -eq 0 ]

  run exec_in "printenv CLAUDE_CODE_OAUTH_TOKEN"
  [ "$status" -eq 0 ]
  [ "$output" = "test-oauth-token-value" ]

  run exec_in "claude --version"
  [ "$status" -eq 0 ]
}

@test "up --profile work injects the Bedrock env vars" {
  run sandbox_up_with_home "$FAKE_HOME" --profile work
  [ "$status" -eq 0 ]

  run exec_in "printenv CLAUDE_CODE_USE_BEDROCK"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run exec_in "printenv AWS_BEARER_TOKEN_BEDROCK"
  [ "$status" -eq 0 ]
  [ "$output" = "test-bedrock-key-value" ]
}

@test "up --profile with an arbitrary (non-private/work) name injects that profile's env vars" {
  run sandbox_up_with_home "$FAKE_HOME" --profile client-a
  [ "$status" -eq 0 ]

  run exec_in "printenv CLAUDE_CODE_OAUTH_TOKEN"
  [ "$status" -eq 0 ]
  [ "$output" = "test-client-a-token-value" ]
}

@test "up without --profile injects no auth env vars" {
  run "$SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]

  run exec_in "printenv CLAUDE_CODE_OAUTH_TOKEN"
  [ "$status" -ne 0 ]

  run exec_in "printenv CLAUDE_CODE_USE_BEDROCK"
  [ "$status" -ne 0 ]
}

@test "up --profile with a name containing unsafe characters fails clearly" {
  run sandbox_up_with_home "$FAKE_HOME" --profile "../etc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid profile name"* ]]
}

@test "up --profile with a missing profile file fails clearly instead of silently skipping injection" {
  local empty_home
  empty_home="$(mktemp -d)"

  run sandbox_up_with_home "$empty_home" --profile private
  [ "$status" -ne 0 ]
  [[ "$output" == *"env.private"* ]]

  rm -rf "$empty_home"
}

@test "up --profile with an empty value fails clearly instead of silently skipping injection" {
  run sandbox_up_with_home "$FAKE_HOME" --profile ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-empty"* ]]

  run sandbox_up_with_home "$FAKE_HOME" --profile=
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-empty"* ]]
}
