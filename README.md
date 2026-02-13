# Codex Docker

Containerized drop-in equivalent of the Claude Docker workflow, but running OpenAI Codex CLI.

It keeps the same wrapper API style and setup patterns:
- isolated Docker runtime
- current project mounted at `/workspace`
- persistent agent home on host
- optional conda mounts
- optional GPU access
- host/port access (`--network host` by default on Linux)

## Prerequisites

Required:
- Docker (or Podman)
- Codex authentication on host (`codex login`) OR API key login inside container

Optional:
- NVIDIA runtime for GPU (`--gpus all`)
- Conda paths in `.env`

## Quick Start

```bash
# 1) Enter project
cd codex-docker

# 2) One-time setup
cp .env.example .env
./src/install.sh

# 3) Reload shell so alias is available
source ~/.bashrc   # or your shell rc

# 4) Run from any project directory
cd ~/your-project
codex-docker
```

## Wrapper CLI (same style as Claude Docker)

```bash
codex-docker                       # Start Codex in current directory
codex-docker --podman              # Use podman instead of docker
codex-docker --continue            # Resume previous Codex session
codex-docker --rebuild             # Force rebuild image
codex-docker --rebuild --no-cache  # Rebuild without cache
codex-docker --memory 8g           # Set container memory limit
codex-docker --gpus all            # Enable GPU access
codex-docker --cc-version 0.98.0   # Pin Codex CLI version (compat flag)
codex-docker --codex-version 0.98.0
```

Notes:
- `--cc-version` is preserved as a compatibility alias and maps to Codex CLI version.
- Inside container, Codex runs in YOLO mode via `--dangerously-bypass-approvals-and-sandbox`.

## Runtime Behavior

- Current directory is mounted to `/workspace`.
- Persistent Codex home is mounted at `/home/codex-user/.codex` from:
  - `${CODEX_DOCKER_HOME:-~/.codex-docker}/codex-home`
- SSH keys are mounted from:
  - `${CODEX_DOCKER_HOME:-~/.codex-docker}/ssh`
- `host.docker.internal` is always added.
- On Linux, network mode defaults to `host` unless overridden in `.env`.

## Conda Mounting

Set in `.env`:

```bash
CONDA_PREFIX=/path/to/miniconda3
CONDA_EXTRA_DIRS="/path/to/envs /path/to/pkgs"
```

`codex-docker` mounts these paths read-only and exports `CONDA_ENVS_DIRS`/`CONDA_PKGS_DIRS` automatically when possible.

## Optional .env Settings

- `SYSTEM_PACKAGES="..."` additional apt packages in image build
- `DOCKER_MEMORY_LIMIT=8g`
- `DOCKER_GPU_ACCESS=all`
- `DOCKER_NETWORK_MODE=host`
- `TWILIO_*` and other MCP-related credentials

## MCP Support

`mcp-servers.txt` now uses `codex mcp add ...` commands.

- MCP installation runs once at first container startup and writes into persistent `~/.codex` mount.
- To force reinstall:

```bash
FORCE_MCP_REINSTALL=1 codex-docker
```

See `MCP_SERVERS.md` for details.

## Authentication

Preferred:
- Log in on host once: `codex login`
- Installer copies host `~/.codex/auth.json` into persistent codex-docker home

Alternative inside container:

```bash
codex login
# or
printenv OPENAI_API_KEY | codex login --with-api-key
```
