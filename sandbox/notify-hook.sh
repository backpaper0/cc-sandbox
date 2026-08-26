#!/bin/bash
# Installed as ~/.local/bin/cc-sandbox-notify-hook (see sandbox/Dockerfile),
# invoked by Claude Code's Stop/Notification hooks (see
# sandbox/claude-settings.json and docs/adr/0009). Deliberately dumb: just
# appends "<event> <epoch>" to a fixed log file that the host-side "通知
# ウォッチャー" (bin/cc-sandbox's start_notify_watcher) streams via
# `docker exec ... tail -F`. Writing to a plain file rather than a FIFO is
# intentional -- a FIFO write blocks until a reader attaches, which would
# stall this hook (and so Claude Code itself) whenever the host watcher isn't
# currently attached.
set -euo pipefail

echo "$1 $(date +%s)" >>"${HOME}/.cache/cc-sandbox-notify.log"
