#!/bin/bash
#
# zsh + Oh My Zsh, and zsh as the login shell. The prompt is starship, set up
# by common.sh's setup_prompt (Powerlevel10k is retired: its README now says
# most bugs will go unfixed). Idempotent; safe to re-run.

# Re-exec under bash if invoked with sh/dash ($OSTYPE and [[ ]] are bash-only)
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

if ! command -v zsh &> /dev/null; then
    echo "Installing zsh..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install zsh
    elif command -v apt-get &> /dev/null; then
        { sudo apt-get update -y || true; } && sudo apt-get install -y zsh
    else
        echo "Error: install zsh manually, then re-run." >&2
        exit 1
    fi
fi

if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "Oh My Zsh already installed."
else
    echo "Installing Oh My Zsh..."
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# The Oh My Zsh installer leaves CHSH=no under --unattended, so switch the
# login shell here. sudo avoids chsh's interactive password prompt; the shell
# must be listed in /etc/shells.
ZSH_BIN="$(command -v zsh)"
CURRENT_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
if [ "$(basename "${CURRENT_SHELL:-$SHELL}")" != "zsh" ]; then
    grep -qxF "$ZSH_BIN" /etc/shells || echo "$ZSH_BIN" | sudo tee -a /etc/shells > /dev/null
    echo "Changing the login shell to zsh..."
    sudo chsh -s "$ZSH_BIN" "$USER" || echo "⚠ could not change the login shell; run: chsh -s $ZSH_BIN" >&2
fi
