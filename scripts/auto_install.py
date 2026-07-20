#!/usr/bin/env python3
"""
auto_install.py — Auto-install MarkView.app after a successful git push in this repo.

Wired as a PostToolUse hook (matcher: Bash, async: true) in .claude/settings.json
(not tracked — private, per-machine dev config).

Reads a Claude Code tool-call JSON payload from stdin; only fires when a
`git push` Bash command exited 0.

Usage:
    python3 scripts/auto_install.py   (reads hook JSON from stdin)
    bash scripts/auto-install.sh      (thin wrapper)
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

GIT_PUSH_RE = re.compile(r"^\s*git push")


def should_fire(payload: dict[str, Any]) -> bool:
    """True iff this hook invocation is a successful `git push` Bash call.

    Mirrors the original bash: matches any command starting with "git push"
    (including `git push --tags`, `git push origin main --tags`, etc.) —
    the original comment claimed to exclude `--tags` but the regex never
    did; behavior is preserved exactly, not the comment's description.
    """
    if payload.get("tool_name") != "Bash":
        return False

    tool_response = payload.get("tool_response", {}) or {}
    exit_code = tool_response.get("exit_code", tool_response.get("exitCode", 1))
    if str(exit_code) != "0":
        return False

    command = payload.get("tool_input", {}).get("command", "") or ""
    return bool(GIT_PUSH_RE.match(command))


def read_payload(stream) -> dict[str, Any]:
    try:
        return json.loads(stream.read())
    except (json.JSONDecodeError, ValueError):
        return {}


def find_repo_root(start: Path) -> Path | None:
    result = subprocess.run(
        ["git", "-C", str(start), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return Path(result.stdout.strip())


def launch_install(repo_root: Path) -> None:
    """Kick off `bash scripts/bundle.sh --install` in the background (fire
    and forget, like the original `& disown`), logging to
    .claude/memory/auto-install.log, then reload the Dock so a freshly
    installed icon appears immediately."""
    log_dir = repo_root / ".claude" / "memory"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "auto-install.log"

    print("[auto-install] git push detected — rebuilding MarkView.app", file=sys.stderr)

    with log_path.open("a") as log_file:
        subprocess.Popen(
            ["bash", "scripts/bundle.sh", "--install"],
            cwd=repo_root,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

    # Reload Dock so the new icon appears immediately — no sudo needed.
    subprocess.run(["killall", "Dock"], capture_output=True)

    print(
        "[auto-install] build started in background (tail .claude/memory/auto-install.log)",
        file=sys.stderr,
    )


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root = find_repo_root(script_dir)
    if repo_root is None:
        return 0

    payload = read_payload(sys.stdin)
    if not should_fire(payload):
        return 0

    launch_install(repo_root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
