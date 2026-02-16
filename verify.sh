#!/bin/bash
set -euo pipefail
PHASE=${1:-all}
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "=== MarkView Verification ==="

# Tier 0: Build all targets
echo ""
echo "--- Tier 0: Build ---"
if swift build 2>&1 | tail -3 | grep -q "Build complete"; then
    echo "✓ All targets build successfully"
else
    echo "✗ Build failed"
    swift build 2>&1 | tail -10
    exit 1
fi
[ "$PHASE" = "0" ] && exit 0

# Tier 1+2: Run test suite (includes unit tests, GFM compliance, performance, FileWatcher)
echo ""
echo "--- Tier 1+2: Test Suite ---"
swift run MarkViewTestRunner 2>&1 | grep -v "^Building\|^Build of\|^\[" | grep -v "^$"

# Extract result
RESULT=$(swift run MarkViewTestRunner 2>&1 | tail -1)
if echo "$RESULT" | grep -q "0 failed"; then
    echo ""
    echo "=== All checks passed ==="
    exit 0
else
    echo ""
    echo "=== Some checks failed ==="
    exit 1
fi
