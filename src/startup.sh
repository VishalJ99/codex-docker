#!/usr/bin/env bash
set -euo pipefail
trap 'echo "$0: line $LINENO: $BASH_COMMAND: exitcode $?"' ERR

# ABOUTME: Startup script for codex-docker container
# ABOUTME: Loads optional env file, initializes ~/.codex template, installs MCPs once, then starts Codex in YOLO mode.

if [ -f /app/.env ]; then
    echo "Loading environment from baked-in .env file"
    set -a
    # shellcheck disable=SC1091
    source /app/.env 2>/dev/null || true
    set +a
else
    echo "WARNING: No .env file found in image."
fi

mkdir -p "$HOME/.codex"

if [ -f /app/.codex/config.toml ] && [ ! -f "$HOME/.codex/config.toml" ]; then
    cp /app/.codex/config.toml "$HOME/.codex/config.toml"
    echo "✓ Seeded default Codex config at $HOME/.codex/config.toml"
fi

if [ -f "$HOME/.codex/auth.json" ]; then
    echo "Found existing Codex authentication"
else
    echo "No existing Codex authentication found"
    echo "Log in inside container with one of:"
    echo "  codex login"
    echo "  printenv OPENAI_API_KEY | codex login --with-api-key"
fi

MCP_MARKER="$HOME/.codex/.mcp_servers_installed"
if [ -f "$MCP_MARKER" ] && [ "${FORCE_MCP_REINSTALL:-0}" != "1" ]; then
    echo "✓ MCP servers already initialized"
else
    echo "Initializing MCP servers..."
    if [ -x /app/install-mcp-servers.sh ]; then
        /app/install-mcp-servers.sh || true
    else
        echo "MCP installer script not found at /app/install-mcp-servers.sh (skipping)"
    fi
    touch "$MCP_MARKER"
fi

YOLO_FLAG="--dangerously-bypass-approvals-and-sandbox"

if [ "${CODEX_CONTINUE_FLAG:-}" = "--continue" ]; then
    echo "Starting Codex CLI (resume --last) in YOLO mode..."
    exec codex "$YOLO_FLAG" resume --last "$@"
fi

echo "Starting Codex CLI in YOLO mode..."
exec codex "$YOLO_FLAG" "$@"
