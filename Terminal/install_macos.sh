#!/bin/bash

set -e

echo "=== macOS Development Environment Setup ==="
echo ""

# Install Xcode Command Line Tools (required by Homebrew, Flutter, etc.)
if ! xcode-select -p &> /dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "Please complete the Xcode CLT installation prompt, then re-run this script."
    exit 1
fi
echo "Xcode Command Line Tools found"

# Install Homebrew
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add Homebrew to PATH for this session and persist in .zprofile
    echo >> "$HOME/.zprofile"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv zsh)"' >> "$HOME/.zprofile"
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
else
    echo "Homebrew already installed"
fi

# Update Homebrew
echo "Updating Homebrew..."
brew update

# Install Python 3.14
echo "Installing Python 3.14..."
brew install python@3.14

# Install htop
echo "Installing htop..."
brew install htop

# Install AWS CLI
echo "Installing AWS CLI..."
brew install awscli

# Install GitHub CLI
echo "Installing GitHub CLI..."
brew install gh

# Install Podman
echo "Installing Podman..."
brew install podman

# Install modern CLI tools (structural search, JSON/config parsing)
echo "Installing modern CLI tools (ast-grep, jq, dasel)..."
brew install ast-grep jq dasel

# Install NVM (fetch latest release tag)
echo "Installing NVM..."
# Ensure .zshrc exists so the NVM installer can append to it
touch "$HOME/.zshrc"
NVM_LATEST=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -oE '"tag_name": *"[^"]+"' | cut -d'"' -f4)
NVM_LATEST="${NVM_LATEST:-v0.40.1}"
echo "Using NVM ${NVM_LATEST}"
curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST}/install.sh" | bash
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Ensure NVM is loaded in .zshrc (the installer may only update .bashrc)
if ! grep -q 'NVM_DIR' "$HOME/.zshrc" 2>/dev/null; then
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

# Install uv
echo "Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh
# Add uv to PATH for this session
export PATH="$HOME/.local/bin:$PATH"

# Install Flutter SDK
echo "Installing Flutter SDK..."
brew install --cask flutter

# Install Python dev tools
echo "Installing Python dev tools..."
uv tool install pytest
uv tool install ruff
uv tool install mypy
uv tool install pip-audit
uv tool install semgrep
uv tool install commitizen

# Install the agentic coding CLIs and their configuration. Each CLI binary and
# its agents/skills/prompts, steering, MCPs and hooks come from the per-tool
# installers, driven by the single sources of truth under ../shared.
echo "Installing agentic coding CLIs and configs..."
CONFIGS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$CONFIGS_ROOT/install.sh"

# Install LazyVim dependencies
echo "Installing LazyVim dependencies..."
brew install neovim ripgrep fd lazygit

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

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "1. Start a new terminal session to load updated PATH"
echo "2. Run 'nvim' to complete LazyVim setup"
echo "3. Initialize Podman: podman machine init && podman machine start"
echo "4. Verify installations:"
echo "   - python3 --version"
echo "   - node --version"
echo "   - aws --version"
echo "   - claude --version"
echo "   - codex --version"
echo "   - omp --version"
echo "   - flutter --version"
echo "   - dart --version"
echo "   - ruff --version"
