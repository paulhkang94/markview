#!/bin/bash
set -euo pipefail

# MarkView — Install CLI command (mdpreview)
# Usage: bash scripts/install-cli.sh

APP_PATH="/Applications/MarkView.app"
BIN_DIR="$HOME/.local/bin"
CLI_PATH="$BIN_DIR/mdpreview"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: MarkView.app not found at $APP_PATH"
    echo "Run 'bash scripts/bundle.sh --install' first."
    exit 1
fi

mkdir -p "$BIN_DIR"

# Create a wrapper script that uses `open -a` to open files with MarkView
cat > "$CLI_PATH" << 'SCRIPT'
#!/bin/bash
if [ $# -eq 0 ]; then
    open -a MarkView
else
    # Resolve to absolute path and open the file with MarkView
    FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    open -a MarkView "$FILE"
fi
SCRIPT
chmod +x "$CLI_PATH"

echo "✓ Installed CLI command:"
echo "  $CLI_PATH → opens /Applications/MarkView.app"
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
echo "  mdpreview README.md   # Open file in MarkView"
echo "  mdpreview             # Open MarkView (empty)"
