#!/bin/bash
set -euo pipefail

# Verify a MarkView release is fully deployed across all distribution channels.
# Usage: bash scripts/verify-release.sh [VERSION]
# If VERSION is omitted, reads from Info.plist.
#
# Checks:
#   1. GitHub release has the expected assets (.zip + .tar.gz)
#   2. npm registry shows the correct version as @latest
#   3. npm postinstall actually works (downloads + extracts binary)
#   4. Homebrew tap cask is at the correct version
#   5. Official MCP registry shows updated version
#   6. check-version-sync.sh passes (all sources in sync)

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve version
if [[ $# -gt 0 ]]; then
    VERSION="$1"
else
    VERSION=$(plutil -extract CFBundleShortVersionString raw \
        "$PROJECT_DIR/Sources/MarkView/Info.plist" 2>/dev/null || echo "")
fi

if [[ -z "$VERSION" ]]; then
    echo "ERROR: Could not determine version. Pass as argument: bash $0 1.2.3"
    exit 1
fi

echo "=== Verifying MarkView v${VERSION} release ==="
echo ""

ERRORS=0
WARNINGS=0

check_pass() { echo "  ✓ $1"; }
check_fail() { echo "  ✗ $1"; ERRORS=$((ERRORS + 1)); }
check_warn() { echo "  ⚠ $1"; WARNINGS=$((WARNINGS + 1)); }

# ─── 1. Version sync ─────────────────────────────────────────────────────────
echo "1. Version sync (check-version-sync.sh)"
if bash "$PROJECT_DIR/scripts/check-version-sync.sh" 2>&1 | grep -q "✓ All versions in sync"; then
    check_pass "All local version sources in sync"
else
    check_fail "Local version sources OUT OF SYNC — run: bash scripts/check-version-sync.sh"
fi
echo ""

# ─── 2. GitHub Release ───────────────────────────────────────────────────────
echo "2. GitHub Release assets"
RELEASE_ASSETS=$(gh release view "v${VERSION}" --repo paulhkang94/markview --json assets \
    --jq '[.assets[] | .name]' 2>/dev/null || echo "[]")

if echo "$RELEASE_ASSETS" | python3 -c "import json,sys; a=json.load(sys.stdin); exit(0 if 'MarkView-${VERSION}.zip' in a else 1)" 2>/dev/null; then
    check_pass "GitHub release has MarkView-${VERSION}.zip"
else
    check_fail "GitHub release MISSING MarkView-${VERSION}.zip"
fi

if echo "$RELEASE_ASSETS" | python3 -c "import json,sys; a=json.load(sys.stdin); exit(0 if 'MarkView-${VERSION}.tar.gz' in a else 1)" 2>/dev/null; then
    check_pass "GitHub release has MarkView-${VERSION}.tar.gz (npm artifact)"
else
    check_fail "GitHub release MISSING MarkView-${VERSION}.tar.gz — npm postinstall will fail"
fi
echo ""

# ─── 3. npm registry ─────────────────────────────────────────────────────────
echo "3. npm registry"
NPM_LATEST=$(npm view mcp-server-markview version 2>/dev/null || echo "ERROR")
if [[ "$NPM_LATEST" == "$VERSION" ]]; then
    check_pass "npm @latest = ${NPM_LATEST}"
else
    check_fail "npm @latest = ${NPM_LATEST} (expected ${VERSION}) — run: cd npm && npm publish --access public"
fi
echo ""

# ─── 4. npm postinstall smoke test ───────────────────────────────────────────
echo "4. npm postinstall smoke test"
_tmp_install="$(mktemp -d)"
if (cd "$_tmp_install" && npm install "mcp-server-markview@${VERSION}" --prefer-offline=false 2>&1 | tail -3) > /dev/null 2>&1; then
    if [[ -f "$_tmp_install/node_modules/mcp-server-markview/bin/markview-mcp-server-binary" ]]; then
        BINARY_SIZE=$(du -sh "$_tmp_install/node_modules/mcp-server-markview/bin/markview-mcp-server-binary" | cut -f1)
        check_pass "npm install succeeds + binary extracted (${BINARY_SIZE})"
    else
        # Binary may come from /Applications fallback — still acceptable
        check_warn "npm install succeeded but binary not in node_modules (falling back to /Applications)"
    fi
else
    check_fail "npm install mcp-server-markview@${VERSION} failed"
fi
rm -rf "$_tmp_install"
echo ""

# ─── 5. Homebrew tap ─────────────────────────────────────────────────────────
echo "5. Homebrew tap"
TAP_VER=$(curl -sf \
    "https://raw.githubusercontent.com/paulhkang94/homebrew-markview/main/Casks/markview.rb" \
    2>/dev/null | grep -oE 'version "[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "ERROR")
if [[ "$TAP_VER" == "$VERSION" ]]; then
    check_pass "Homebrew tap = ${TAP_VER}"
else
    check_warn "Homebrew tap = ${TAP_VER} (expected ${VERSION}) — may not have propagated yet"
fi
echo ""

# ─── 6. Official MCP registry ────────────────────────────────────────────────
echo "6. Official MCP registry"
MCP_ENTRY=$(curl -sf \
    "https://registry.modelcontextprotocol.io/v0/servers?search=io.github.paulhkang94%2Fmarkview" \
    2>/dev/null || echo "")
MCP_STATUS=$(echo "$MCP_ENTRY" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except:
    print('api_error'); sys.exit(0)
for item in data.get('servers', []):
    s = item.get('server', item)  # handle both nested and flat formats
    if s.get('name') == 'io.github.paulhkang94/markview':
        reg_ver = s.get('version', '?')
        print(reg_ver)
        sys.exit(0)
print('not_found')
" 2>/dev/null || echo "api_error")

case "$MCP_STATUS" in
    "${VERSION}")    check_pass "MCP registry = ${MCP_STATUS}" ;;
    "not_found")     check_warn "Not found in MCP registry — publish: cd npm && mcp-publisher publish" ;;
    "api_error")     check_warn "MCP registry API unreachable" ;;
    *)               check_warn "MCP registry = ${MCP_STATUS} (expected ${VERSION}) — update with: cd npm && mcp-publisher publish" ;;
esac
echo ""

# ─── Summary ─────────────────────────────────────────────────────────────────
echo "=== Summary for v${VERSION} ==="
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo "✓ All checks passed — v${VERSION} is fully deployed"
elif [[ $ERRORS -eq 0 ]]; then
    echo "⚠ Passed with ${WARNINGS} warning(s) — typically propagation delay, retry in a few minutes"
else
    echo "✗ ${ERRORS} failure(s), ${WARNINGS} warning(s) — see above for fixes"
    exit 1
fi
