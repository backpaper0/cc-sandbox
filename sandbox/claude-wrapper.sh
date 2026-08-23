#!/bin/bash
# Installed as ~/.local/bin/claude (see Dockerfile), ahead of the mise-managed
# `claude` shim in PATH -- ~/.local/bin is already first on PATH for `uv`'s
# sake, so no new PATH entry is needed. See CONTEXT.md's "claudeラッパー".
#
# The sandbox exists to make bypass-permissions mode safe to run (see
# README), so a bare session start defaults to it. Passed straight through to
# the real binary, unchanged, when:
#   - the first argument is a known top-level subcommand (claude mcp add,
#     claude doctor, ...)
#   - any argument already names a permission-related flag itself
#
# $REAL_CLAUDE is resolved via $HOME rather than searched for on PATH, since
# this script's own directory is first on PATH -- searching would just find
# itself again.
set -euo pipefail

REAL_CLAUDE="$HOME/.local/share/mise/shims/claude"

KNOWN_SUBCOMMANDS=(
  agents auth auto-mode doctor gateway import install mcp
  plugin plugins project setup-token ultrareview update upgrade
)

if [ "$#" -gt 0 ]; then
  for cmd in "${KNOWN_SUBCOMMANDS[@]}"; do
    if [ "$1" = "$cmd" ]; then
      exec "$REAL_CLAUDE" "$@"
    fi
  done
fi

for arg in "$@"; do
  case "$arg" in
    --dangerously-skip-permissions | --allow-dangerously-skip-permissions | --permission-mode | --permission-mode=*)
      exec "$REAL_CLAUDE" "$@"
      ;;
  esac
done

exec "$REAL_CLAUDE" --dangerously-skip-permissions --permission-mode bypassPermissions "$@"
