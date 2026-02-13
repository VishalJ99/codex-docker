#!/usr/bin/env bash
set -euo pipefail
trap 'echo "$0: line $LINENO: $BASH_COMMAND: exitcode $?"' ERR
# ABOUTME: Installation script for codex-docker
# ABOUTME: Creates persistent codex-docker config and adds shell alias for the calling user.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib-common.sh"

get_user_shell_from_passwd() {
    local user_name="${1:-}"
    local user_shell=""

    if [ -n "$user_name" ] && command -v getent >/dev/null 2>&1; then
        user_shell="$(getent passwd "$user_name" | cut -d: -f7 || true)"
    fi

    if [ -z "$user_shell" ] && [ -n "$user_name" ] && [ -r /etc/passwd ]; then
        user_shell="$(awk -F: -v uname="$user_name" '$1 == uname { print $7; exit }' /etc/passwd || true)"
    fi

    if [ -z "$user_shell" ]; then
        user_shell="${SHELL:-/bin/bash}"
    fi

    printf '%s\n' "$user_shell"
}

get_shell_rc_filename() {
    local shell_path="${1:-}"
    local shell_name
    shell_name="$(basename "$shell_path")"

    # Prefer existing zsh config when present, regardless of current shell.
    if [ -f "$TARGET_HOME/.zshrc" ]; then
        printf '%s\n' ".zshrc"
        return
    fi

    case "$shell_name" in
        zsh)
            printf '%s\n' ".zshrc"
            ;;
        bash)
            if [ -f "$TARGET_HOME/.bash_profile" ] && [ ! -f "$TARGET_HOME/.bashrc" ]; then
                printf '%s\n' ".bash_profile"
            else
                printf '%s\n' ".bashrc"
            fi
            ;;
        sh|dash|ksh|ash)
            printf '%s\n' ".profile"
            ;;
        *)
            printf '%s\n' ".profile"
            ;;
    esac
}

TARGET_USER="$(id -un)"
TARGET_UID="$(id -u)"
TARGET_GID="$(id -g)"

if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    TARGET_USER="$SUDO_USER"
    TARGET_UID="$(id -u "$TARGET_USER")"
    TARGET_GID="$(id -g "$TARGET_USER")"
fi

TARGET_HOME="$(get_home_for_uid "$TARGET_UID" || true)"
if [ -z "$TARGET_HOME" ] && [ "$EUID" -ne 0 ]; then
    TARGET_HOME="${HOME:-}"
fi

if [ -z "$TARGET_HOME" ]; then
    echo "Error: Could not determine a home directory for user '$TARGET_USER'."
    echo "Set CODEX_DOCKER_HOME to a writable location and re-run install.sh."
    exit 1
fi

TARGET_SHELL="$(get_user_shell_from_passwd "$TARGET_USER")"
TARGET_RC_NAME="$(get_shell_rc_filename "$TARGET_SHELL")"
TARGET_RC_FILE="$TARGET_HOME/$TARGET_RC_NAME"

resolve_codex_docker_dir "$TARGET_HOME"
CODEX_HOME_DIR="$CODEX_DOCKER_DIR/codex-home"

mkdir -p "$CODEX_HOME_DIR"

echo "✓ Copying template Codex configuration to persistent directory"
cp -rn "$PROJECT_ROOT/.codex/." "$CODEX_HOME_DIR/"

if [ -f "$TARGET_HOME/.codex/auth.json" ] && [ ! -f "$CODEX_HOME_DIR/auth.json" ]; then
    echo "✓ Seeding auth.json from host ~/.codex"
    cp "$TARGET_HOME/.codex/auth.json" "$CODEX_HOME_DIR/auth.json"
fi

if [ -f "$TARGET_HOME/.codex/config.toml" ] && [ ! -f "$CODEX_HOME_DIR/config.toml" ]; then
    echo "✓ Seeding config.toml from host ~/.codex"
    cp "$TARGET_HOME/.codex/config.toml" "$CODEX_HOME_DIR/config.toml"
fi

if [ ! -f "$PROJECT_ROOT/.env" ]; then
    cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
    echo "⚠️  Created .env file at $PROJECT_ROOT/.env"
    echo "   Edit it only if you need optional MCP credentials or defaults"
fi

ALIAS_LINE="alias codex-docker='$PROJECT_ROOT/src/codex-docker.sh'"
if [ ! -f "$TARGET_RC_FILE" ]; then
    touch "$TARGET_RC_FILE"
    echo "✓ Created shell config file at $TARGET_RC_FILE"
fi

if ! grep -Fq "alias codex-docker=" "$TARGET_RC_FILE"; then
    echo "" >> "$TARGET_RC_FILE"
    echo "# Codex Docker alias" >> "$TARGET_RC_FILE"
    echo "$ALIAS_LINE" >> "$TARGET_RC_FILE"
    echo "✓ Added 'codex-docker' alias to $TARGET_RC_NAME"
else
    echo "✓ codex-docker alias already exists in $TARGET_RC_NAME"
fi

if [ "$EUID" -eq 0 ] && [ "$TARGET_USER" != "root" ]; then
    chown -R "$TARGET_UID:$TARGET_GID" "$CODEX_DOCKER_DIR"
    chown "$TARGET_UID:$TARGET_GID" "$TARGET_RC_FILE"
    if [ -f "$PROJECT_ROOT/.env" ]; then
        chown "$TARGET_UID:$TARGET_GID" "$PROJECT_ROOT/.env"
    fi
fi

chmod +x "$PROJECT_ROOT/src/codex-docker.sh"
chmod +x "$PROJECT_ROOT/src/startup.sh"

# Keep the same optional GPU installation behavior as the original template.
echo ""
echo "Checking GPU support..."

if [ "$EUID" -eq 0 ]; then
    echo "✓ Running with admin privileges"

    if command -v nvidia-smi &> /dev/null; then
        echo "✓ NVIDIA drivers detected"

        if docker info 2>/dev/null | grep -q nvidia; then
            echo "✓ Docker GPU support already installed"
        else
            echo "⚠️  Docker GPU support not found"
            echo "Installing NVIDIA Container Toolkit..."

            distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
                gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
            apt-get update -qq
            apt-get install -y -qq nvidia-container-toolkit
            nvidia-ctk runtime configure --runtime=docker > /dev/null
            systemctl restart docker
            echo "✓ NVIDIA Container Toolkit installed"
        fi
    else
        echo "ℹ️  No NVIDIA GPU detected - skipping GPU support"
    fi
else
    echo "ℹ️  Not running as root - skipping GPU installation"
    echo "   To install GPU support, run: sudo $SCRIPT_DIR/install.sh"

    if command -v nvidia-smi &> /dev/null; then
        if docker info 2>/dev/null | grep -q nvidia; then
            echo "   ✓ GPU support appears to be already installed"
        else
            echo "   ⚠️  GPU detected but Docker GPU support not installed"
        fi
    fi
fi

echo ""
echo "Installation complete"
echo ""
echo "Next steps:"
echo "1. (Optional) Edit $PROJECT_ROOT/.env for MCP creds or defaults"
echo "2. Run 'source $TARGET_RC_FILE' or start a new terminal"
echo "3. Navigate to any project and run 'codex-docker'"
echo "4. If needed, authenticate once inside container using 'codex login'"
