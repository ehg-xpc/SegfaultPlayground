#!/bin/bash
# init-firewall.sh - Lock outbound traffic to known-good endpoints only.
# Runs as root inside the container (via sudo from agent user).
# Requires --cap-add=NET_ADMIN --cap-add=NET_RAW at docker run time.
set -euo pipefail

# Domains the agent is allowed to reach
ALLOWED_DOMAINS=(
    # Claude / Anthropic
    "api.anthropic.com"
    "statsig.anthropic.com"
    "statsig.com"
    "sentry.io"
    # npm
    "registry.npmjs.org"
    # PyPI
    "pypi.org"
    "files.pythonhosted.org"
    # GitHub (git operations, gh CLI)
    "github.com"
    "api.github.com"
    "objects.githubusercontent.com"
    "raw.githubusercontent.com"
    # OpenCode
    "opencode.ai"
)

# Preserve Docker's internal DNS NAT rules before flushing
DOCKER_DNS_RULES=$(iptables-save -t nat 2>/dev/null | grep "127\.0\.0\.11" || true)

# Flush all existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# Restore Docker DNS rules
if [ -n "$DOCKER_DNS_RULES" ]; then
    iptables -t nat -N DOCKER_OUTPUT    2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
fi

# Allow loopback and established connections
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS and SSH
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT  -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT

# Allow traffic to/from the Docker host network
HOST_IP=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed 's/\.[0-9]*$/.0\/24/')
    iptables -A INPUT  -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

# Build ipset of allowed IPs from resolved domains
ipset create allowed-domains hash:net
for domain in "${ALLOWED_DOMAINS[@]}"; do
    ips=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' || true)
    for ip in $ips; do
        ipset add allowed-domains "$ip" 2>/dev/null || true
    done
done

iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Default DROP
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  DROP

# Reject remaining OUTPUT with a polite message instead of silent drop
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "[firewall] Outbound network restricted to allowed domains."
