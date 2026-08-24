#!/bin/bash

# Re-exec under bash if invoked with sh/dash (bashisms ahead)
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

echo "=== Ubuntu 26 Development Environment Setup ==="
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

# Update package list
echo "Updating package list..."
sudo apt-get update -y

# Install curl
echo "Installing curl..."
sudo apt-get install -y curl wget

# Install htop
echo "Installing htop..."
sudo apt-get install -y htop

# Install curl
echo "Installing unzip..."
sudo apt-get install -y unzip

# Install git early (needed by the oh-my-zsh/p10k installer)
echo "Installing git..."
sudo apt-get install -y git

# Install zsh + Oh My Zsh + Powerlevel10k first so ~/.zshrc exists
# before the NVM/brew/herdr blocks below append to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Running install_ohmyzsh_p10k.sh..."
bash "$SCRIPT_DIR/install_ohmyzsh_p10k.sh"

# Install Python 3.14
# Works on both Ubuntu 24.04 (needs the deadsnakes PPA) and 26.04 (ships 3.14
# in the default repos, so the PPA is skipped).
#
# IMPORTANT: we deliberately do NOT point /usr/bin/python3 at 3.14. Ubuntu's
# apt tooling (command-not-found / cnf-update-db) imports the python3-apt C
# bindings (apt_pkg), which only exist for the distro's stock python3. Re-aiming
# /usr/bin/python3 at 3.14 breaks every later apt run with:
#   ModuleNotFoundError: No module named 'apt_pkg'
# Instead we register `python` (which doesn't exist by default) -> 3.14, leaving
# the system python3 untouched.
echo "Installing Python 3.14..."
if apt-cache show python3.14 >/dev/null 2>&1; then
    # Already available in the distro repos (Ubuntu 26.04+)
    echo "python3.14 available in default repos; skipping deadsnakes PPA."
else
    # Ubuntu 24.04 etc. — pull from the deadsnakes PPA
    echo "Adding deadsnakes PPA for python3.14..."
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt-get update -y
fi
sudo apt-get install -y python3.14 python3.14-venv python3.14-dev python3-pip
# Provide a `python` command pointing at 3.14 without touching system python3.
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.14 1

# Install uv
echo "Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh
# Add uv to PATH for this session
export PATH="$HOME/.local/bin:$PATH"

# Install Python dev tools
# Cross-platform Python packages (wheels on macOS + manylinux), installed the
# same way as on macOS so the shared post-code/post-task hooks find them. These
# back the lint/type-check/security battery in shared/post_*_checks.sh.
echo "Installing Python dev tools..."
uv tool install pytest
uv tool install ruff
uv tool install mypy
uv tool install pip-audit
uv tool install semgrep
uv tool install commitizen

# Install AWS CLI
echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
cd /tmp
unzip -q awscliv2.zip
sudo ./aws/install --update
rm -rf awscliv2.zip aws

# Install GitHub CLI
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian
echo "Installing GitHub CLI..."
(type -p wget >/dev/null || (sudo apt-get update && sudo apt-get install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt-get update \
	&& sudo apt-get install gh -y

# Install the stacked-PR extension (gh stack ...) — optional, non-fatal
echo "Installing gh-stack extension..."
if gh extension list 2>/dev/null | grep -q 'github/gh-stack'; then
    echo "gh-stack already installed"
else
    gh extension install github/gh-stack || echo "⚠ gh-stack install skipped"
fi

# Install Podman
echo "Installing Podman..."
sudo apt-get install -y podman

# Install Docker (official repo)
echo "Installing Docker..."
sudo apt-get install -y ca-certificates
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group (takes effect after re-login)
echo "Adding $USER to docker group..."
sudo usermod -aG docker "$USER"

# Install QEMU + binfmt for multi-arch Docker builds (linux/arm64, etc.)
# On Ubuntu 26, "qemu-user-static" is a virtual package with no install
# candidate, so explicitly select a concrete provider (falling back to the
# legacy name on older releases).
echo "Installing QEMU and binfmt support..."
if ! sudo apt-get install -y qemu-user-binfmt binfmt-support; then
    sudo apt-get install -y qemu-user-static binfmt-support
fi

# Install NVM (fetch latest release tag)
echo "Installing NVM..."
NVM_LATEST=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -oP '"tag_name": "\K[^"]+')
NVM_LATEST="${NVM_LATEST:-v0.40.1}"
echo "Using NVM ${NVM_LATEST}"
curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST}/install.sh" | bash
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Ensure NVM is loaded in .zshrc if zsh is installed
if [ -f "$HOME/.zshrc" ] && ! grep -q 'NVM_DIR' "$HOME/.zshrc" 2>/dev/null; then
    cat >> "$HOME/.zshrc" << 'NVMEOF'

