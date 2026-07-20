#!/usr/bin/env python3
"""
render_verify_gate.py — Warn if template.html or HTMLPipeline.swift was
recently modified but the verify stamp (.last-verify-at) hasn't been
refreshed.

Wired as a PreToolUse Bash hook in .claude/settings.json (not tracked —
private, per-machine dev config).

Reads a Claude Code tool-call JSON payload from stdin; only checks on
`git commit` / `git push` Bash commands. Always exits 0 — this is a
warn-only gate, never a blocking one.

Usage:
    python3 scripts/render_verify_gate.py   (reads hook JSON from stdin)
    bash scripts/render-verify-gate.sh      (thin wrapper)
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

THRESHOLD_SECONDS = 600  # 10 minutes

GIT_COMMIT_OR_PUSH_RE = re.compile(r"^\s*git (commit|push)")

CRITICAL_FILES = (
    "Sources/MarkViewCore/Resources/template.html",
    "Sources/MarkViewCore/HTMLPipeline.swift",
    "Sources/MarkViewCore/MarkdownRenderer.swift",
)

STAMP_TS_RE = re.compile(r"^TS=(\d+)", re.MULTILINE)


def read_payload(stream) -> dict[str, Any]:
    try:
        return json.loads(stream.read())
    except (json.JSONDecodeError, ValueError):
        return {}


def find_repo_root(start: Path) -> Path:
    result = subprocess.run(
        ["git", "-C", str(start), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return Path(result.stdout.strip())
    return Path.cwd()


def is_commit_or_push(command: str) -> bool:
    return bool(GIT_COMMIT_OR_PUSH_RE.match(command))


def _changed_basenames(cwd: Path) -> set[str]:
    """Basenames of files modified (staged or unstaged) relative to HEAD —
    mirrors `git diff --name-only HEAD` + `git diff --cached --name-only`."""
    names: set[str] = set()
    for args in (["diff", "--name-only", "HEAD"], ["diff", "--cached", "--name-only"]):
        result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
        if result.returncode == 0:
            names.update(Path(line).name for line in result.stdout.splitlines() if line)
    return names


def any_critical_file_stale(
    cwd: Path, critical_files: tuple[str, ...] = CRITICAL_FILES
) -> bool:
    """True if any of `critical_files` exists (relative to `cwd`, matching the
    original bash's cwd-relative `[[ -f "$f" ]]` check) AND was recently
    changed (staged or unstaged)."""
    changed = _changed_basenames(cwd)
    for f in critical_files:
        if (cwd / f).is_file() and Path(f).name in changed:
            return True
    return False


def stamp_age_seconds(stamp_path: Path, now: float) -> int | None:
    """Returns the stamp's age in seconds, or None if the stamp is missing
    or unparseable. Supports the HA-008 "TIER=x\\nTS=<epoch>" format, falling
    back to a legacy bare-epoch first line."""
    if not stamp_path.is_file():
        return None
    text = stamp_path.read_text()
    match = STAMP_TS_RE.search(text)
    if match:
        ts = int(match.group(1))
    else:
        first_line = text.splitlines()[0].strip() if text.splitlines() else ""
        if not first_line.isdigit():
            return None
        ts = int(first_line)
    return int(now) - ts


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root = find_repo_root(script_dir)
    stamp_path = repo_root / ".last-verify-at"

    payload = read_payload(sys.stdin)
    command = payload.get("tool_input", {}).get("command", "") or ""

    if not is_commit_or_push(command):
        return 0

    cwd = Path.cwd()
    if not any_critical_file_stale(cwd):
        return 0

    age = stamp_age_seconds(stamp_path, time.time())
    if age is not None and age < THRESHOLD_SECONDS:
        return 0

    print(
        "render-verify: template.html/HTMLPipeline.swift changed. "
        "Run 'make playwright' before committing.",
        file=sys.stderr,
    )
    return 0  # warn only, don't block


if __name__ == "__main__":
    sys.exit(main())
