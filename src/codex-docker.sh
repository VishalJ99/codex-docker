#!/usr/bin/env bash
set -euo pipefail
trap 'echo "$0: line $LINENO: $BASH_COMMAND: exitcode $?"' ERR
# ABOUTME: Wrapper script to run Codex CLI in Docker container
# ABOUTME: Handles project mounting, persistent Codex config, conda mounts, extra user mounts, GPU, and optional rebuild

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib-common.sh"

require_option_value() {
    local option_name="$1"
    local option_value="${2-}"

    if [ -z "$option_value" ] || [[ "$option_value" == --* ]]; then
        echo "Error: $option_name requires a value."
        exit 1
    fi
}

resolve_existing_directory() {
    local directory_path="$1"

    if [ ! -d "$directory_path" ]; then
        return 1
    fi

    (
        cd "$directory_path"
        pwd -P
    )
}

normalize_container_destination() {
    local destination="$1"

    if [ "$destination" != "/" ]; then
        destination="${destination%/}"
    fi

    printf '%s\n' "$destination"
}

DOCKER="${DOCKER:-docker}"
NO_CACHE=()
FORCE_REBUILD=false
CONTINUE_FLAG=""
MEMORY_LIMIT=""
GPU_ACCESS=""
CODEX_VERSION=""
EXTRA_MOUNT_SPECS=()
ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --podman)
            DOCKER=podman
            shift
            ;;
        --no-cache)
            NO_CACHE=(--no-cache)
            shift
            ;;
        --rebuild)
            FORCE_REBUILD=true
            shift
            ;;
        --continue)
            CONTINUE_FLAG="--continue"
            shift
            ;;
        --memory)
            require_option_value "$1" "${2-}"
            MEMORY_LIMIT="$2"
            shift 2
            ;;
        --gpus)
            require_option_value "$1" "${2-}"
            GPU_ACCESS="$2"
            shift 2
            ;;
        --cc-version|--codex-version)
            require_option_value "$1" "${2-}"
            CODEX_VERSION="$2"
            shift 2
            ;;
        --mount)
            require_option_value "$1" "${2-}"
            EXTRA_MOUNT_SPECS+=("$2")
            shift 2
            ;;
        --mount=*)
            EXTRA_MOUNT_SPECS+=("${1#*=}")
            shift
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

check_container_runtime "$DOCKER" "1.44"
resolve_codex_docker_dir

CURRENT_DIR="$(pwd -P)"
HOST_HOME="${HOME:-}"
if [ -z "$HOST_HOME" ]; then
    HOST_HOME="$(get_home_for_uid "$(id -u)" || true)"
fi

CODEX_HOME_DIR="$CODEX_DOCKER_DIR/codex-home"
SSH_DIR="$CODEX_DOCKER_DIR/ssh"

ENV_FILE="$PROJECT_ROOT/.env"
if [ -f "$ENV_FILE" ]; then
    echo "✓ Found .env file with credentials"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE" 2>/dev/null || true
    set +a
else
    echo "⚠️  No .env file found at $ENV_FILE"
    echo "   To configure optional MCP credentials: copy .env.example to .env and fill values"
fi

if [ -z "${MEMORY_LIMIT:-}" ] && [ -n "${DOCKER_MEMORY_LIMIT:-}" ]; then
    MEMORY_LIMIT="$DOCKER_MEMORY_LIMIT"
    echo "✓ Using memory limit from environment: $MEMORY_LIMIT"
fi

if [ -z "${GPU_ACCESS:-}" ] && [ -n "${DOCKER_GPU_ACCESS:-}" ]; then
    GPU_ACCESS="$DOCKER_GPU_ACCESS"
    echo "✓ Using GPU access from environment: $GPU_ACCESS"
fi

NEED_REBUILD=false
if ! "$DOCKER" images | grep -q "codex-docker"; then
    echo "Building Codex Docker image for first time..."
    NEED_REBUILD=true
fi

if [ "$FORCE_REBUILD" = true ]; then
    echo "Forcing rebuild of Codex Docker image..."
    NEED_REBUILD=true
fi

