#!/usr/bin/env bash
# Warn if template.html or HTMLPipeline.swift was recently modified but
# render-verify stamp (.last-render-verify-at) hasn't been refreshed.
# Wired as a PreToolUse Bash hook in .claude/settings.json.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || pwd)"
STAMP="$REPO_ROOT/.last-render-verify-at"
THRESHOLD=600  # 10 minutes

# Read the stdin JSON to check if this is a git commit command
INPUT="$(cat)"
command=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null) || exit 0

# Only warn on git commit commands
if ! echo "$command" | grep -qE '^\s*git (commit|push)'; then
    exit 0
fi

# Check if render-critical files were recently modified
CRITICAL_FILES=(
    "Sources/MarkViewCore/Resources/template.html"
    "Sources/MarkViewCore/HTMLPipeline.swift"
    "Sources/MarkViewCore/MarkdownRenderer.swift"
)

STALE=0
for f in "${CRITICAL_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        # Check if file is modified (staged or unstaged)
        if git diff --name-only HEAD 2>/dev/null | grep -q "$(basename $f)" || \
           git diff --cached --name-only 2>/dev/null | grep -q "$(basename $f)"; then
            STALE=1
            break
        fi
    fi
done

[[ $STALE -eq 0 ]] && exit 0

# Check stamp freshness
if [[ -f "$STAMP" ]]; then
    stamp_age=$(( $(date +%s) - $(cat "$STAMP") ))
    [[ $stamp_age -lt $THRESHOLD ]] && exit 0
fi

echo "render-verify: template.html/HTMLPipeline.swift changed. Run 'make playwright' before committing." >&2
exit 0  # warn only, don't block
