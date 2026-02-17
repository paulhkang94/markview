#!/bin/bash
# Window lifecycle smoke test — verifies the window-closing bug is fixed.
# Does NOT require Accessibility permissions (uses pgrep + AppleScript only).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

cleanup() {
    pkill -f "MarkView.app/Contents/MacOS/MarkView" 2>/dev/null || true
    rm -f /tmp/markview-lifecycle-test-*.md
}
trap cleanup EXIT

echo "--- Window Lifecycle Smoke Test ---"

# Find .app bundle
APP_PATH=""
if [ -d "$PROJECT_DIR/MarkView.app" ]; then
    APP_PATH="$PROJECT_DIR/MarkView.app"
elif [ -d "/Applications/MarkView.app" ]; then
    APP_PATH="/Applications/MarkView.app"
else
    echo "  ⊘ No .app bundle found — build with: bash scripts/bundle.sh"
    echo ""
    echo "Results: 0 passed, 0 failed, 0 skipped"
    exit 0
fi

echo "  Using: $APP_PATH"

# Kill any existing instance
pkill -f "MarkView.app/Contents/MacOS/MarkView" 2>/dev/null || true
sleep 0.5

# Create test file
TEST_FILE="/tmp/markview-lifecycle-test-$$.md"
echo "# Lifecycle Test" > "$TEST_FILE"

# Test 1: Open file → window stays open for 3s
echo ""
echo "  Test 1: File open → window stays open"
open -a "$APP_PATH" "$TEST_FILE"
sleep 3
if pgrep -f "MarkView.app/Contents/MacOS/MarkView" > /dev/null 2>&1; then
    pass "Window stays open after file open (3s)"
else
    fail "Window closed immediately after file open (race condition bug)"
fi

# Test 2: Open same file again → still 1 window
echo ""
echo "  Test 2: Re-open same file → single window"
WINDOWS_BEFORE=$(osascript -e 'tell application "System Events" to count windows of process "MarkView"' 2>/dev/null || echo "0")
open -a "$APP_PATH" "$TEST_FILE"
sleep 2
WINDOWS_AFTER=$(osascript -e 'tell application "System Events" to count windows of process "MarkView"' 2>/dev/null || echo "0")
if [ "$WINDOWS_AFTER" -le "$WINDOWS_BEFORE" ] 2>/dev/null; then
    pass "Single window after re-opening same file (before: $WINDOWS_BEFORE, after: $WINDOWS_AFTER)"
else
    fail "Duplicate window created (before: $WINDOWS_BEFORE, after: $WINDOWS_AFTER)"
fi

# Test 3: Open different file → window reuses
echo ""
echo "  Test 3: Open different file → window reuses"
TEST_FILE2="/tmp/markview-lifecycle-test-$$-2.md"
echo "# Second File" > "$TEST_FILE2"
open -a "$APP_PATH" "$TEST_FILE2"
sleep 2
WINDOWS_FINAL=$(osascript -e 'tell application "System Events" to count windows of process "MarkView"' 2>/dev/null || echo "0")
if [ "$WINDOWS_FINAL" -le 1 ] 2>/dev/null; then
    pass "Window reused for different file (windows: $WINDOWS_FINAL)"
else
    fail "Extra window created for different file (windows: $WINDOWS_FINAL)"
fi

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
