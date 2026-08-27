#!/bin/sh
# Blocks containers started inside the DinD sidecar (Testcontainers, manually-run
# service containers) from reaching host-side services, mirroring sandbox/isolate.sh's
# blocked destinations for the main container (see docs/adr/0004, ticket 05).
#
# Nested containers' egress is NAT'd by the nested dockerd and forwarded out this
# container's own outward-facing interface, so it never passes through the OUTPUT
# chain the way isolate.sh's traffic does -- there is no local "process" here to
# owner-match against. The FORWARD chain is what actually carries it.
#
# Restricting the block to that one interface isn't enough on its own to leave the
# *opposite* direction alone -- the sandbox container reaching a nested container's
# published port. That connection's reply traffic (e.g. a Testcontainers client
# reading back from the container it just started) is forwarded from the nested
# bridge back out this same outward interface toward the sandbox container -- and
# the sandbox container's own address, on this same compose network, also falls
# inside 172.16.0.0/12. The ESTABLISHED,RELATED accept below (checked before the
# blocked-ranges loop) is what actually leaves that path alone: a nested
# container's own *new* outbound connection to a host service is NEW at the point
# its first packet is evaluated, so it isn't covered by this exception the sandbox
# container's connections already are.
set -eu

# Resolved at runtime rather than assumed to be "eth0": this container is only
# ever attached to the one compose network sandbox/compose.yaml puts it on,
# so its default route names that interface, whatever Docker happens to call it.
egress_iface="$(ip -o route show default 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n1)"
if [ -z "${egress_iface}" ]; then
  echo "cc-sandbox-isolate-forward: DinDサイドカーのegressインターフェースを特定できませんでした" >&2
  exit 1
fi

# shellcheck source=blocked-ranges.sh
. /usr/local/sbin/cc-sandbox-blocked-ranges
blocked="${SANDBOX_BLOCKED_RANGES}"

# Same OrbStack/Docker Desktop bypass as isolate.sh. Uses "hosts" rather than
# "ahostsv4" (as isolate.sh does): this image's musl/BusyBox getent doesn't
# support the "ahostsv4" database, only "hosts".
host_internal="$(getent hosts host.docker.internal 2>/dev/null \
  | awk '{print $1}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | head -n1 || true)"
if [ -n "${host_internal}" ]; then
  blocked="${blocked} ${host_internal}"
fi

# A dedicated chain keeps this idempotent, same as isolate.sh.
if iptables -n -L SANDBOX_ISOLATION_FWD >/dev/null 2>&1; then
  iptables -F SANDBOX_ISOLATION_FWD
else
  iptables -N SANDBOX_ISOLATION_FWD
fi

# Must be inserted at position 1, not appended: the nested dockerd running in this
# container installs its own DOCKER-USER/DOCKER-FORWARD chains ahead of anything
# appended to FORWARD, and those ACCEPT nested containers' traffic outright --
# an ACCEPT verdict stops netfilter's chain traversal right there, so an appended
# rule after them would never even see the packet. Delete-then-insert (rather than
# a -C/-A idempotency check like isolate.sh's) so re-running this always puts us
# back at the top, even if the nested dockerd re-populates its own chains first.
iptables -D FORWARD -j SANDBOX_ISOLATION_FWD 2>/dev/null || true
iptables -I FORWARD 1 -j SANDBOX_ISOLATION_FWD

iptables -A SANDBOX_ISOLATION_FWD -o "${egress_iface}" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

for range in ${blocked}; do
  iptables -A SANDBOX_ISOLATION_FWD -o "${egress_iface}" -d "${range}" -j REJECT
done
