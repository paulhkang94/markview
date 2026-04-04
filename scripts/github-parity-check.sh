#!/usr/bin/env bash
# GitHub Parity Check — structural comparison of MarkView vs GitHub rendering.
#
# Uses the GitHub Markdown API to render golden-corpus.md and compares the
# heading/table/code structure against MarkView's output.
#
# Run before major releases. Not in CI (requires GitHub API, rate-limited).
# Auth recommended: GITHUB_TOKEN env var for higher rate limits.
#
# Usage:
#   bash scripts/github-parity-check.sh
#   GITHUB_TOKEN=ghp_xxx bash scripts/github-parity-check.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORPUS="$REPO_ROOT/Tests/TestRunner/Fixtures/golden-corpus.md"
GEN_BIN="$REPO_ROOT/.build/release/MarkViewHTMLGen"
TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

echo "=== MarkView vs GitHub Parity Check ==="
echo "Corpus: $CORPUS"
echo ""

# Build MarkViewHTMLGen if needed
if [[ ! -f "$GEN_BIN" ]]; then
    echo "Building MarkViewHTMLGen..."
    swift build -c release --product MarkViewHTMLGen 2>&1
fi

# --- Step 1: Render via GitHub Markdown API ---
echo "Fetching GitHub rendering..."
AUTH_HEADER=""
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    AUTH_HEADER="-H \"Authorization: Bearer $GITHUB_TOKEN\""
fi

GITHUB_HTML=$(curl -s -X POST "https://api.github.com/markdown" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    --data-binary "{\"text\": $(jq -Rs . < "$CORPUS"), \"mode\": \"gfm\"}") || {
    echo "ERROR: GitHub API request failed" >&2
    exit 1
}

if echo "$GITHUB_HTML" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null | grep -q "rate limit\|API rate"; then
    echo "ERROR: GitHub API rate limited. Set GITHUB_TOKEN for higher limits." >&2
    exit 1
fi

echo "$GITHUB_HTML" > "$TMPDIR_LOCAL/github.html"

# --- Step 2: Render via MarkView ---
echo "Rendering via MarkView..."
MARKVIEW_HTML=$("$GEN_BIN" "$CORPUS")
echo "$MARKVIEW_HTML" > "$TMPDIR_LOCAL/markview.html"

# --- Step 3: Structural comparison ---
echo ""
echo "--- Heading structure ---"
GH_HEADINGS=$(echo "$GITHUB_HTML" | grep -oE '<h[1-6][^>]*>' | grep -oE 'h[1-6]' | sort | uniq -c | sort -rn)
MV_HEADINGS=$(echo "$MARKVIEW_HTML" | grep -oE '<h[1-6][^>]*>' | grep -oE 'h[1-6]' | sort | uniq -c | sort -rn)
echo "GitHub:  $GH_HEADINGS"
echo "MarkView: $MV_HEADINGS"
if [[ "$GH_HEADINGS" == "$MV_HEADINGS" ]]; then
    echo "✅ Headings match"
else
    echo "⚠️  Heading counts differ"
    diff <(echo "$GH_HEADINGS") <(echo "$MV_HEADINGS") || true
fi

echo ""
echo "--- Table structure ---"
GH_TABLES=$(echo "$GITHUB_HTML" | grep -cE '<table' || echo 0)
MV_TABLES=$(echo "$MARKVIEW_HTML" | grep -cE '<table' || echo 0)
echo "GitHub tables:   $GH_TABLES"
echo "MarkView tables: $MV_TABLES"
[[ "$GH_TABLES" == "$MV_TABLES" ]] && echo "✅ Table counts match" || echo "⚠️  Table counts differ"

echo ""
echo "--- Code block languages ---"
GH_LANGS=$(echo "$GITHUB_HTML" | grep -oE 'class="language-[a-z]+"' | sort | uniq -c | sort -rn)
MV_LANGS=$(echo "$MARKVIEW_HTML" | grep -oE 'class="language-[a-z]+"' | sort | uniq -c | sort -rn)
echo "GitHub:   $GH_LANGS"
echo "MarkView: $MV_LANGS"

echo ""
echo "--- Task lists ---"
GH_TASKS=$(echo "$GITHUB_HTML" | grep -cE '<li class="task-list-item' || echo 0)
MV_TASKS=$(echo "$MARKVIEW_HTML" | grep -cE 'type="checkbox"' || echo 0)
echo "GitHub task items:   $GH_TASKS"
echo "MarkView checkboxes: $MV_TASKS"

echo ""
echo "=== Parity check complete ==="
echo "Full output saved to: $TMPDIR_LOCAL/"
echo "Note: Differences in alert/TOC/KaTeX/Mermaid are expected (MarkView extensions)."
