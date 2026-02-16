#!/bin/bash
set -euo pipefail
PHASE=${1:-all}
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "=== MarkView Verification ==="

# Tier 0: Build all targets
echo ""
echo "--- Tier 0: Build ---"
BUILD_OUTPUT=$(swift build 2>&1)
if echo "$BUILD_OUTPUT" | tail -3 | grep -q "Build complete"; then
    echo "✓ All targets build successfully"
else
    echo "✗ Build failed"
    echo "$BUILD_OUTPUT" | tail -10
    exit 1
fi
[ "$PHASE" = "0" ] && exit 0

# Tier 1-3: Run full test suite (unit, GFM compliance, performance, golden files, E2E)
echo ""
echo "--- Tier 1-3: Full Test Suite ---"
TEST_OUTPUT=$(swift run MarkViewTestRunner 2>&1)
# Display test output (filter build noise)
echo "$TEST_OUTPUT" | grep -v "^Building\|^Build of\|^\[" | grep -v "^$"

# Check result from the last line
RESULT=$(echo "$TEST_OUTPUT" | tail -1)
if echo "$RESULT" | grep -q "0 failed"; then
    echo ""
    echo "=== All checks passed ==="
    exit 0
else
    echo ""
    echo "=== Some checks failed ==="
    exit 1
fi