if [ "${#NO_CACHE[@]}" -gt 0 ] && [ "$NEED_REBUILD" = false ]; then
    echo "⚠️  Warning: --no-cache set but image already exists. Use --rebuild --no-cache to force rebuild."
fi

if [ "$NEED_REBUILD" = true ]; then
    GIT_USER_NAME="$(git config --global --get user.name 2>/dev/null || echo "")"
    GIT_USER_EMAIL="$(git config --global --get user.email 2>/dev/null || echo "")"

    BUILD_ARGS=(
        --build-arg "USER_UID=$(id -u)"
        --build-arg "USER_GID=$(id -g)"
    )
    if [ -n "${GIT_USER_NAME:-}" ] && [ -n "${GIT_USER_EMAIL:-}" ]; then
        BUILD_ARGS+=(--build-arg "GIT_USER_NAME=$GIT_USER_NAME" --build-arg "GIT_USER_EMAIL=$GIT_USER_EMAIL")
    fi
    if [ -n "${SYSTEM_PACKAGES:-}" ]; then
        echo "✓ Building with additional system packages: $SYSTEM_PACKAGES"
        BUILD_ARGS+=(--build-arg "SYSTEM_PACKAGES=$SYSTEM_PACKAGES")
    fi
    if [ -n "${CODEX_VERSION:-}" ]; then
        echo "✓ Building with Codex CLI version: $CODEX_VERSION"
        BUILD_ARGS+=(--build-arg "CODEX_VERSION=$CODEX_VERSION")
    fi

    "$DOCKER" build "${NO_CACHE[@]}" "${BUILD_ARGS[@]}" -t codex-docker:latest "$PROJECT_ROOT"
fi

mkdir -p "$CODEX_HOME_DIR"
mkdir -p "$SSH_DIR"

if [ -n "$HOST_HOME" ] && [ -f "$HOST_HOME/.codex/auth.json" ] && [ ! -f "$CODEX_HOME_DIR/auth.json" ]; then
    echo "✓ Copying Codex authentication to persistent directory"
    cp "$HOST_HOME/.codex/auth.json" "$CODEX_HOME_DIR/auth.json"
fi

if [ -n "$HOST_HOME" ] && [ -f "$HOST_HOME/.codex/config.toml" ] && [ ! -f "$CODEX_HOME_DIR/config.toml" ]; then
    echo "✓ Seeding persistent config.toml from host ~/.codex"
    cp "$HOST_HOME/.codex/config.toml" "$CODEX_HOME_DIR/config.toml"
fi

if [ -n "$HOST_HOME" ] && [ -f "$HOST_HOME/.codex/AGENTS.md" ] && [ ! -f "$CODEX_HOME_DIR/AGENTS.md" ]; then
    echo "✓ Seeding persistent AGENTS.md from host ~/.codex"
    cp "$HOST_HOME/.codex/AGENTS.md" "$CODEX_HOME_DIR/AGENTS.md"
fi

if [ -f "$PROJECT_ROOT/.codex/AGENTS.md" ] && [ ! -f "$CODEX_HOME_DIR/AGENTS.md" ]; then
    echo "✓ Seeding persistent AGENTS.md from project template"
    cp "$PROJECT_ROOT/.codex/AGENTS.md" "$CODEX_HOME_DIR/AGENTS.md"
fi

echo ""
echo "📁 Codex persistent home directory: $CODEX_HOME_DIR/"
echo "   This directory is mounted as /home/codex-user/.codex in the container"
echo ""

SSH_KEY_PATH="$SSH_DIR/id_rsa"
SSH_PUB_KEY_PATH="$SSH_DIR/id_rsa.pub"

if [ ! -f "$SSH_KEY_PATH" ] || [ ! -f "$SSH_PUB_KEY_PATH" ]; then
    echo ""
    echo "⚠️  SSH keys not found for git operations"
    echo "   To enable git push/pull in Codex Docker:"
    echo ""
    echo "   1. Generate SSH key:"
    echo "      ssh-keygen -t rsa -b 4096 -f $SSH_DIR/id_rsa -N ''"
    echo ""
    echo "   2. Add public key to GitHub:"
    echo "      cat $SSH_DIR/id_rsa.pub"
    echo "      # Copy output and add to: GitHub -> Settings -> SSH keys"
    echo ""
    echo "   3. Test connection:"
    echo "      ssh -T git@github.com -i $SSH_DIR/id_rsa"
    echo ""
    echo "   Codex will continue without SSH keys (read-only git operations only)"
    echo ""
