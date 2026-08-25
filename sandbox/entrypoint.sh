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

# Corporate CA certificate for the mise-managed JDK (ticket 12, ADR-0007): the
# JDK's default cacerts lives inside the mise cache volume
# (cc-sandbox-cache-mise), which persists once created, so importing into it
# directly wouldn't survive a later image rebuild. Instead, generate a fresh
# trust store (default CAs + the corporate one) into the container's writable
# layer -- which *does* get recreated on every `up --build` -- on every
# container start, and point Java at it via JAVA_TOOL_OPTIONS.
#
# Exporting that var here would only reach this entrypoint's own process tree,
# not a later `docker exec -it -u dev <container> bash` session (docker exec
# doesn't inherit a live PID 1 shell's env, only the image/container's
# configured env), so it's appended to ~/.bashrc instead, which such a session
# -- an interactive, non-login shell -- sources automatically. No-op (~/.bashrc
# untouched) when there's no corporate CA certificate.
#
# The append is guarded by a grep check rather than unconditional, since
# `up`/`down` always recreate the container's writable layer (see above) but a
# plain `docker restart` on the same container does not -- entrypoint.sh would
# otherwise re-run against the same ~/.bashrc and grow a duplicate export line
# on every restart (found in review).
CA_CERT=/usr/local/share/ca-certificates/cc-sandbox-ca.crt
if [ -s "${CA_CERT}" ]; then
  java_home="$(mise where java)"
  trust_store="${HOME}/.cache/cc-sandbox-cacerts"
  mkdir -p "$(dirname "${trust_store}")"
  cp "${java_home}/lib/security/cacerts" "${trust_store}"
  keytool -importcert -noprompt \
    -alias cc-sandbox-corporate-ca \
    -keystore "${trust_store}" \
    -storepass changeit \
    -file "${CA_CERT}"
  if ! grep -q '^export JAVA_TOOL_OPTIONS=' "${HOME}/.bashrc" 2>/dev/null; then
    echo "export JAVA_TOOL_OPTIONS=\"-Djavax.net.ssl.trustStore=${trust_store} -Djavax.net.ssl.trustStorePassword=changeit\"" >> "${HOME}/.bashrc"
  fi
fi

code-server --bind-addr 0.0.0.0:8080 /workspace >/tmp/code-server.log 2>&1 &

exec "$@"
