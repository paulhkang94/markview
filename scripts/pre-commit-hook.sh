#!/usr/bin/env bash
# MarkView pre-commit hook — fast static checks only (~5s)
# SSOT: scripts/pre-commit-hook.sh (tracked). Installed via scripts/install-hooks.sh.
# Full test suite runs in CI. This catches the most common 10-min CI tax mistakes.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

FAIL=0

fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  ✓ $1"; }

echo "=== pre-commit checks ==="

# 1. Version sync across all callsites
if bash scripts/check-version-sync.sh > /dev/null 2>&1; then
    pass "Version sync"
else
    fail "Version out of sync — run: bash scripts/check-version-sync.sh"
fi

# 2. Rule-gate CI patterns still present
if bash scripts/check-rule-gates.sh > /dev/null 2>&1; then
    pass "Rule gates"
else
    fail "Rule gate missing — run: python3 scripts/check-rule-gates.sh"
fi

# 3. MCP config file path correct in docs
if bash scripts/verify-mcp-docs.sh > /dev/null 2>&1; then
    pass "MCP docs"
else
    fail "MCP doc path wrong — run: bash scripts/verify-mcp-docs.sh"
fi

# 4. No private config files staged
STAGED=$(git diff --cached --name-only 2>/dev/null || true)
PRIVATE=$(echo "$STAGED" | grep -E '^\.(claude)/|^hooks/|^scripts/claude-' || true)
if [ -n "$PRIVATE" ]; then
    fail "Private file staged: $PRIVATE"
else
    pass "No private files staged"
fi

# 5. Render-verify gate: verify stamp (.last-verify-at) must be fresh after edits to
#    render-critical files. Single SSOT — same stamp used by make playwright and verify.sh.
RENDER_CRITICAL=$(echo "$STAGED" | grep -cE 'template\.html|HTMLPipeline\.swift|\.min\.js' || true)
if [[ "$RENDER_CRITICAL" -gt 0 ]]; then
    STAMP="$PROJECT_DIR/.last-verify-at"
    if [[ ! -f "$STAMP" ]]; then
        fail "Render-critical file changed. Run: make playwright   (then re-commit)"
    else
        AGE=$(( $(date +%s) - $(cat "$STAMP") ))
        if [[ "$AGE" -gt 600 ]]; then
            fail "Playwright tests stale (${AGE}s ago). Run: make playwright   (then re-commit)"
        else
            pass "Render-verify recent (${AGE}s ago)"
        fi
    fi
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "✗ $FAIL check(s) failed — commit blocked"
    exit 1
fi
echo "✓ All pre-commit checks passed"
