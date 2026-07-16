#!/bin/bash

# iTerm2 Color Scheme Installer
# This script installs .itermcolors files to the correct iTerm2 directory

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Installing iTerm2 color schemes..."

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Error: This script is intended for macOS only."
    exit 1
fi

# Check if iTerm2 is installed
if ! [ -d "/Applications/iTerm.app" ] && ! [ -d "$HOME/Applications/iTerm.app" ]; then
    echo "Warning: iTerm2 doesn't appear to be installed."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create iTerm2 color schemes directory if it doesn't exist
mkdir -p "$HOME/Library/Application Support/iTerm2/ColorPresets"

# Find and copy all .itermcolors files
COLORS_COPIED=0
for colorfile in "$SCRIPT_DIR"/*.itermcolors; do
    if [ -f "$colorfile" ]; then
        BASENAME=$(basename "$colorfile")
        cp "$colorfile" "$HOME/Library/Application Support/iTerm2/ColorPresets/"
        echo "✓ Installed: $BASENAME"
        COLORS_COPIED=$((COLORS_COPIED + 1))
    fi
done

if [ $COLORS_COPIED -eq 0 ]; then
    echo "No .itermcolors files found in $SCRIPT_DIR"
    exit 1
fi

echo ""
echo "Successfully installed $COLORS_COPIED color scheme(s)!"
echo ""
echo "To apply the color scheme:"
echo "1. Open iTerm2"
echo "2. Go to Preferences (⌘,)"
echo "3. Go to Profiles > Colors"
echo "4. Click 'Color Presets...' dropdown"
echo "5. Select your desired color scheme"
