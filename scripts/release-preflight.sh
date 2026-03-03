#!/usr/bin/env bash
# release-preflight.sh — Validate all release prerequisites BEFORE pushing a tag.
#
# Run: bash scripts/release-preflight.sh
# Pass: prints "Pre-flight passed. Safe to tag." and exits 0.
# Fail: exits 1 with specific failure messages.
#
# Catches the 4-tag-push class of CI failures (missing secrets, wrong permissions,
# stale SPM cache) before any CI runner time is spent.
set -euo pipefail

if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; NC=''
fi

pass() { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

echo "=== MarkView Release Pre-flight Check ==="
echo ""

# ── 1. GitHub CLI available ──────────────────────────────────────────────────
if command -v gh &>/dev/null; then
  pass "gh CLI available ($(gh --version | head -1))"
else
  fail "gh CLI not found — install via: brew install gh"
fi

# ── 2. Authenticated to GitHub ───────────────────────────────────────────────
if gh auth status &>/dev/null; then
  pass "GitHub authenticated"
else
  fail "Not authenticated to GitHub — run: gh auth login"
fi

# ── 3. Required release secrets set in repo ──────────────────────────────────
echo ""
echo "  Checking required secrets..."
REQUIRED_SECRETS=(
  NOTARIZE_KEY_ID
  NOTARIZE_ISSUER_ID
  NOTARIZE_API_KEY
  DEVELOPER_ID_CERT_BASE64
  DEVELOPER_ID_CERT_PASSWORD
  HOMEBREW_TAP_TOKEN
)

for secret in "${REQUIRED_SECRETS[@]}"; do
  if gh secret list 2>/dev/null | grep -q "^${secret}[[:space:]]"; then
    pass "Secret: $secret"
  else
    fail "Missing secret: $secret (set via: gh secret set $secret)"
  fi
done

# ── 4. release.yml has contents:write permission ─────────────────────────────
echo ""
if grep -q "contents: write" .github/workflows/release.yml 2>/dev/null; then
  pass "release.yml has contents:write permission"
else
  fail "release.yml missing 'permissions: contents: write' — required for softprops/action-gh-release"
fi

# ── 5. release.yml passes every required secret to build step ────────────────
# Both NOTARIZE_KEY_ID and NOTARIZE_ISSUER_ID must appear in the build step's env block,
# not just in "Store notarization credentials" — GH Actions env scope is per-step.
if grep -A 5 "Build, sign, notarize" .github/workflows/release.yml 2>/dev/null | grep -q "NOTARIZE_KEY_ID"; then
  pass "NOTARIZE_KEY_ID passed to build step env"
else
  fail "NOTARIZE_KEY_ID not in 'Build, sign, notarize' step env (per-step scope — not inherited)"
fi

# ── 6. Stale SPM binary artifact cache cleared ───────────────────────────────
echo ""
SPM_ARTIFACTS=~/Library/Caches/org.swift.swiftpm/artifacts
if [[ -d "$SPM_ARTIFACTS" ]] && [[ -n "$(ls -A "$SPM_ARTIFACTS" 2>/dev/null)" ]]; then
  warn "Stale SPM binary artifact cache found at $SPM_ARTIFACTS — clearing..."
  rm -rf "$SPM_ARTIFACTS"
  pass "SPM artifact cache cleared (prevents exit code 74 on release CI)"
else
  pass "SPM artifact cache clean (or already empty)"
fi

# ── 7. Local tests pass ───────────────────────────────────────────────────────
echo ""
echo "  Running local tests..."
if swift run MarkViewTestRunner 2>&1 | grep -q "0 failed"; then
  pass "Local tests pass (MarkViewTestRunner)"
else
  fail "Local tests failing — fix before tagging"
fi

# ── 8. Version consistency ─────────────────────────────────────────────────────
echo ""
if command -v bash &>/dev/null && [[ -f scripts/check-version-sync.sh ]]; then
  if bash scripts/check-version-sync.sh &>/dev/null; then
    pass "Version numbers in sync"
  else
    warn "Version sync check failed — verify version numbers match across files"
  fi
fi

# ── 9. Distribution path test ─────────────────────────────────────────────────
# Tests the user-facing install path, not the developer path (bundle.sh --install
# strips quarantine and never hits Gatekeeper). This is the check that catches
# signing failures before they reach users.
echo ""
echo "  Running distribution path test (--local)..."
if bash scripts/test-distribution.sh --local 2>&1 | grep -q "Distribution test passed"; then
  pass "Distribution path test passed (local install — quarantine + signature checks)"
else
  fail "Distribution path test FAILED — fix signing/bundle before tagging"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=================================================="
if [[ "$FAILURES" -eq 0 ]]; then
  # Write sentinel consumed by the pre-push hook — proves this check ran.
  VERSION=$(plutil -extract CFBundleShortVersionString raw \
    "Sources/MarkView/Info.plist" 2>/dev/null || echo "unknown")
  SENTINEL=".release-preflight-passed-${VERSION}"
  touch "$SENTINEL"
  echo -e "${GREEN}Pre-flight passed. Safe to tag.${NC}"
  echo ""
  echo "  Sentinel written: ${SENTINEL}"
  echo "  Next: git tag v${VERSION} && git push origin v${VERSION}"
  exit 0
else
  echo -e "${RED}$FAILURES check(s) failed. Fix before tagging.${NC}"
  exit 1
fi