# NVM (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
NVMEOF
    echo "Added NVM configuration to ~/.zshrc"
fi

# Install latest Node.js via NVM
echo "Installing latest Node.js via NVM..."
nvm install node
nvm use node
nvm alias default node

# Install TypeScript globally (latest)
echo "Installing TypeScript..."
npm install -g typescript@latest

# Install AWS CDK (latest)
echo "Installing AWS CDK..."
npm install -g aws-cdk@latest

# Install LazyVim dependencies (lazygit comes from brew in the sub-script — not in Ubuntu apt)
echo "Installing LazyVim dependencies..."
sudo apt-get install -y git ripgrep fd-find

# Install Neovim (latest stable)
echo "Installing Neovim..."
NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
curl -Lo /tmp/nvim-linux-x86_64.tar.gz "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz"
sudo rm -rf /opt/nvim-linux-x86_64
sudo tar -C /opt -xzf /tmp/nvim-linux-x86_64.tar.gz
rm /tmp/nvim-linux-x86_64.tar.gz

# Add nvim to PATH if not already there
if ! grep -q '/opt/nvim-linux-x86_64/bin' ~/.bashrc; then
    # shellcheck disable=SC2016
    echo 'export PATH="$PATH:/opt/nvim-linux-x86_64/bin"' >> ~/.bashrc
fi

# Install the agentic coding CLIs and their configuration. Each CLI binary and
# its agents/skills/prompts, steering, MCPs and hooks come from the per-tool
# installers, driven by the single sources of truth under ../shared.
echo "Installing agentic coding CLIs and configs..."
# Derive from SCRIPT_DIR (absolute, set at the top) — NOT $0, which resolves
# against the current cwd, and an earlier `cd /tmp` makes $0-based paths point
# at / (regression: install.sh became //install.sh).
CONFIGS_ROOT="$(dirname "$SCRIPT_DIR")"
"$CONFIGS_ROOT/install.sh"

# Install Ollama
echo "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# Configure tmux (enable mouse scroll wheel + PgUp in SSH sessions)
echo "Configuring tmux..."
if [ ! -f "$HOME/.tmux.conf" ] || ! grep -q '^set -g mouse on' "$HOME/.tmux.conf" 2>/dev/null; then
    cat >> "$HOME/.tmux.conf" << 'TMUXEOF'

# Enable mouse: scroll wheel scrolls the pane's scrollback
set -g mouse on

# Page Up jumps straight into copy mode and scrolls up
bind -n Pageup copy-mode -u
TMUXEOF
    echo "Added tmux mouse configuration to ~/.tmux.conf"
fi

# Backup existing nvim config if it exists
if [ -d "$HOME/.config/nvim" ]; then
    echo "Backing up existing nvim config..."
    mv "$HOME/.config/nvim" "$HOME/.config/nvim.backup.$(date +%Y%m%d_%H%M%S)"
fi

if [ -d "$HOME/.local/share/nvim" ]; then
    mv "$HOME/.local/share/nvim" "$HOME/.local/share/nvim.backup.$(date +%Y%m%d_%H%M%S)"
