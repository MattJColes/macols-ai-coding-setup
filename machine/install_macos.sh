#!/bin/bash
#
# macOS workstation setup. Packages come from machine/Brewfile; the shared
# steps (Homebrew, Python via uv, Node via NVM, LazyVim, starship, git/AWS
# config) live in machine/common.sh. Idempotent: safe to re-run.

set -euo pipefail

echo "=== macOS Development Environment Setup ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Xcode Command Line Tools (required by Homebrew, Flutter, etc.)
if ! xcode-select -p &> /dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "Complete the Xcode CLT installation prompt, then re-run this script."
    exit 1
fi
echo "Xcode Command Line Tools found"

ensure_homebrew
brew update
brew_bundle

bash "$SCRIPT_DIR/install_zsh.sh"
install_python
install_node
install_gh_stack
install_lazyvim
setup_prompt

# herdr + its plugins and layouts, yazi config, tmux and the herdr SSH
# auto-launch hook (the same script Ubuntu runs).
bash "$SCRIPT_DIR/install_brew_herdr_yazi_lazygit_nvim.sh"

install_agent_tools

echo ""
echo "=== Configuration ==="
configure_git_identity
configure_aws

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "1. Start a new terminal session (zsh + starship)"
echo "2. Run 'nvim' to complete LazyVim setup"
echo "3. Initialise Podman: podman machine init && podman machine start"
echo "4. Optional: ./install_ghostty_config.sh and ./install_iterm_colors.sh"
echo "5. Verify installations:"
echo "   - python3 --version   (uv-managed 3.14)"
echo "   - node --version"
echo "   - aws --version"
echo "   - claude --version"
echo "   - codex --version"
echo "   - pi --version"
echo "   - omp --version"
echo "   - ls -d /Applications/ZCode.app"
echo "   - flutter --version"
echo "   - go version"
echo "   - ruff --version"
