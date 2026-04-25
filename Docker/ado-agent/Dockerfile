FROM ubuntu:22.04

# Avoid interactive prompts during package install
ENV DEBIAN_FRONTEND=noninteractive

# Install system packages + NodeSource Node.js 20 LTS + Azure CLI + micro + glow + firewall tools
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dnsutils \
        git \
        gnupg \
        iproute2 \
        ipset \
        iptables \
        jq \
        lsb-release \
        python3 \
        sudo \
    # Node.js 20 LTS
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    # Azure CLI
    && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    # micro editor
    && curl -fsSL https://getmic.ro | bash \
    && mv micro /usr/local/bin/micro \
    # glow (Charm apt repo)
    && curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /usr/share/keyrings/charm.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list \
    && apt-get update && apt-get install -y --no-install-recommends glow \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install uv (matches host tooling convention)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# Create non-root user and copy uv install
RUN useradd -m -s /bin/bash agent \
    && cp -r /root/.local /home/agent/.local \
    && chown -R agent:agent /home/agent/.local

# Copy and configure firewall script + entrypoint
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/docker-entrypoint.sh \
    && echo "agent ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" \
       > /etc/sudoers.d/agent-firewall \
    && chmod 0440 /etc/sudoers.d/agent-firewall

# Create persistent Claude config directory
RUN mkdir -p /home/agent/.claude && chown agent:agent /home/agent/.claude

USER agent
ENV PATH="/home/agent/.local/bin:${PATH}"
ENV CLAUDE_CONFIG_DIR=/home/agent/.claude
WORKDIR /home/agent

# Install Claude Code via the native installer (installs to ~/.local/bin/claude).
# Run as `agent` so it lands under /home/agent, and matches the host convention.
RUN curl -fsSL https://claude.ai/install.sh | bash

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