fi

if [ -d "$HOME/.local/state/nvim" ]; then
    mv "$HOME/.local/state/nvim" "$HOME/.local/state/nvim.backup.$(date +%Y%m%d_%H%M%S)"
fi

if [ -d "$HOME/.cache/nvim" ]; then
    mv "$HOME/.cache/nvim" "$HOME/.cache/nvim.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Install LazyVim
echo "Installing LazyVim..."
git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
rm -rf "$HOME/.config/nvim/.git"

# Self-heal: remove the stale herdr launch block that earlier versions of this
# script appended to the rc files. It was guarded on HERDR_ENV (not the
# HERDR_SESSION used by the current HERDR_AUTOLAUNCH block) and had no
# 'command -v herdr' check, so it relaunched herdr on exit and errored when
# herdr was absent. Strip it from the marker comment through its closing 'fi'.
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ] && grep -qF 'Launch herdr on SSH login' "$rc"; then
        echo "Removing stale herdr launch block from $rc..."
        sed -i '/# --- Launch herdr on SSH login ---/,/^fi$/d' "$rc"
    fi
done

# Advertise 24-bit colour support to terminal apps. Set in both shells' rc
# files so it applies whether the login shell is zsh or bash.
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ] && ! grep -q 'COLORTERM' "$rc" 2>/dev/null; then
        echo 'export COLORTERM=truecolor' >> "$rc"
        echo "Added COLORTERM=truecolor to $rc"
    fi
done

# Install Homebrew + herdr + yazi + lazygit + neovim tooling (sub-script).
# The sub-script also installs the herdr SSH auto-launch hook into ~/.bashrc
# and ~/.zshrc (single HERDR_AUTOLAUNCH block), so no extra wiring is needed here.
echo "Running install_brew_herdr_yazi_lazygit_nvim.sh..."
bash "$SCRIPT_DIR/install_brew_herdr_yazi_lazygit_nvim.sh"

echo ""
echo "=== Configuration ==="
echo ""

# Git configuration
read -rp "Enter your Git username: " git_username
read -rp "Enter your Git email: " git_email

if [ -n "$git_username" ]; then
    git config --global user.name "$git_username"
    echo "Git username set to: $git_username"
fi

if [ -n "$git_email" ]; then
    git config --global user.email "$git_email"
    echo "Git email set to: $git_email"
fi

# AWS configuration
echo ""
echo "Configuring AWS CLI..."
aws configure

# Ollama model configuration
echo ""
echo "=== Ollama Model Setup ==="
read -p "Pull an Ollama model now? [y/N]: " -r REPLY
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Popular models:"
    echo "  - qwen3.6:27b     (27B - powerful, recommended)"
    echo "  - qwen3-coder:30b (30B MoE - coding focused)"
    echo "  - devstral:24b    (24B - agentic coding)"
    echo "  - gpt-oss:20b     (20B MoE - fast reasoning)"
    echo "  - deepseek-r1     (7B - reasoning focused)"
    echo ""
    read -rp "Enter model name [qwen3.6:27b]: " ollama_model
    ollama_model=${ollama_model:-qwen3.6:27b}

    echo "Pulling $ollama_model..."
    ollama pull "$ollama_model"
    echo "Model $ollama_model installed successfully!"
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "1. Log out and back in (or run 'newgrp docker') for docker group membership to take effect"
echo "2. Restart your terminal or run: source ~/.bashrc"
echo "3. Run 'nvim' to complete LazyVim setup"
echo "4. Start Ollama service if not already running: ollama serve"
echo "5. Pull additional models: ollama pull <model-name>"
echo "6. Verify installations:"
echo "   - python3 --version"
echo "   - node --version"
echo "   - aws --version"
echo "   - claude --version"
echo "   - codex --version"
echo "   - omp --version"
echo "   - ollama --version"
