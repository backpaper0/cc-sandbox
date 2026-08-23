#!/usr/bin/env bats
#
# E2E tests for auth profile injection (ticket 03): `bin/sandbox up --profile
# <private|work>` loads a host-side ~/.sandbox/env.<profile> file and injects its
# variables into the sandbox container. Runs against a real Docker daemon, no mocks.

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
}

teardown_file() {
  HOME="${FAKE_HOME}" "$SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
  rm -rf "$PROJECT_DIR" "$FAKE_HOME"
}

teardown() {
  "$SANDBOX_BIN" down "$PROJECT_DIR" >/dev/null 2>&1 || true
}

@test "up --profile private injects the OAuth token and claude runs with no interactive login" {
  run env HOME="$FAKE_HOME" DOCKER_CONFIG="$DOCKER_CONFIG" "$SANDBOX_BIN" up "$PROJECT_DIR" --profile private
  [ "$status" -eq 0 ]

  run exec_in "printenv CLAUDE_CODE_OAUTH_TOKEN"
  [ "$status" -eq 0 ]
  [ "$output" = "test-oauth-token-value" ]

  run exec_in "claude --version"
  [ "$status" -eq 0 ]
}

@test "up --profile work injects the Bedrock env vars" {
  run env HOME="$FAKE_HOME" DOCKER_CONFIG="$DOCKER_CONFIG" "$SANDBOX_BIN" up "$PROJECT_DIR" --profile work
  [ "$status" -eq 0 ]

  run exec_in "printenv CLAUDE_CODE_USE_BEDROCK"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run exec_in "printenv AWS_BEARER_TOKEN_BEDROCK"
  [ "$status" -eq 0 ]
  [ "$output" = "test-bedrock-key-value" ]
}

@test "up without --profile injects no auth env vars" {
  run "$SANDBOX_BIN" up "$PROJECT_DIR"
  [ "$status" -eq 0 ]

  run exec_in "printenv CLAUDE_CODE_OAUTH_TOKEN"
  [ "$status" -ne 0 ]

  run exec_in "printenv CLAUDE_CODE_USE_BEDROCK"
  [ "$status" -ne 0 ]
}

@test "up --profile with an unknown profile name fails clearly" {
  run env HOME="$FAKE_HOME" DOCKER_CONFIG="$DOCKER_CONFIG" "$SANDBOX_BIN" up "$PROJECT_DIR" --profile bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown profile"* ]]
}

@test "up --profile with a missing profile file fails clearly instead of silently skipping injection" {
  local empty_home
  empty_home="$(mktemp -d)"

  run env HOME="$empty_home" DOCKER_CONFIG="$DOCKER_CONFIG" "$SANDBOX_BIN" up "$PROJECT_DIR" --profile private
  [ "$status" -ne 0 ]
  [[ "$output" == *"env.private"* ]]

  rm -rf "$empty_home"
}

@test "up --profile with an empty value fails clearly instead of silently skipping injection" {
  run env HOME="$FAKE_HOME" DOCKER_CONFIG="$DOCKER_CONFIG" "$SANDBOX_BIN" up "$PROJECT_DIR" --profile ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-empty"* ]]

  run env HOME="$FAKE_HOME" DOCKER_CONFIG="$DOCKER_CONFIG" "$SANDBOX_BIN" up "$PROJECT_DIR" --profile=
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-empty"* ]]
}
