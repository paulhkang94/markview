#!/usr/bin/env bash
# Generate self-contained HTML fixtures for Playwright tests.
# Each fixture is assembled HTML: template + rendered markdown + inline JS (Prism/Mermaid/KaTeX).
#
# Usage:
#   bash scripts/gen-playwright-fixtures.sh           # build if needed, then generate
#   bash scripts/gen-playwright-fixtures.sh --no-build # skip swift build (binary must exist)
#
# Fixtures are committed to Tests/playwright/fixtures/ so CI runs Playwright without Swift.
# Regenerate whenever: template.html, HTMLPipeline.swift, or *.min.js changes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_MD="$REPO_ROOT/Tests/TestRunner/Fixtures"
FIXTURES_HTML="$REPO_ROOT/Tests/playwright/fixtures"
GEN_BIN="$REPO_ROOT/.build/release/MarkViewHTMLGen"

mkdir -p "$FIXTURES_HTML"

# Build the generator unless --no-build passed
if [[ "${1:-}" != "--no-build" ]]; then
    echo "Building MarkViewHTMLGen..."
    swift build -c release --product MarkViewHTMLGen 2>&1
fi

if [[ ! -f "$GEN_BIN" ]]; then
    echo "ERROR: $GEN_BIN not found. Run without --no-build." >&2
    exit 1
fi

generate() {
    local src="$1"
    local name="$2"
    echo "  → $name.html"
    "$GEN_BIN" "$src" "$FIXTURES_HTML/$name.html"
    # Sanity check: assembled HTML with inline JS should be >100KB
    local size
    size=$(wc -c < "$FIXTURES_HTML/$name.html")
    if [[ "$size" -lt 100000 ]]; then
        echo "  WARNING: $name.html is only ${size} bytes — JS bundles may not have been inlined" >&2
    fi
}

echo "Generating Playwright HTML fixtures..."

# Use existing test fixtures — no separate playwright/ fixtures needed
generate "$FIXTURES_MD/gfm-alerts.md"    "alerts"
generate "$FIXTURES_MD/mermaid.md"       "mermaid"
generate "$FIXTURES_MD/math.md"          "math"
generate "$FIXTURES_MD/code-blocks.md"   "code-blocks"
generate "$FIXTURES_MD/golden-corpus.md" "golden-corpus"
generate "$FIXTURES_MD/diff.md"          "diff"

COUNT=$(ls "$FIXTURES_HTML"/*.html 2>/dev/null | wc -l | tr -d ' ')
echo "Generated $COUNT fixtures in $FIXTURES_HTML"

# Stamp generation time for commit-gate freshness check
date +%s > "$FIXTURES_HTML/.generated-at"
echo "Done."
