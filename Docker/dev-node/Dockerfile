FROM ubuntu:22.04

# Avoid interactive prompts during package install
ENV DEBIAN_FRONTEND=noninteractive

# Install system packages + NodeSource Node.js 20 LTS + GitHub CLI + micro + glow + firewall tools
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
    # GitHub CLI
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
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

# Install OpenCode CLI via npm
RUN npm install -g opencode-ai

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
ENV EDITOR=micro
WORKDIR /home/agent

# Install Claude Code via the native installer (installs to ~/.local/bin/claude)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Launch into a regular shell -- not an agent CLI session
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash"]
