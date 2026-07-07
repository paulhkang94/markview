#!/usr/bin/env python3
"""SubagentStop hook: log subagent completions to metrics JSONL.

Reads the hook event payload as JSON on stdin and appends a single JSONL line
to ``<repo>/.claude/memory/metrics.jsonl``.

v4 schema: universal — auto-detects repo name, ``mkdir -p``, ``is_interrupt``,
``duration_ms``, ``exit_code``. Port of scripts/claude-log-subagent.sh (M7-4);
the bash version required ``jq`` and sourced ``cl-version.sh``. This reads the
version constant from the sibling ``cl-version.sh`` at runtime (same contract as
cl_session_summary.py / claude_build_benchmark.py) and uses the json stdlib, so
there is no external dependency.

Always exits 0: a logging hook must never break the tool it observes. Malformed
stdin, an unwritable metrics file, or any other error degrades to a no-op.
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_SUBAGENT_JSONL_VERSION = 4


def _subagent_jsonl_version() -> int:
    """CL_SUBAGENT_JSONL_VERSION from the sibling cl-version.sh; any failure → 4.

    Mirrors bash: `source "$(dirname "$0")/cl-version.sh" || CL_SUBAGENT_JSONL_VERSION=4`.
    """
    version_file = Path(__file__).resolve().parent / "cl-version.sh"
    try:
        text = version_file.read_text(encoding="utf-8")
    except OSError:
        return DEFAULT_SUBAGENT_JSONL_VERSION
    match = re.search(r"^CL_SUBAGENT_JSONL_VERSION=(\d+)\s*$", text, re.MULTILINE)
    return int(match.group(1)) if match else DEFAULT_SUBAGENT_JSONL_VERSION


def _str_or_unknown(value: object) -> str:
    """jq `(.field // "unknown") | if . == "" then "unknown"` — null/empty → unknown."""
    if value is None or value == "":
        return "unknown"
    return str(value)


def _session_id(payload: dict, repo_root: Path) -> str:
    """Native session_id from stdin, falling back to the .session_id file."""
    sid = payload.get("session_id") or ""
    if not sid:
        sid_file = repo_root / ".claude" / "memory" / ".session_id"
        try:
            sid = sid_file.read_text(encoding="utf-8").strip()
        except OSError:
            sid = ""
    return sid


def _session_metadata(repo_root: Path) -> dict[str, str]:
    """Opt-in (REPL_SESSION_TAGGING=1) user/work_type/feature_id tags."""
    if os.environ.get("REPL_SESSION_TAGGING", "0") != "1":
        return {}
    meta_file = repo_root / ".claude" / "memory" / ".session_metadata.json"
    try:
        meta = json.loads(meta_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(meta, dict):
        return {}
    out: dict[str, str] = {}
    for src, dst in (
        ("user", "user"),
        ("work_type", "work_type"),
        ("feature_id", "feature_id"),
    ):
        val = meta.get(src) or ""
        if val:
            out[dst] = str(val)
    return out


def main() -> int:
    # Opt-out: set REPL_METRICS=0 or REPL_METRICS_SUBAGENTS=0 to disable.
    if (
        os.environ.get("REPL_METRICS", "1") == "0"
        or os.environ.get("REPL_METRICS_SUBAGENTS", "1") == "0"
    ):
        return 0

    repo_root = Path(__file__).resolve().parent.parent
    metrics_file = repo_root / ".claude" / "memory" / "metrics.jsonl"
    repo_name = repo_root.name

    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return 0
    if not isinstance(payload, dict):
        return 0

    record: dict[str, object] = {
        "v": _subagent_jsonl_version(),
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo": repo_name,
        "event": "subagent_stop",
        "agent_type": _str_or_unknown(payload.get("agent_type")),
        "agent_id": _str_or_unknown(payload.get("agent_id")),
        "is_interrupt": payload.get("is_interrupt") or False,
        "duration_ms": payload.get("duration_ms") or 0,
        "exit_code": payload.get("exit_code") or 0,
    }

    sid = _session_id(payload, repo_root)
    if sid:
        record["session"] = sid
    record.update(_session_metadata(repo_root))

    try:
        metrics_file.parent.mkdir(parents=True, exist_ok=True)
        with metrics_file.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, separators=(",", ":")) + "\n")
    except OSError:
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
