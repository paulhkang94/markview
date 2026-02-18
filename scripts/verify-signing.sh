#!/bin/bash
set -euo pipefail

# MarkView — E2E signing and distribution verification
# Verifies that a built .app bundle meets distribution requirements:
#   1. Valid code signature (deep + strict)
#   2. Hardened runtime enabled
#   3. Correct team identifier
#   4. Gatekeeper acceptance (requires notarization for Developer ID)
#   5. Notarization ticket stapled
#   6. MCP server binary signed
#   7. Quick Look extension signed
#   8. No quarantine flags after local install
#
# Usage: bash scripts/verify-signing.sh [/path/to/MarkView.app]
# Default: checks both ./MarkView.app and /Applications/MarkView.app

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠ $1"; WARN=$((WARN + 1)); }

verify_app() {
    local APP_PATH="$1"
    local CONTEXT="$2"  # "repo" or "installed"

    echo ""
    echo "--- Verifying: $APP_PATH ($CONTEXT) ---"

    if [ ! -d "$APP_PATH" ]; then
        warn "App not found at $APP_PATH — skipping"
        return
    fi

    # 1. Basic code signature
    if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
        pass "Code signature valid (deep + strict)"
    else
        fail "Code signature invalid or missing"
    fi

    # 2. Signing identity details
    local SIGN_INFO
    SIGN_INFO=$(codesign -d --verbose=2 "$APP_PATH" 2>&1 || true)

    local IS_ADHOC=false
    local IS_DEVID=false

    if echo "$SIGN_INFO" | grep -q "Signature=adhoc"; then
        IS_ADHOC=true
        warn "Signed ad-hoc (Developer ID required for distribution)"
    elif echo "$SIGN_INFO" | grep -q "Developer ID Application"; then
        IS_DEVID=true
        pass "Signed with Developer ID Application"
    else
        fail "Unknown signing identity"
    fi

    # 3. Hardened runtime
    local FLAGS
    FLAGS=$(echo "$SIGN_INFO" | grep "flags=" || true)
    if echo "$FLAGS" | grep -q "runtime"; then
        pass "Hardened runtime enabled"
    else
        if [ "$IS_DEVID" = true ]; then
            fail "Hardened runtime NOT enabled (required for notarization)"
        else
            warn "Hardened runtime not enabled (expected for ad-hoc)"
        fi
    fi

    # 4. Team identifier
    local TEAM
    TEAM=$(echo "$SIGN_INFO" | grep "TeamIdentifier=" | sed 's/TeamIdentifier=//' || true)
    if [ "$IS_DEVID" = true ]; then
        if [ -n "$TEAM" ] && [ "$TEAM" != "not set" ]; then
            pass "Team identifier: $TEAM"
        else
            fail "Team identifier missing"
        fi
    fi

    # 5. Gatekeeper assessment
    if [ "$IS_DEVID" = true ]; then
        if spctl --assess --type execute "$APP_PATH" 2>/dev/null; then
            pass "Gatekeeper: ACCEPTED"
        else
            fail "Gatekeeper: REJECTED (app needs notarization for distribution)"
        fi
    fi

    # 6. Notarization ticket
    if xcrun stapler validate "$APP_PATH" 2>/dev/null; then
        pass "Notarization ticket: stapled"
    else
        if [ "$IS_DEVID" = true ]; then
            fail "Notarization ticket: NOT stapled (run: bash scripts/bundle.sh --notarize)"
        else
            warn "Notarization ticket: not applicable (ad-hoc signed)"
        fi
    fi

    # 7. MCP server binary
    local MCP_BIN="$APP_PATH/Contents/MacOS/markview-mcp-server"
    if [ -f "$MCP_BIN" ]; then
        if codesign --verify --strict "$MCP_BIN" 2>/dev/null; then
            pass "MCP server binary: signed"
        else
            fail "MCP server binary: NOT signed"
        fi
    else
        warn "MCP server binary not found in bundle"
    fi

    # 8. Quick Look extension
    local QL_APPEX="$APP_PATH/Contents/PlugIns/MarkViewQuickLook.appex"
    if [ -d "$QL_APPEX" ]; then
        if codesign --verify --deep --strict "$QL_APPEX" 2>/dev/null; then
            pass "Quick Look extension: signed"
        else
            warn "Quick Look extension: signature verification failed"
        fi
    else
        warn "Quick Look extension not found in bundle"
    fi

    # 9. Quarantine flag (only for installed apps)
    if [ "$CONTEXT" = "installed" ]; then
        local XATTRS
        XATTRS=$(xattr "$APP_PATH" 2>/dev/null || true)
        if echo "$XATTRS" | grep -q "com.apple.quarantine"; then
            fail "Quarantine flag PRESENT on installed app (users will see 'damaged' dialog)"
        else
            pass "No quarantine flag on installed app"
        fi
    fi

    # 10. Entitlements present
    local ENTITLEMENTS
    ENTITLEMENTS=$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null || true)
    if echo "$ENTITLEMENTS" | grep -q "com.apple.security"; then
        pass "Entitlements embedded in signature"
    else
        if [ "$IS_DEVID" = true ]; then
            warn "No entitlements found in signature"
        fi
    fi
}

echo "=== MarkView Signing Verification ==="

# Check specified path or defaults
if [ $# -gt 0 ]; then
    verify_app "$1" "specified"
else
    verify_app "$PROJECT_DIR/MarkView.app" "repo"
    verify_app "/Applications/MarkView.app" "installed"
fi

# Summary
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $WARN warnings ==="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Distribution readiness: NOT READY"
    echo "Fix the failures above before releasing."
    exit 1
else
    if [ "$WARN" -gt 0 ]; then
        echo ""
        echo "Distribution readiness: READY (with warnings)"
    else
        echo ""
        echo "Distribution readiness: READY"
    fi
fi
