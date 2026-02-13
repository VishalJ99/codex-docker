# MCP Server Management (Codex)

This project configures MCP servers through `codex mcp add` commands listed in `mcp-servers.txt`.

## How It Works

1. `src/startup.sh` runs `install-mcp-servers.sh` on first container startup.
2. `install-mcp-servers.sh` reads `mcp-servers.txt`.
3. `${VAR}` placeholders are resolved from `/app/.env`.
4. Existing server names are removed then re-added, so updates are clean.

Installed MCP config is stored in the persistent mount:
- `${CODEX_DOCKER_HOME:-~/.codex-docker}/codex-home/config.toml`

## Command Format

Use one command per line:

```bash
codex mcp add <name> -- <command> <args>
codex mcp add <name> --url <http_mcp_url>
```

Use `${ENV_VAR}` placeholders for secrets when needed.

## Reinstall MCP Servers

```bash
FORCE_MCP_REINSTALL=1 codex-docker
```

## Current Defaults

- `serena` (stdio)
- `context7` (stdio via `@upstash/context7-mcp`)
- `twilio` (stdio, conditional on `TWILIO_*` vars)
- `grep` (HTTP)
