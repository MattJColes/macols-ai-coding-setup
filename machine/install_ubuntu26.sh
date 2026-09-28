#!/bin/bash

# Re-exec under bash if invoked with sh/dash (bashisms ahead)
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

echo "=== Ubuntu 24/26 Development Environment Setup ==="
echo ""

# Set non-interactive mode for apt
export DEBIAN_FRONTEND=noninteractive

# --- Self-heal: undo any prior hijack of the system python3 ---
# An earlier version of this script pointed /usr/bin/python3 at 3.14 via
# update-alternatives. That breaks apt: its cnf-update-db hook runs under
# /usr/bin/python3 and needs the python3-apt bindings (apt_pkg), which only
# exist for the distro's stock interpreter. The result is either
# "ModuleNotFoundError: No module named 'apt_pkg'" or "/usr/lib/cnf-update-db:
# not found", and every apt command fails. Detect and repair that here so this
# script can run (and re-run) on a previously-broken machine.
if update-alternatives --list python3 >/dev/null 2>&1; then
    echo "Removing python3 update-alternatives override (it breaks apt)..."
    sudo update-alternatives --remove-all python3 || true
fi
# Ensure /usr/bin/python3 exists and can import apt_pkg; if not, restore it to
# the stock interpreter (the one that ships python3-apt).
if [ ! -e /usr/bin/python3 ] || ! /usr/bin/python3 -c 'import apt_pkg' >/dev/null 2>&1; then
    stock_py=""
    for py in /usr/bin/python3.[0-9] /usr/bin/python3.[0-9][0-9]; do
        [ -x "$py" ] || continue
        if "$py" -c 'import apt_pkg' >/dev/null 2>&1; then
            stock_py="$py"
            break
        fi
    done
    if [ -n "$stock_py" ]; then
        echo "Restoring /usr/bin/python3 -> $stock_py (repairs apt)..."
        sudo ln -sf "$stock_py" /usr/bin/python3
    else
        echo "WARNING: could not find a system python3 with apt_pkg bindings;" \
             "apt may still be broken. Try: sudo apt-get install --reinstall python3-minimal python3-apt" >&2
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# System packages that need apt (the rest come from machine/Brewfile).
echo "Installing base packages (apt)..."
apt_update
sudo apt-get install -y curl wget unzip git zsh build-essential procps file \
    ca-certificates software-properties-common

# zsh + Oh My Zsh first so ~/.zshrc exists before the blocks below write to it.
bash "$SCRIPT_DIR/install_zsh.sh"

# Homebrew + everything in the Brewfile (neovim, gh, awscli, uv, go, starship,
# the hook linters…). Replaces the x86-only Neovim tarball and AWS CLI zip,
# the GitHub CLI apt repo and the curl|sh uv installer.
ensure_homebrew
brew_bundle

# Retire the old /opt Neovim tarball install (brew's neovim replaces it).
if [ -d /opt/nvim-linux-x86_64 ]; then
    echo "Removing the old /opt Neovim tarball install..."
    sudo rm -rf /opt/nvim-linux-x86_64
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] && grep -qF '/opt/nvim-linux-x86_64/bin' "$rc" \
            && grep -vF '/opt/nvim-linux-x86_64/bin' "$rc" > "$rc.macols.tmp" && mv "$rc.macols.tmp" "$rc"
    done
fi

install_python
install_node
install_gh_stack

# Podman, Docker (official repo) and QEMU/binfmt for multi-arch builds.
echo "Installing Podman..."
sudo apt-get install -y podman

echo "Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt_update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
id -nG "$USER" | grep -qw docker || sudo usermod -aG docker "$USER"

# On Ubuntu 26, "qemu-user-static" is a virtual package with no install
# candidate, so select a concrete provider (legacy name on older releases).
echo "Installing QEMU and binfmt support..."
if ! sudo apt-get install -y qemu-user-binfmt binfmt-support; then
    sudo apt-get install -y qemu-user-static binfmt-support
fi

# Ollama's official installer (not brew) because it sets up the systemd
# service that host_ollama_model.sh configures.
if command -v ollama &>/dev/null; then
    echo "Ollama already installed."
else
    echo "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh || warn "Ollama install failed"
fi

install_lazyvim
setup_prompt

# Self-heal: remove the stale herdr launch block earlier versions of this
# script appended (guarded on HERDR_ENV, no 'command -v herdr' check).
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ] && grep -qF 'Launch herdr on SSH login' "$rc"; then
        echo "Removing stale herdr launch block from $rc..."
        awk '/# --- Launch herdr on SSH login ---/ { skip = 1 }
             skip && /^fi$/ { skip = 0; next }
             !skip { print }' "$rc" > "$rc.macols.tmp" && mv "$rc.macols.tmp" "$rc"
    fi
done

# Advertise 24-bit colour support to terminal apps.
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    set_rc_block "$rc" colorterm 'export COLORTERM=truecolor'
done

# herdr + its plugins and layouts, yazi config, tmux and the herdr SSH
# auto-launch hook.
bash "$SCRIPT_DIR/install_brew_herdr_yazi_lazygit_nvim.sh"

install_agent_tools

echo ""
echo "=== Configuration ==="
configure_git_identity
configure_aws

if is_interactive && command -v ollama &>/dev/null; then
    echo ""
    echo "=== Ollama Model Setup ==="
    read -rp "Pull an Ollama model now? [y/N]: " reply
    if [[ $reply =~ ^[Yy]$ ]]; then
        read -rp "Model name [qwen3.6:27b]: " ollama_model
        ollama_model=${ollama_model:-qwen3.6:27b}
        ollama pull "$ollama_model" || warn "ollama pull $ollama_model failed"
    fi
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "1. Log out and back in (or run 'newgrp docker') for docker group membership to take effect"
echo "2. Restart your terminal (zsh + starship) or run: exec zsh"
echo "3. Run 'nvim' to complete LazyVim setup"
echo "4. To host a model over Tailscale: sudo ./host_ollama_model.sh"
echo "5. Verify installations:"
echo "   - python3 --version"
echo "   - node --version"
echo "   - aws --version"
echo "   - claude --version"
echo "   - codex --version"
echo "   - pi --version"
echo "   - omp --version"
echo "   - ollama --version"
