#!/bin/sh
# Blocks the sandbox's non-root user from reaching host-side services, while
# leaving outbound internet access intact
# (see docs/adr/0004-network-isolation-in-container-owner-match.md).
#
# The rules live inside the container (OUTPUT chain + owner match) rather than on
# the host's DOCKER-USER chain, so the same code path works whether the Docker
# daemon runs natively on Linux or inside a VM on macOS (OrbStack/Docker Desktop),
# where the host has no iptables of its own.
#
# Only the non-root user is isolated. root inside the sandbox can remove these
# rules -- and the dev user has passwordless sudo -- so this guards against
# accidental damage, not against a deliberate escape. That trade-off is accepted:
# see the ADR.
set -eu

sandbox_user="${1:-dev}"
uid="$(id -u "${sandbox_user}")"

# shellcheck source=blocked-ranges.sh
. /usr/local/sbin/sandbox-blocked-ranges
blocked="${SANDBOX_BLOCKED_RANGES}"

# OrbStack and Docker Desktop resolve host.docker.internal to an address outside
# RFC1918 (0.250.250.254 on OrbStack), so the ranges above do not cover it. It is
# the one route that actually reaches a macOS host service bound to 0.0.0.0, so
# resolve it at runtime and block it explicitly.
host_internal="$(getent ahostsv4 host.docker.internal 2>/dev/null | awk 'NR==1{print $1}' || true)"
if [ -n "${host_internal}" ]; then
  blocked="${blocked} ${host_internal}"
fi

# A dedicated chain keeps this idempotent: re-running `up` against a live sandbox
# flushes and rebuilds the rules instead of appending a second copy of them.
if iptables -n -L SANDBOX_ISOLATION >/dev/null 2>&1; then
  iptables -F SANDBOX_ISOLATION
else
  iptables -N SANDBOX_ISOLATION
fi
iptables -C OUTPUT -j SANDBOX_ISOLATION 2>/dev/null \
  || iptables -A OUTPUT -j SANDBOX_ISOLATION

# Exempt the DinD sidecar (ticket 05, docs/adr/0004's open point on ticket 05): it's
# a compose service on this same private network, but its address falls inside the
# RFC1918 ranges blocked below. Resolving it by service name and exempting just
# that address -- rather than the whole subnet -- keeps the bridge gateway itself
# blocked (see test/network_isolation.bats's gateway_ip test). Must be added before
# the REJECT rules below: iptables evaluates a chain top-down, first match wins.
#
# This script runs right after `compose up -d --build` returns, which doesn't
# guarantee the embedded DNS already has the `dind` alias registered. Retried
# rather than a single lookup, so a lost race here doesn't turn into every
# sandbox<->dind connection being rejected -- including the `docker info` check
# bin/sandbox's wait_for_dind depends on -- until the next `up`.
dind_ip=""
attempt=1
while [ -z "${dind_ip}" ] && [ "${attempt}" -le 10 ]; do
  dind_ip="$(getent ahostsv4 dind 2>/dev/null | awk 'NR==1{print $1}' || true)"
  [ -n "${dind_ip}" ] || sleep 0.5
  attempt=$((attempt + 1))
done
if [ -n "${dind_ip}" ]; then
  iptables -A SANDBOX_ISOLATION -m owner --uid-owner "${uid}" -d "${dind_ip}" -j RETURN
fi

# REJECT rather than DROP: a blocked call fails immediately instead of hanging
# until it times out, which makes an accidental hit obvious rather than looking
# like a slow network.
for range in ${blocked}; do
  iptables -A SANDBOX_ISOLATION -m owner --uid-owner "${uid}" -d "${range}" -j REJECT
done

# IPv6 is left alone: Docker gives these containers no IPv6 address or route, so
# there is nothing to block today. An IPv6-enabled daemon would need the
# equivalent ip6tables rules (fc00::/7, fe80::/10) added here.
