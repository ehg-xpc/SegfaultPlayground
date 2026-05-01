#!/bin/bash
# docker-entrypoint.sh - Initialize the container environment then exec the given command.
set -euo pipefail

# Initialize network firewall if CAP_NET_ADMIN is in our bounding capability set.
# We run as the non-root `agent` user, so `/proc/sys/net` is never writable from
# here, and our sudo allowlist only covers init-firewall.sh (not `iptables` for a
# probe). Read CapBnd directly: bit 12 is CAP_NET_ADMIN.
cap_bnd=$(awk '/^CapBnd:/ {print $2}' /proc/self/status)
if (( (0x${cap_bnd} >> 12) & 1 )); then
    sudo /usr/local/bin/init-firewall.sh
else
    echo "[entrypoint] Warning: NET_ADMIN not available, skipping firewall." >&2
fi

exec "$@"
