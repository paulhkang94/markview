#!/usr/bin/env bash
# Auto-install MarkView.app after a successful git push in this repo.
# Wired as a PostToolUse hook (matcher: Bash, async: true).
# Reads tool JSON from stdin; only fires when `git push` exited 0.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || exit 0

# Parse stdin JSON — requires python3 (always available on macOS)
INPUT="$(cat)"

# Only fire on successful Bash tool calls
tool_name=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null) || exit 0
[[ "$tool_name" == "Bash" ]] || exit 0

exit_code=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_response',{}).get('exit_code', d.get('tool_response',{}).get('exitCode', 1)))" 2>/dev/null) || exit 0
[[ "$exit_code" == "0" ]] || exit 0

command=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null) || exit 0

# Only trigger on git push (not git push --tags, not git push to other repos)
if ! echo "$command" | grep -qE '^\s*git push'; then
    exit 0
fi

# Run bundle + install in background so the hook returns immediately
cd "$REPO_ROOT"
echo "[auto-install] git push detected — rebuilding MarkView.app" >&2
bash scripts/bundle.sh --install >> .claude/memory/auto-install.log 2>&1 &
disown

# Reload Dock so the new icon appears immediately — no sudo needed.
# (The system-wide /private/var/folders cache clear requires sudo and can't
# run in an async hook context. killall Dock is sufficient for app installs.)
killall Dock 2>/dev/null || true

echo "[auto-install] build started in background (tail .claude/memory/auto-install.log)" >&2
