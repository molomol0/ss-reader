#!/bin/bash

set -e

INSTALL_DIR="${HOME}/.ss-reader"
REPO_URL="https://github.com/molomol0/ss-reader.git"
BIN_DIR="${HOME}/.local/bin"

# Clone the repo
if [[ -d "$INSTALL_DIR" ]]; then
    echo "Updating existing installation..."
    git -C "$INSTALL_DIR" pull
else
    echo "Cloning ss-reader..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Make executable
chmod +x "$INSTALL_DIR/reader.sh"

# Create bin directory if needed
mkdir -p "$BIN_DIR"

# Symlink into PATH
ln -sf "$INSTALL_DIR/reader.sh" "$BIN_DIR/ss-reader"

# Check if ~/.local/bin is in PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    echo ""
    echo "Add this to your shell config (~/.bashrc or ~/.zshrc):"
    echo ""
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

echo "Installed! Run 'ss-reader' to start reading."
