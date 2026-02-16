#!/bin/bash
set -euo pipefail

# MarkView — Install CLI commands (md, mdpreview)
# Usage: bash scripts/install-cli.sh

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$PROJECT_DIR/.build/release/MarkView"
BIN_DIR="$HOME/.local/bin"

if [ ! -f "$BINARY" ]; then
    echo "Release binary not found. Building first..."
    cd "$PROJECT_DIR" && swift build -c release 2>&1 | tail -3
fi

mkdir -p "$BIN_DIR"

# Create symlinks
ln -sf "$BINARY" "$BIN_DIR/md"
ln -sf "$BINARY" "$BIN_DIR/mdpreview"

echo "✓ Installed CLI commands:"
echo "  $BIN_DIR/md → $BINARY"
echo "  $BIN_DIR/mdpreview → $BINARY"
echo ""

# Check if ~/.local/bin is in PATH
if echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo "✓ ~/.local/bin is in PATH"
else
    echo "⚠ Add ~/.local/bin to your PATH:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Usage:"
echo "  md README.md          # Open file in MarkView"
echo "  md                    # Open MarkView (empty)"
echo "  mdpreview README.md   # Same thing"
