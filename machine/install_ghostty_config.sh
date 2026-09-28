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
# Ghostty's cross-platform config path (preferred since 1.2; read on macOS
# and Linux). The old macOS-only location is migrated below.
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
TARGET_FILE="$TARGET_DIR/config.ghostty"
LEGACY_FILE="$HOME/Library/Application Support/com.mitchellh.ghostty/config"

print_status "Installing Ghostty configuration to $TARGET_FILE"

if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "Ghostty config file not found at: $CONFIG_FILE"
    exit 1
fi

mkdir -p "$TARGET_DIR"

if [[ -f "$TARGET_FILE" ]] && ! cmp -s "$CONFIG_FILE" "$TARGET_FILE"; then
    BACKUP_FILE="$TARGET_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$TARGET_FILE" "$BACKUP_FILE"
    print_warning "Backed up the existing config to $BACKUP_FILE"
fi

cp "$CONFIG_FILE" "$TARGET_FILE"
chmod 644 "$TARGET_FILE"

# A config at the old macOS path is also loaded and overrides this one, so
# move it aside if it is a copy this script installed earlier.
if [[ -f "$LEGACY_FILE" ]] && cmp -s "$CONFIG_FILE" "$LEGACY_FILE"; then
    mv "$LEGACY_FILE" "$LEGACY_FILE.migrated"
    print_status "Moved the old macOS-path copy aside ($LEGACY_FILE.migrated)"
elif [[ -f "$LEGACY_FILE" ]]; then
    print_warning "$LEGACY_FILE also exists and overrides this config; merge or remove it."
fi

print_status "Done. Reload Ghostty (Cmd/Ctrl + Shift + ,) to apply."
