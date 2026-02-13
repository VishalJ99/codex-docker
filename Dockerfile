# ABOUTME: Docker image for Codex CLI with optional MCP setup
# ABOUTME: Provides isolated Codex environment with host project, conda, GPU, and SSH access.

FROM node:20.18.1-slim

RUN deluser node || true
RUN delgroup node || true

RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    python3 \
    python3-pip \
    build-essential \
    sudo \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

ARG SYSTEM_PACKAGES=""
RUN if [ -n "$SYSTEM_PACKAGES" ]; then \
    echo "Installing additional system packages: $SYSTEM_PACKAGES" && \
    apt-get update && \
    apt-get install -y $SYSTEM_PACKAGES && \
    rm -rf /var/lib/apt/lists/*; \
else \
    echo "No additional system packages specified"; \
fi

ARG USER_UID=1000
ARG USER_GID=1000
RUN if getent group $USER_GID > /dev/null 2>&1; then \
        GROUP_NAME=$(getent group $USER_GID | cut -d: -f1); \
    else \
        groupadd -g $USER_GID codex-user && GROUP_NAME=codex-user; \
    fi && \
    useradd -m -s /bin/bash -u $USER_UID -g $GROUP_NAME codex-user && \
    echo "codex-user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

WORKDIR /app

ARG CODEX_VERSION=""
RUN if [ -n "$CODEX_VERSION" ]; then \
        echo "Installing Codex CLI version: $CODEX_VERSION" && \
        npm install -g @openai/codex@$CODEX_VERSION; \
    else \
        echo "Installing latest Codex CLI" && \
        npm install -g @openai/codex; \
    fi

ENV PATH="/usr/local/bin:${PATH}"

RUN mkdir -p /app/.codex /home/codex-user/.codex

COPY src/startup.sh /app/
COPY install-mcp-servers.sh /app/
COPY mcp-servers.txt /app/
COPY .codex /app/.codex
COPY .env /app/.env

RUN chmod +x /app/startup.sh /app/install-mcp-servers.sh
RUN chown -R codex-user /app /home/codex-user

USER codex-user
ENV HOME=/home/codex-user

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/home/codex-user/.local/bin:${PATH}"

ARG GIT_USER_NAME=""
ARG GIT_USER_EMAIL=""
RUN if [ -n "$GIT_USER_NAME" ] && [ -n "$GIT_USER_EMAIL" ]; then \
        echo "Configuring git user from host: $GIT_USER_NAME <$GIT_USER_EMAIL>" && \
        git config --global user.name "$GIT_USER_NAME" && \
        git config --global user.email "$GIT_USER_EMAIL" && \
        echo "Git configuration complete"; \
    else \
        echo "Warning: No git user configured on host system"; \
    fi

WORKDIR /workspace
ENV NODE_ENV=production

ENTRYPOINT ["/app/startup.sh"]
