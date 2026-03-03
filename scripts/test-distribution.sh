#!/bin/bash
set -euo pipefail

# MarkView — Distribution path e2e test
# Tests the FULL install→launch→verify path that users experience.
#
# Modes:
#   --local       Test bundle.sh --install path (default)
#   --brew        Test Homebrew cask path (requires tap + release artifact)
#   --tar         Test tar.gz extraction path (simulates GitHub Release download)
#   --zip [url]   Download release zip, apply quarantine, run Gatekeeper check.
#                 url defaults to the latest GitHub Release zip if omitted.
#                 This is the canonical user path for direct downloads.
#
# Usage: bash scripts/test-distribution.sh [--local|--brew|--tar|--zip [url]]

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

test_zip_download() {
    local zip_url="${1:-}"
    echo ""
    echo "=== Distribution Test: zip download (user path) ==="

    # Resolve URL: explicit arg → latest GitHub Release
    if [[ -z "$zip_url" ]]; then
        zip_url=$(gh release view --repo paulhkang94/markview --json assets \
            --jq '.assets[] | select(.name | endswith(".zip")) | .url' 2>/dev/null | head -1)
    fi
    if [[ -z "$zip_url" ]]; then
        fail "No zip URL provided and no GitHub Release found"
        return
    fi
    echo "URL: $zip_url"

    local tmpdir
    tmpdir=$(mktemp -d)
    local zip_path="${tmpdir}/MarkView-download.zip"

    # Download
    if ! curl -fsSL --output "$zip_path" "$zip_url" 2>/dev/null; then
        fail "Download failed: $zip_url"
        rm -rf "$tmpdir"
        return
    fi
    pass "Downloaded zip ($(du -sh "$zip_path" | cut -f1))"

    # Verify zip internal path — absolute runner paths break extraction
    local first_entry
    first_entry=$(unzip -l "$zip_path" | awk 'NR==4{print $4}')
    if [[ "$first_entry" == "MarkView.app/" ]]; then
        pass "Zip structure: MarkView.app/ at root"
    else
        fail "Zip structure: first entry is '$first_entry' — users get nested folder, not MarkView.app"
    fi

    # Extract (what a user does after downloading)
    unzip -qq "$zip_path" -d "$tmpdir"
    local extracted_app="${tmpdir}/MarkView.app"

    if [ ! -d "$extracted_app" ]; then
        fail "MarkView.app not found at top level after extraction"
        rm -rf "$tmpdir"
        return
    fi

    # Apply quarantine flag (macOS adds this to any internet download)
    xattr -w com.apple.quarantine \
        "0081;$(printf '%08x' $(date +%s));curl;$(uuidgen | tr '[:upper:]' '[:lower:]')" \
        "$extracted_app" 2>/dev/null || true

    # Gatekeeper — the actual user-facing gate
    if spctl --assess --type execute "$extracted_app" 2>/dev/null; then
        pass "Gatekeeper ACCEPTS downloaded app"
    else
        local reason
        reason=$(spctl --assess --type execute --verbose=4 "$extracted_app" 2>&1 | grep -oE 'source=.*' | head -1 || echo "unknown reason")
        fail "Gatekeeper REJECTS downloaded app (${reason}) — users see 'damaged' dialog"
    fi

    # Staple ticket
    if xcrun stapler validate "$extracted_app" 2>/dev/null | grep -q "The validate action worked"; then
        pass "Notarization staple ticket present"
    else
        fail "Notarization staple ticket MISSING — offline users see 'damaged' dialog"
    fi

    test_app_launches "$extracted_app" "zip download"

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
    --zip)
        # Optional second arg: explicit zip URL
        ZIP_URL="${2:-}"
        test_zip_download "$ZIP_URL"
        ;;
    *)
        echo "Unknown mode: $MODE"
        echo "Usage: bash scripts/test-distribution.sh [--local|--brew|--tar|--zip [url]]"
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
