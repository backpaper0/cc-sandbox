#!/bin/bash
# Starts code-server in the background before handing off to the container's
# real command (see ticket 04: code-server integration).
#
# --bind-addr 0.0.0.0:8080 (rather than code-server's loopback-only default) is
# required for docker-compose.yml's "127.0.0.1::PORT" port publish to reach it at
# all: Docker's port forwarding targets the container's bridge-network address,
# not its loopback interface. The 127.0.0.1-only restriction that the ticket
# actually asks for is enforced on the host side by that port publish, not here.
#
# No config file is written here: code-server auto-generates
# ~/.config/code-server/config.yaml with password auth and a random password on
# first run if one doesn't already exist, which is exactly the "password
# required, retrievable after the fact" behavior the ticket wants.
set -euo pipefail

# The Playwright cache is a persistent named volume. New volumes are seeded from
# the image, while volumes created before ticket 10 may be empty; flock also
# prevents two concurrently-starting instances from downloading into the shared
# cache at the same time.
mkdir -p "${HOME}/.cache/ms-playwright"
(
  flock 9
  playwright install chromium
) 9>"${HOME}/.cache/ms-playwright/.install.lock"

code-server --bind-addr 0.0.0.0:8080 /workspace >/tmp/code-server.log 2>&1 &

exec "$@"
