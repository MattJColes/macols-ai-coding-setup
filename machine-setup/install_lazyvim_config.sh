#!/bin/bash

# Script to install LazyVim configuration from this repository
# Usage: ./install_lazyvim_config.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAZYVIM_SOURCE_DIR="$SCRIPT_DIR/Lazyvim"
NVIM_CONFIG_DIR="$HOME/.config/nvim"

print_status "Installing LazyVim configuration..."

# Check if source directory exists
if [ ! -d "$LAZYVIM_SOURCE_DIR" ]; then
    print_error "LazyVim source directory not found: $LAZYVIM_SOURCE_DIR"
    exit 1
fi

# Check if nvim config directory exists
if [ ! -d "$NVIM_CONFIG_DIR" ]; then
    print_status "Creating Neovim config directory: $NVIM_CONFIG_DIR"
    mkdir -p "$NVIM_CONFIG_DIR"
else
    print_warning "Neovim config directory already exists. Backing up..."
    BACKUP_DIR="${NVIM_CONFIG_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    cp -r "$NVIM_CONFIG_DIR" "$BACKUP_DIR"
    print_status "Backup created: $BACKUP_DIR"
fi

# Copy configuration files
print_status "Copying LazyVim configuration files..."
cp -r "$LAZYVIM_SOURCE_DIR"/* "$NVIM_CONFIG_DIR/"

# Set proper permissions
print_status "Setting proper permissions..."
find "$NVIM_CONFIG_DIR" -type f -name "*.lua" -exec chmod 644 {} \;

print_status "LazyVim configuration installed successfully!"
print_status "You can now start Neovim and the plugins will be automatically installed."
print_status "Run 'nvim' to start using your LazyVim setup."