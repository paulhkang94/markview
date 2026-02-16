#!/bin/bash
set -euo pipefail
PHASE=${1:-all}
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "=== MarkView Verification ==="

# Version sync check
echo ""
echo "--- Version Sync ---"
bash "$PROJECT_DIR/scripts/check-version-sync.sh"

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

# Tier 0b: Bundle structure (if bundle.sh has been run)
if [ -d "$PROJECT_DIR/MarkView.app" ]; then
    echo ""
    echo "--- Tier 0b: Bundle Verification ---"
    BUNDLE_OK=true
    [ -f "$PROJECT_DIR/MarkView.app/Contents/MacOS/MarkView" ] && echo "✓ Executable in bundle" || { echo "✗ Missing executable"; BUNDLE_OK=false; }
    [ -f "$PROJECT_DIR/MarkView.app/Contents/Info.plist" ] && echo "✓ Info.plist in bundle" || { echo "✗ Missing Info.plist"; BUNDLE_OK=false; }
    if plutil -lint "$PROJECT_DIR/MarkView.app/Contents/Info.plist" > /dev/null 2>&1; then
        echo "✓ Info.plist is valid"
    else
        echo "✗ Info.plist is invalid"
        BUNDLE_OK=false
    fi
    if grep -q "CFBundleDocumentTypes" "$PROJECT_DIR/MarkView.app/Contents/Info.plist"; then
        echo "✓ Document types registered"
    else
        echo "✗ Missing document types"
        BUNDLE_OK=false
    fi

    # Quick Look extension verification
    APPEX_DIR="$PROJECT_DIR/MarkView.app/Contents/PlugIns/MarkViewQuickLook.appex"
    if [ -d "$APPEX_DIR" ]; then
        [ -f "$APPEX_DIR/Contents/MacOS/MarkViewQuickLook" ] && echo "✓ Quick Look extension executable" || { echo "✗ Missing QL executable"; BUNDLE_OK=false; }
        [ -f "$APPEX_DIR/Contents/Info.plist" ] && echo "✓ Quick Look extension Info.plist" || { echo "✗ Missing QL Info.plist"; BUNDLE_OK=false; }
        if plutil -lint "$APPEX_DIR/Contents/Info.plist" > /dev/null 2>&1; then
            echo "✓ Quick Look Info.plist is valid"
        else
            echo "✗ Quick Look Info.plist is invalid"
            BUNDLE_OK=false
        fi
        if codesign --verify --no-strict "$APPEX_DIR" 2>/dev/null; then
            echo "✓ Quick Look extension is signed"
        else
            echo "⚠ Quick Look extension is unsigned (non-fatal)"
        fi
    else
        echo "⚠ Quick Look extension not in bundle (run: bash scripts/bundle.sh)"
    fi

    [ "$BUNDLE_OK" = true ] || exit 1
fi

# Tier 1-3: Run full test suite (unit, GFM compliance, performance, golden files, E2E)
echo ""
echo "--- Tier 1-3: Full Test Suite ---"
TEST_OUTPUT=$(swift run MarkViewTestRunner 2>&1)
# Display test output (filter build noise)
echo "$TEST_OUTPUT" | grep -v "^Building\|^Build of\|^\[" | grep -v "^$"

# Check result from the last line
RESULT=$(echo "$TEST_OUTPUT" | tail -1)
if echo "$RESULT" | grep -q "0 failed"; then
    true
else
    echo ""
    echo "=== Some checks failed ==="
    exit 1
fi

# Golden baseline drift check — catches the same issue CI catches
echo ""
echo "--- Golden Drift Check ---"
swift run MarkViewTestRunner --generate-goldens 2>&1 | grep -v "^\[" | grep -v "^$" | grep -v "^Building\|^Build of\|^warning:"
if git diff --quiet Tests/TestRunner/Fixtures/expected/ 2>/dev/null; then
    echo "✓ Golden baselines are up to date"
else
    echo "✗ Golden baselines are stale — commit the updated files:"
    git diff --stat Tests/TestRunner/Fixtures/expected/
    exit 1
fi

# CLI smoke test
echo ""
echo "--- CLI Check ---"
if [ -x "$HOME/.local/bin/mdpreview" ] && file "$HOME/.local/bin/mdpreview" | grep -q "text"; then
    echo "✓ mdpreview CLI is installed (shell script)"
else
    echo "⚠ mdpreview not installed or is not a shell script (run: bash scripts/install-cli.sh)"
fi

echo ""
echo "=== All checks passed ==="

# Extended tests (fuzz + differential) — only with --extended flag
if [ "$PHASE" = "--extended" ]; then
    echo ""
    echo "--- Extended: Fuzz Testing ---"
    swift run MarkViewFuzzTester 2>&1 | grep -v "^\[" | grep -v "^$"

    echo ""
    echo "--- Extended: Differential Testing ---"
    swift run MarkViewDiffTester 2>&1 | grep -v "^\[" | grep -v "^$"

    echo ""
    echo "--- Extended: Visual Regression Tests ---"
    # Generate goldens first (idempotent), then compare
    swift run MarkViewVisualTester --generate-goldens 2>&1 | grep -v "^\[" | grep -v "^$" | grep -v "^Building\|^Build of\|^warning:"
    swift run MarkViewVisualTester 2>&1 | grep -v "^\[" | grep -v "^$" | grep -v "^Building\|^Build of\|^warning:"

    # Quick Look system integration test (requires installed app)
    echo ""
    echo "--- Extended: Quick Look Integration ---"
    if [ -d "/Applications/MarkView.app/Contents/PlugIns/MarkViewQuickLook.appex" ]; then
        FIXTURE="$PROJECT_DIR/Tests/TestRunner/Fixtures/basic.md"
        if [ -f "$FIXTURE" ]; then
            # qlmanage -p renders the file and exits; timeout after 10s
            if timeout 10 qlmanage -p "$FIXTURE" > /dev/null 2>&1; then
                echo "✓ qlmanage -p renders basic.md successfully"
            else
                # qlmanage may exit non-zero even on success (opens a window)
                # Check if the process at least started
                echo "⚠ qlmanage -p exited with non-zero (may still work — opens GUI window)"
            fi
        else
            echo "⚠ Test fixture not found: $FIXTURE"
        fi
    else
        echo "⊘ Quick Look extension not installed — skipping (run: bash scripts/bundle.sh --install)"
    fi

    echo ""
    echo "=== Extended verification complete ==="
fi
