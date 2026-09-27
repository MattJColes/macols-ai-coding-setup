#!/bin/bash

# Oh My Zsh and Powerlevel10k Installer
# This script installs Oh My Zsh and Powerlevel10k with default settings

# Re-exec under bash if invoked with sh/dash ($OSTYPE and [[ ]] are bash-only)
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

echo "Installing Oh My Zsh and Powerlevel10k..."
echo ""

# Check if zsh is installed, install if missing
if ! command -v zsh &> /dev/null; then
    echo "zsh is not installed. Installing..."

    # Detect OS and install zsh
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install zsh
        else
            echo "Error: Homebrew not found. Please install Homebrew first:"
            echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y zsh
        elif command -v yum &> /dev/null; then
            sudo yum install -y zsh
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y zsh
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm zsh
        else
            echo "Error: Unsupported package manager. Please install zsh manually."
            exit 1
        fi
    else
        echo "Error: Unsupported OS. Please install zsh manually."
        exit 1
    fi

    echo "✓ zsh installed"
fi

# Install Oh My Zsh
if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "Oh My Zsh is already installed. Skipping..."
else
    echo "Installing Oh My Zsh..."
    RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    echo "✓ Oh My Zsh installed"
fi

# --unattended forces CHSH=no in the installer, so change the login shell ourselves
if [ "$(basename "$SHELL")" != "zsh" ]; then
    echo "Changing default shell to zsh (you may be prompted for your password)..."
    chsh -s "$(command -v zsh)"
    echo "✓ Default shell changed to zsh (takes effect on next login)"
fi

echo ""

# Install Powerlevel10k
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ -d "$P10K_DIR" ]; then
    echo "Powerlevel10k is already installed. Updating..."
    git -C "$P10K_DIR" pull
else
    echo "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    echo "✓ Powerlevel10k installed"
fi

echo ""

# Update .zshrc to use Powerlevel10k theme
if [ -f "$HOME/.zshrc" ]; then
    if grep -q "^ZSH_THEME=" "$HOME/.zshrc"; then
        # macOS sed requires different syntax than Linux
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
        else
            sed -i.bak 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
        fi
        echo "✓ Updated .zshrc to use Powerlevel10k theme"
    else
        echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$HOME/.zshrc"
        echo "✓ Added Powerlevel10k theme to .zshrc"
    fi
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Install the recommended Meslo Nerd Font:"
echo "   https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k"
echo "2. Configure iTerm2 to use the MesloLGS NF font"
echo "3. Restart your terminal or run: exec zsh"
echo "4. The Powerlevel10k configuration wizard will start automatically"
echo "   (or run 'p10k configure' to start it manually)"
echo ""
echo "The wizard will guide you through customization with visual examples."
echo "Just follow the prompts and select your preferred options!"
