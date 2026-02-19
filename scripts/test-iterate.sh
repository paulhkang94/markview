#!/bin/bash
set -euo pipefail
# MarkView — Build, test, and optionally install + E2E verify in one shot.
# Usage:
#   bash scripts/test-iterate.sh           # Build + unit tests only
#   bash scripts/test-iterate.sh --install # Build + tests + install + E2E menu check
#   bash scripts/test-iterate.sh --e2e     # Build + tests + install + full E2E (launch, verify menus, quit)

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
MODE="${1:-}"

echo "=== Bootstrap Dependencies ==="
bash scripts/bootstrap-swiftpm.sh
echo ""

echo "=== Build ==="
swift build 2>&1 | tail -3
echo ""

echo "=== Unit Tests ==="
swift run MarkViewTestRunner 2>&1 | grep -v "^\[" | grep -v "^$" | grep -v "^Building\|^Build of"
echo ""

# Stop here if no install/e2e flag
[ -z "$MODE" ] && exit 0

echo "=== Bundle + Install ==="
bash scripts/bundle.sh --install 2>&1 | grep -E "(✓|✗|⚠|===)"
echo ""

[ "$MODE" = "--install" ] && exit 0

# E2E: Launch app, verify menus, quit cleanly
echo "=== E2E: App Launch + Menu Verification ==="
pkill -f "MarkView.app" 2>/dev/null; sleep 1
open /Applications/MarkView.app --args "$PROJECT_DIR/Tests/TestRunner/Fixtures/basic.md"
sleep 3

# Verify Edit menu has Find commands
EDIT_MENU=$(osascript -e '
tell application "System Events"
    tell process "MarkView"
        set editItems to name of every menu item of menu 1 of menu bar item "Edit" of menu bar 1
        return editItems as text
    end tell
end tell' 2>&1)

PASS=true
for ITEM in "Find..." "Find Next" "Find Previous" "Find and Replace..."; do
    if echo "$EDIT_MENU" | grep -q "$ITEM"; then
        echo "  ✓ Edit menu has: $ITEM"
    else
        echo "  ✗ Edit menu missing: $ITEM"
        PASS=false
    fi
done

# Verify lint popover button exists (check for ⚠ in status bar)
echo ""
echo "--- Lint Popover (visual check) ---"
echo "  ℹ Open a file with lint issues to verify clickable ⚠ icon"

# Clean quit
echo ""
osascript -e 'tell application "MarkView" to quit' 2>/dev/null
sleep 1
echo "✓ App quit cleanly"

if [ "$PASS" = true ]; then
    echo ""
    echo "=== E2E verification passed ==="
else
    echo ""
    echo "=== E2E verification FAILED ==="
    exit 1
fi
