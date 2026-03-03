#!/usr/bin/env bash
# verify-mcp-docs.sh — Assert MCP setup docs reference the correct Claude Code config file.
#
# Bug class: MCP config file path written from model knowledge, never verified against
# official docs. Wrong path (~/.claude/settings.json) shipped and was caught only by
# an end-user on launch day. This gate makes future regressions a CI failure.
#
# Correct per https://code.claude.com/docs/en/mcp (verified 2026-03-03):
#   User scope:   ~/.claude.json  (not ~/.claude/settings.json)
#   Project scope: .mcp.json      (not .claude/mcp.json)
#   CLI:          claude mcp add --transport stdio --scope user <name> -- <cmd>
#
# Usage: bash scripts/verify-mcp-docs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

check_absent() {
    local file="$1" pattern="$2" reason="$3"
    if grep -qE "$pattern" "$file" 2>/dev/null; then
        echo "  FAIL  [$file] contains '$pattern'"
        echo "        $reason"
        FAIL=$((FAIL + 1))
    else
        PASS=$((PASS + 1))
    fi
}

check_present() {
    local file="$1" pattern="$2" reason="$3"
    if grep -qE "$pattern" "$file" 2>/dev/null; then
        PASS=$((PASS + 1))
    else
        echo "  FAIL  [$file] missing '$pattern'"
        echo "        $reason"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== verify-mcp-docs: checking MCP config file references ==="
echo ""

# README.md
check_absent  "README.md" '~/.claude/settings\.json.*mcpServer|mcpServer.*~/.claude/settings\.json' \
    "settings.json is for permissions only; MCP config belongs in ~/.claude.json"
check_absent  "README.md" '~/.claude/mcp\.json' \
    "~/.claude/mcp.json does not exist; correct path is ~/.claude.json"
check_present "README.md" '~/.claude\.json|claude mcp add' \
    "README must reference ~/.claude.json or claude mcp add for MCP setup"

# npm/README.md (the file npm users see)
check_absent  "npm/README.md" '~/.claude/settings\.json' \
    "npm/README.md: settings.json is for permissions only"
check_absent  "npm/README.md" '~/.claude/mcp\.json' \
    "npm/README.md: ~/.claude/mcp.json does not exist"
check_present "npm/README.md" '~/.claude\.json|claude mcp add' \
    "npm/README.md must reference ~/.claude.json or claude mcp add"

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "FAIL — MCP config file path is wrong in docs."
    echo "Correct path per https://code.claude.com/docs/en/mcp :"
    echo "  User scope:    ~/.claude.json  (not settings.json, not mcp.json)"
    echo "  CLI:           claude mcp add --transport stdio --scope user <name> -- <cmd>"
    exit 1
else
    echo "PASS — MCP config file references are correct."
fi
