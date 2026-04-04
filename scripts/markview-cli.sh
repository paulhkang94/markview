#!/bin/bash
# markview — CLI entry point for MarkView.app
# Usage:
#   markview              open MarkView
#   markview file.md      open file in MarkView
#   markview *.md         open multiple files
#   markview --version    print version
#   markview --help       show this help

set -euo pipefail

APP_NAME="MarkView"

if [ $# -eq 0 ]; then
    open -a "$APP_NAME"
    exit 0
fi

case "${1:-}" in
    --help|-h)
        echo "Usage: markview [file.md ...]"
        echo ""
        echo "Opens markdown files in MarkView.app."
        echo "With no arguments, launches MarkView."
        exit 0
        ;;
    --version|-v)
        defaults read /Applications/MarkView.app/Contents/Info CFBundleShortVersionString 2>/dev/null \
            || echo "MarkView (version unknown)"
        exit 0
        ;;
esac

for file in "$@"; do
    abs="$(cd "$(dirname "$file")" 2>/dev/null && pwd)/$(basename "$file")"
    if [ ! -f "$abs" ]; then
        echo "markview: not found: $file" >&2
        continue
    fi
    open -a "$APP_NAME" "$abs"
done
