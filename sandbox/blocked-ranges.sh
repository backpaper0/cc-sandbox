# shellcheck shell=sh
# Sourced by both sandbox/isolate.sh and sandbox/isolate-forward.sh, never run
# directly -- the shell directive above is only so shellcheck can lint it.
#
# Shared destination list for sandbox/isolate.sh (main container) and
# sandbox/isolate-forward.sh (DinD sidecar) -- see docs/adr/0004. Kept in one
# place so a change to what counts as "host-side" can't be applied to one
# isolation boundary and silently forgotten on the other.
#
# Destinations treated as "host side":
#   RFC1918        -- the LAN and the container's own bridge gateway
#   169.254.0.0/16 -- link-local, incl. cloud metadata endpoints
#   100.64.0.0/10  -- CGNAT space, used by some Docker Desktop configurations
SANDBOX_BLOCKED_RANGES='10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10'
