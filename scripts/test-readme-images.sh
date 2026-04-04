#!/usr/bin/env bash
# Test: verify all img src paths in icons/README.md resolve to real files.
# Simulates HTMLPipeline.inlineLocalImages — if this passes, MarkView.app will render them.
set -euo pipefail

README="/Users/pkang/repos/markview/icons/README.md"
BASE_DIR="/Users/pkang/repos/markview/icons"
PASS=0; FAIL=0

log_pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
log_fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "=== README image resolution test ==="
echo "Base dir: $BASE_DIR"
echo ""

# Step 1: generate HTML (raw, no inlining)
HTML=$(swift run --package-path /Users/pkang/repos/markview MarkViewHTMLGen "$README" 2>/dev/null)

# Step 2: extract all src="..." values
SRCS=$(echo "$HTML" | grep -oE 'src="[^"]*\.(png|jpg|jpeg|gif|svg|webp)"' \
       | sed 's/src="//;s/"//' | sort -u)

if [[ -z "$SRCS" ]]; then
    echo "  ✗ No img src paths found in rendered HTML — markdown images not in output"
    FAIL=$((FAIL+1))
else
    echo "Image paths found in HTML:"
    while IFS= read -r src; do
        # Skip data URIs, http, absolute paths (already resolved)
        [[ "$src" == data:* || "$src" == http* || "$src" == /* ]] && continue
        FULL_PATH="$BASE_DIR/$src"
        if [[ -f "$FULL_PATH" ]]; then
            SIZE=$(wc -c < "$FULL_PATH" | tr -d ' ')
            log_pass "$src  ($SIZE bytes)"
        else
            log_fail "$src  → NOT FOUND at $FULL_PATH"
        fi
    done <<< "$SRCS"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