else
    echo "✓ SSH keys found for git operations"

    SSH_CONFIG_PATH="$SSH_DIR/config"
    if [ ! -f "$SSH_CONFIG_PATH" ]; then
        cat > "$SSH_CONFIG_PATH" << 'EOC'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_rsa
    IdentitiesOnly yes
EOC
        echo "✓ SSH config created for GitHub"
    fi
fi

MOUNT_ARGS=()
ENV_ARGS=()
DOCKER_OPTS=()

declare -A USED_CONTAINER_DESTINATIONS=(
    ["/workspace"]="workspace directory ($CURRENT_DIR)"
    ["/home/codex-user/.codex"]="persistent Codex home ($CODEX_HOME_DIR)"
    ["/home/codex-user/.ssh"]="persistent SSH directory ($SSH_DIR)"
)

is_container_destination_registered() {
    local destination="$1"
    [ -n "${USED_CONTAINER_DESTINATIONS[$destination]:-}" ]
}

register_container_destination() {
    local destination="$1"
    local description="$2"
    USED_CONTAINER_DESTINATIONS["$destination"]="$description"
}

add_extra_mount() {
    local raw_spec="$1"
    local source_path=""
    local destination=""
    local host_source=""

    if [[ "$raw_spec" != *:* ]]; then
        echo "Error: Extra mount '$raw_spec' must use source:destination format."
        exit 1
    fi

    source_path="${raw_spec%%:*}"
    destination="${raw_spec#*:}"

    if [ -z "$source_path" ] || [ -z "$destination" ] || [[ "$destination" == *:* ]]; then
        echo "Error: Extra mount '$raw_spec' must use exactly one source:destination pair."
        exit 1
    fi

    if ! host_source="$(resolve_existing_directory "$source_path")"; then
        echo "Error: Extra mount source '$source_path' was not found or is not a directory."
        exit 1
    fi

    destination="$(normalize_container_destination "$destination")"
    if [[ "$destination" != /* ]]; then
        echo "Error: Extra mount destination '$destination' must be an absolute container path."
        exit 1
    fi

    if is_container_destination_registered "$destination"; then
        echo "Error: Extra mount destination '$destination' is already used by ${USED_CONTAINER_DESTINATIONS[$destination]}."
        exit 1
    fi

    register_container_destination "$destination" "extra mount from $host_source"
    echo "✓ Mounting additional directory: $host_source -> $destination"
    MOUNT_ARGS+=("-v" "$host_source:$destination:rw")
}

if [ -n "${MEMORY_LIMIT:-}" ]; then
    echo "✓ Setting memory limit: $MEMORY_LIMIT"
    DOCKER_OPTS+=(--memory "$MEMORY_LIMIT")
fi

if [ -n "${GPU_ACCESS:-}" ]; then
    if "$DOCKER" info 2>/dev/null | grep -q nvidia || command -v nvidia-docker >/dev/null 2>&1; then
        echo "✓ Enabling GPU access: $GPU_ACCESS"
        DOCKER_OPTS+=(--gpus "$GPU_ACCESS")
    else
        echo "⚠️  GPU access requested but NVIDIA Docker runtime not found"
        echo "   Install nvidia-docker2 or nvidia-container-runtime to enable GPU support"
        echo "   Continuing without GPU access..."
    fi
fi

if [ -z "${DOCKER_NETWORK_MODE:-}" ] && [ "$(uname -s)" = "Linux" ]; then
    DOCKER_NETWORK_MODE="host"
fi

if [ -n "${DOCKER_NETWORK_MODE:-}" ]; then
    echo "✓ Using network mode: $DOCKER_NETWORK_MODE"
    DOCKER_OPTS+=(--network "$DOCKER_NETWORK_MODE")
fi

DOCKER_OPTS+=(--add-host=host.docker.internal:host-gateway)

if [ -n "${CONDA_PREFIX:-}" ] && [ -d "$CONDA_PREFIX" ]; then
    echo "✓ Mounting conda installation from $CONDA_PREFIX"
    if is_container_destination_registered "$CONDA_PREFIX"; then
        echo "⚠️  Skipping conda installation mount to $CONDA_PREFIX (already used by ${USED_CONTAINER_DESTINATIONS[$CONDA_PREFIX]})"
    else
        register_container_destination "$CONDA_PREFIX" "conda installation ($CONDA_PREFIX)"
        MOUNT_ARGS+=("-v" "$CONDA_PREFIX:$CONDA_PREFIX:ro")
        ENV_ARGS+=("-e" "CONDA_PREFIX=$CONDA_PREFIX" "-e" "CONDA_EXE=$CONDA_PREFIX/bin/conda")
    fi
else
    echo "No conda installation configured"
fi

if [ -n "${CONDA_EXTRA_DIRS:-}" ]; then
    echo "✓ Mounting additional conda directories..."
    CONDA_ENVS_PATHS=""
    CONDA_PKGS_PATHS=""
    for dir in $CONDA_EXTRA_DIRS; do
        if [ -d "$dir" ]; then
            if is_container_destination_registered "$dir"; then
                echo "  - Skipping $dir (container destination already used by ${USED_CONTAINER_DESTINATIONS[$dir]})"
                continue
            fi
            echo "  - Mounting $dir"
            register_container_destination "$dir" "conda extra directory ($dir)"
            MOUNT_ARGS+=("-v" "$dir:$dir:ro")
            if [[ "$dir" == *"env"* ]]; then
                if [ -z "${CONDA_ENVS_PATHS:-}" ]; then
                    CONDA_ENVS_PATHS="$dir"
                else
                    CONDA_ENVS_PATHS="$CONDA_ENVS_PATHS:$dir"
                fi
            fi
            if [[ "$dir" == *"pkg"* ]]; then
                if [ -z "${CONDA_PKGS_PATHS:-}" ]; then
                    CONDA_PKGS_PATHS="$dir"
                else
                    CONDA_PKGS_PATHS="$CONDA_PKGS_PATHS:$dir"
                fi
            fi
        else
            echo "  - Skipping $dir (not found)"
        fi
    done
    if [ -n "${CONDA_ENVS_PATHS:-}" ]; then
        ENV_ARGS+=("-e" "CONDA_ENVS_DIRS=$CONDA_ENVS_PATHS")
        echo "  - Setting CONDA_ENVS_DIRS=$CONDA_ENVS_PATHS"
    fi
    if [ -n "${CONDA_PKGS_PATHS:-}" ]; then
        ENV_ARGS+=("-e" "CONDA_PKGS_DIRS=$CONDA_PKGS_PATHS")
        echo "  - Setting CONDA_PKGS_DIRS=$CONDA_PKGS_PATHS"
    fi
else
    echo "No additional conda directories configured"
fi

if [ "${#EXTRA_MOUNT_SPECS[@]}" -gt 0 ]; then
    for mount_spec in "${EXTRA_MOUNT_SPECS[@]}"; do
        add_extra_mount "$mount_spec"
    done
fi

if [ -n "${OPENAI_API_KEY:-}" ]; then
    ENV_ARGS+=("-e" "OPENAI_API_KEY=$OPENAI_API_KEY")
fi

if [ -n "${FORCE_MCP_REINSTALL:-}" ]; then
    ENV_ARGS+=("-e" "FORCE_MCP_REINSTALL=$FORCE_MCP_REINSTALL")
fi

echo "Starting Codex CLI in Docker..."
"$DOCKER" run -it --rm \
    "${DOCKER_OPTS[@]}" \
    -v "$CURRENT_DIR:/workspace" \
    -v "$CODEX_HOME_DIR:/home/codex-user/.codex:rw" \
    -v "$SSH_DIR:/home/codex-user/.ssh:rw" \
    "${MOUNT_ARGS[@]}" \
    "${ENV_ARGS[@]}" \
    -e "CODEX_CONTINUE_FLAG=$CONTINUE_FLAG" \
    --workdir /workspace \
    --name "codex-docker-$(basename "$CURRENT_DIR")-$$" \
    codex-docker:latest "${ARGS[@]}"
