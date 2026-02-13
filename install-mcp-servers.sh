#!/usr/bin/env bash
set -euo pipefail
trap 'echo "$0: line $LINENO: $BASH_COMMAND: exitcode $?"' ERR

# ABOUTME: Installs MCP servers from mcp-servers.txt with ${VAR} substitution for codex mcp add commands.

echo "Installing MCP servers..."

APP_DIR="${APP_DIR:-/app}"

if [ -f "$APP_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$APP_DIR/.env"
    set +a
    echo "Loaded environment variables from .env"
fi

if [ ! -f "$APP_DIR/mcp-servers.txt" ]; then
    echo "No mcp-servers.txt file found, skipping"
    exit 0
fi

if ! command -v codex >/dev/null 2>&1; then
    echo "Codex CLI not found, skipping MCP setup"
    exit 0
fi

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    var_names="$(echo "$line" | grep -o '\${[^}]*}' | sed 's/[${}]//g' | sort -u || true)"

    missing_vars=""
    for var in $var_names; do
        if [ -z "${!var:-}" ]; then
            missing_vars="$missing_vars $var"
        fi
    done

    if [ -n "$missing_vars" ]; then
        echo "⚠ Skipping MCP server - missing environment variables:$missing_vars"
        continue
    fi

    expanded_line="$line"
    for var in $var_names; do
        value="${!var}"
        placeholder="\${$var}"
        expanded_line="${expanded_line//"$placeholder"/$value}"
    done

    server_name=""
    if [[ "$expanded_line" =~ ^[[:space:]]*codex[[:space:]]+mcp[[:space:]]+add[[:space:]]+([^[:space:]]+) ]]; then
        server_name="${BASH_REMATCH[1]}"
    fi

    if [ -n "$server_name" ]; then
        codex mcp remove "$server_name" >/dev/null 2>&1 || true
    fi

    echo "Executing: $(echo "$expanded_line" | head -c 120)..."
    if eval "$expanded_line"; then
        echo "✓ Successfully installed MCP server"
    else
        echo "✗ Failed to install MCP server (continuing)"
    fi
    echo "---"
done < "$APP_DIR/mcp-servers.txt"

echo "MCP server installation complete"
