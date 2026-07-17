#!/bin/bash

# Ghostty Configuration Installation Script for macOS
# This script installs the Ghostty configuration file to the correct directory

set -e  # Exit on any error

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

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/ghostty_config"
TARGET_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
TARGET_FILE="$TARGET_DIR/config"

print_status "Ghostty Configuration Installation Script"
print_status "======================================="

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print_error "This script is designed for macOS only"
    exit 1
fi

# Check if Ghostty config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "Ghostty config file not found at: $CONFIG_FILE"
    print_error "Make sure the ghostty_config file is in the same directory as this script"
    exit 1
fi

print_status "Found Ghostty config file at: $CONFIG_FILE"

# Create target directory if it doesn't exist
if [[ ! -d "$TARGET_DIR" ]]; then
    print_status "Creating Ghostty config directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
else
    print_status "Ghostty config directory exists: $TARGET_DIR"
fi

# Check if target config file already exists
if [[ -f "$TARGET_FILE" ]]; then
    print_warning "Existing Ghostty config found at: $TARGET_FILE"

    # Ask user if they want to backup the existing config
    echo -n "Do you want to backup the existing config? (y/n): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        BACKUP_FILE="$TARGET_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        print_status "Creating backup: $BACKUP_FILE"
        cp "$TARGET_FILE" "$BACKUP_FILE"
        print_status "Backup created successfully"
    fi
fi

# Copy the config file
print_status "Installing Ghostty configuration..."
cp "$CONFIG_FILE" "$TARGET_FILE"

# Verify the installation
if [[ -f "$TARGET_FILE" ]]; then
    print_status "Ghostty configuration installed successfully!"
    print_status "Config file location: $TARGET_FILE"

    # Set proper permissions
    chmod 644 "$TARGET_FILE"
    print_status "Permissions set to 644"

    echo ""
    print_status "Installation complete!"
    print_status "You may need to restart Ghostty or use Command + Shift + , to reload the configuration"
else
    print_error "Failed to install Ghostty configuration"
    exit 1
fi