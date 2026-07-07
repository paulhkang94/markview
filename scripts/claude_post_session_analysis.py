#!/usr/bin/env python3
"""Stop hook: run post-session pattern analysis.

Fire-and-forget — the session is ending, so there is no output to surface.
Runs claude_pattern_detector.py --draft-patterns and, when it finds new
patterns, stages them to .claude/memory/draft-patterns.md for later review.

Port of scripts/claude-post-session-analysis.sh (M7-4c): the bash version
required jq to read the Stop-hook stdin; this uses the json stdlib. Always
exits 0 — a Stop hook must never fail the session teardown.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# Sessions shorter than this many tool events are not worth analyzing.
MIN_EVENTS = 10
DRAFT_THRESHOLD = 3
# Substrings that mean the detector found nothing worth staging.
_NO_NEW = ("No new failure patterns", "already documented")


def _drain_stdin() -> str:
    """Read the Stop-hook JSON payload, but never block on an interactive tty."""
    if sys.stdin.isatty():
        return ""
    try:
        return sys.stdin.read()
    except OSError:
        return ""


def main() -> int:
    # Opt-out: REPL_METRICS=0 or REPL_PATTERN_DETECTION=0 disables analysis.
    if (
        os.environ.get("REPL_METRICS", "1") == "0"
        or os.environ.get("REPL_PATTERN_DETECTION", "1") == "0"
    ):
        return 0

    repo_root = Path(__file__).resolve().parent.parent
    metrics_file = repo_root / ".claude" / "memory" / "metrics.jsonl"
    draft_file = repo_root / ".claude" / "memory" / "draft-patterns.md"
    detector = repo_root / "scripts" / "claude_pattern_detector.py"

    # Drain stdin (transcript_path is available here but unused, matching the
    # bash original) so the hook pipe closes cleanly.
    raw = _drain_stdin()
    if raw:
        try:
            json.loads(raw)
        except (json.JSONDecodeError, ValueError):
            pass

    # Skip when there is nothing to analyze or the detector is absent.
    try:
        lines = metrics_file.read_text(encoding="utf-8").splitlines()
    except OSError:
        return 0
    if not lines or not detector.is_file():
        return 0

    # Session-length threshold: skip short sessions.
    if len(lines) < MIN_EVENTS:
        return 0

    try:
        result = subprocess.run(
            [
                "python3",
                str(detector),
                "--draft-patterns",
                "--quiet",
                "--threshold",
                str(DRAFT_THRESHOLD),
                str(repo_root),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return 0
    if result.returncode != 0:
        return 0

    draft_output = result.stdout.strip()
    if not draft_output or any(marker in draft_output for marker in _NO_NEW):
        return 0

    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        draft_file.parent.mkdir(parents=True, exist_ok=True)
        draft_file.write_text(
            f"# Draft Patterns (auto-generated {stamp})\n\n"
            f"{draft_output}\n\n"
            "_To disable post-session pattern analysis: export REPL_PATTERN_DETECTION=0_\n",
            encoding="utf-8",
        )
    except OSError:
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
