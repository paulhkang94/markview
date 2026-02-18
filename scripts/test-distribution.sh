#!/bin/bash
set -euo pipefail

# MarkView — Distribution path e2e test
# Tests the FULL install→launch→verify path that users experience.
#
# Modes:
#   --local    Test bundle.sh --install path (default)
#   --brew     Test Homebrew cask path (requires tap + release artifact)
#   --tar      Test tar.gz extraction path (simulates GitHub Release download)
#
# Usage: bash scripts/test-distribution.sh [--local|--brew|--tar]

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

MODE="${1:---local}"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

cleanup_test_app() {
    local app_path="$1"
    if [ -d "$app_path" ] && [ "$app_path" != "/Applications/MarkView.app" ]; then
        rm -rf "$app_path"
    fi
}

test_app_launches() {
    local app_path="$1"
    local context="$2"

    echo ""
    echo "--- Testing app launch: $context ---"

    # 1. App exists
    if [ -d "$app_path" ]; then
        pass "App bundle exists"
    else
        fail "App bundle missing at $app_path"
        return
    fi

    # 2. Executable runs (--help or version check, not GUI)
    local exe="$app_path/Contents/MacOS/MarkView"
    if [ -x "$exe" ]; then
        pass "Executable is present and executable"
    else
        fail "Executable missing or not executable"
    fi

    # 3. No quarantine flag
    local xattrs
    xattrs=$(xattr "$app_path" 2>/dev/null || true)
    if echo "$xattrs" | grep -q "com.apple.quarantine"; then
        fail "QUARANTINE FLAG PRESENT — users will see 'damaged' dialog"
    else
        pass "No quarantine flag"
    fi

    # 4. Code signature valid
    if codesign --verify --deep --strict "$app_path" 2>/dev/null; then
        pass "Code signature valid"
    else
        fail "Code signature invalid"
    fi

    # 5. MCP server present
    if [ -f "$app_path/Contents/MacOS/markview-mcp-server" ]; then
        pass "MCP server binary present"
    else
        fail "MCP server binary missing"
    fi

    # 6. Quick Look extension present
    if [ -d "$app_path/Contents/PlugIns/MarkViewQuickLook.appex" ]; then
        pass "Quick Look extension present"
    else
        fail "Quick Look extension missing"
    fi

    # 7. Info.plist valid
    if plutil -lint "$app_path/Contents/Info.plist" > /dev/null 2>&1; then
        pass "Info.plist valid"
    else
        fail "Info.plist invalid"
    fi

    # 8. Version is set (not empty/unknown)
    local version
    version=$(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist" 2>/dev/null || echo "")
    if [ -n "$version" ] && [ "$version" != "unknown" ]; then
        pass "Version: $version"
    else
        fail "Version missing or unknown"
    fi

    # 9. Launch Services can resolve the bundle ID
    if mdls -name kMDItemCFBundleIdentifier "$app_path" 2>/dev/null | grep -q "com.markview.app"; then
        pass "Launch Services recognizes bundle ID"
    else
        # Fall back to checking if the app can be found by bundle ID
        local resolved
        resolved=$(mdfind "kMDItemCFBundleIdentifier == 'com.markview.app'" 2>/dev/null | head -1)
        if [ -n "$resolved" ]; then
            pass "Launch Services can resolve app via Spotlight"
        else
            # On CI or fresh installs, Spotlight may not have indexed yet — non-fatal
            echo "  ⚠ Launch Services not yet indexed (non-fatal on CI/fresh install)"
        fi
    fi
}

test_tar_extraction() {
    echo ""
    echo "=== Distribution Test: tar.gz extraction ==="

    # Find latest tar.gz
    local tarball
    tarball=$(ls -t "$PROJECT_DIR"/MarkView-*.tar.gz 2>/dev/null | head -1)
    if [ -z "$tarball" ]; then
        fail "No MarkView-*.tar.gz found in project root"
        fail "Build one with: bash scripts/bundle.sh && tar -czf MarkView-VERSION.tar.gz MarkView.app"
        return
    fi

    echo "Testing: $tarball"

    # Extract to temp dir (simulates what Homebrew does)
    local tmpdir
    tmpdir=$(mktemp -d)
    tar -xzf "$tarball" -C "$tmpdir"

    local extracted_app="$tmpdir/MarkView.app"

    # Simulate quarantine flag (what macOS adds to downloads)
    xattr -w com.apple.quarantine "0081;$(date +%s);test;$(uuidgen)" "$extracted_app" 2>/dev/null || true

    # Check quarantine is set (simulating download)
    local has_quarantine
    has_quarantine=$(xattr "$extracted_app" 2>/dev/null | grep -c quarantine || true)
    if [ "$has_quarantine" -gt 0 ]; then
        echo "  (quarantine flag set — simulating download)"

        # Now test: would Gatekeeper pass?
        if spctl --assess --type execute "$extracted_app" 2>/dev/null; then
            pass "Gatekeeper ACCEPTS downloaded app (notarized)"
        else
            fail "Gatekeeper REJECTS downloaded app (needs notarization or quarantine stripping)"
            echo "    Users downloading this tar.gz will see 'damaged' dialog"
            echo "    Fix: notarize the app, or document xattr workaround"
        fi
    fi

    test_app_launches "$extracted_app" "tar.gz extraction"

    cleanup_test_app "$extracted_app"
    rm -rf "$tmpdir"
}

# --- Main ---
echo "=== MarkView Distribution E2E Test ==="
echo "Mode: $MODE"

case "$MODE" in
    --local)
        echo ""
        echo "=== Distribution Test: local bundle.sh --install ==="
        test_app_launches "/Applications/MarkView.app" "local install"
        ;;
    --brew)
        echo ""
        echo "=== Distribution Test: Homebrew cask ==="
        echo "Reinstalling via Homebrew..."
        brew uninstall --cask markview 2>/dev/null || true
        brew install --cask paulhkang94/markview/markview
        test_app_launches "/Applications/MarkView.app" "Homebrew cask"
        ;;
    --tar)
        test_tar_extraction
        ;;
    *)
        echo "Unknown mode: $MODE"
        echo "Usage: bash scripts/test-distribution.sh [--local|--brew|--tar]"
        exit 1
        ;;
esac

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    echo "DISTRIBUTION TEST FAILED — do not release until fixed"
    exit 1
else
    echo "Distribution test passed"
fi
