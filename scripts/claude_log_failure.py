#!/usr/bin/env python3
"""PostToolUseFailure hook: log tool failures to metrics JSONL.

Reads the hook event payload as JSON on stdin and does three things, in order:

1. Appends a single v3 ``tool_failure`` JSONL line to
   ``<repo>/.claude/memory/metrics.jsonl``.
2. Pattern detection: if this error's 80-char signature recurs >= 2 times in the
   last 10 metrics events, emits a single ``{"additionalContext": ...}`` JSON
   object on stdout. Claude Code parses hook stdout as JSON — a malformed line
   silently drops the hook (the S86 incident class), so the object is built with
   json.dumps, never string interpolation.
3. CL fingerprint auto-extraction: hands (tool, error, command) to
   ``cl_db.py auto-extract`` (skips interrupts).

Port of scripts/claude-log-failure.sh (M7-4b): the bash version required ``jq``
and sourced ``cl-version.sh``. This reads the version constant from the sibling
``cl-version.sh`` at runtime and uses the json stdlib, so there is no external
dependency. Always exits 0 — a logging hook must never break the tool it
observes; malformed stdin or an unwritable metrics file degrades to a no-op.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_JSONL_VERSION = 3


def _jsonl_version() -> int:
    """CL_JSONL_VERSION from the sibling cl-version.sh; any failure → 3.

    Mirrors bash: `source "$(dirname "$0")/cl-version.sh" || CL_JSONL_VERSION=3`.
    """
    version_file = Path(__file__).resolve().parent / "cl-version.sh"
    try:
        text = version_file.read_text(encoding="utf-8")
    except OSError:
        return DEFAULT_JSONL_VERSION
    match = re.search(r"^CL_JSONL_VERSION=(\d+)\s*$", text, re.MULTILINE)
    return int(match.group(1)) if match else DEFAULT_JSONL_VERSION


def _jq_alt(*candidates: object, default: str) -> object:
    """jq `a // b // default` — first value that is neither null nor false.

    Note: jq's `//` does NOT treat "" as empty, so an empty string short-circuits
    the chain (the caller applies the separate `if . == ""` → default step).
    """
    for value in candidates:
        if value is not None and value is not False:
            return value
    return default


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
    for key in ("user", "work_type", "feature_id"):
        val = meta.get(key) or ""
        if val:
            out[key] = str(val)
    return out


def _build_record(payload: dict, repo_root: Path, repo_name: str) -> dict:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        tool_input = {}

    # file: file_path first, then command (jq `//`), empty → unknown, cap 200.
    file_val = _jq_alt(tool_input.get("file_path"), tool_input.get("command"), default="unknown")
    if file_val == "":
        file_val = "unknown"
    file_val = str(file_val)[:200]

    record: dict[str, object] = {
        "v": _jsonl_version(),
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo": repo_name,
        "event": "tool_failure",
        "tool": _str_or_unknown(payload.get("tool_name")),
        "file": file_val,
        "error": _str_or_unknown(payload.get("error"))[:500],
        "is_interrupt": payload.get("is_interrupt") or False,
    }

    sid = _session_id(payload, repo_root)
    if sid:
        record["session"] = sid
    record.update(_session_metadata(repo_root))
    return record


def _emit_pattern_context(payload: dict, metrics_file: Path) -> None:
    """Emit additionalContext if this error's signature recurs in recent events."""
    if os.environ.get("REPL_PATTERN_DETECTION", "1") == "0":
        return
    sig = str(_jq_alt(payload.get("error"), default=""))[:80]
    if not sig or sig == "null":
        return
    try:
        lines = metrics_file.read_text(encoding="utf-8").splitlines()
    except OSError:
        return
    count = 0
    for line in lines[-10:]:
        try:
            rec = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if rec.get("event") == "tool_failure" and str(rec.get("error") or "")[:80] == sig:
            count += 1
    if count >= 2:
        msg = (
            f"This error has occurred {count} times recently. Check "
            ".claude/memory/failure-patterns.md for known fixes, or run "
            "python3 scripts/claude_pattern_detector.py --analyze . for full analysis."
        )
        # json.dumps guarantees a valid object — Claude Code parses this as JSON.
        print(json.dumps({"additionalContext": msg}))


def _auto_extract(payload: dict, repo_root: Path) -> None:
    """Feed (tool, error, command) to cl_db.py auto-extract (skips interrupts)."""
    if os.environ.get("REPL_FINGERPRINTING", "1") == "0":
        return
    db_path = repo_root / ".claude" / "memory" / "learnings.db"
    cl_db_py = repo_root / "scripts" / "cl_db.py"
    if not cl_db_py.is_file():
        cl_db_py = Path(__file__).resolve().parent / "cl_db.py"
    if not db_path.is_file() or not cl_db_py.is_file():
        return
    if payload.get("is_interrupt") is True:
        return

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        tool_input = {}
    fp_tool = str(_jq_alt(payload.get("tool_name"), default=""))
    fp_error = str(_jq_alt(payload.get("error"), default=""))[:200]
    fp_cmd = str(_jq_alt(tool_input.get("command"), tool_input.get("file_path"), default=""))[:200]

    if not fp_error or fp_error == "null":
        return

    try:
        subprocess.run(
            ["python3", str(cl_db_py), "auto-extract", fp_tool, fp_error, fp_cmd],
            env={**os.environ, "CL_DB_PATH": str(db_path)},
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        return


def main() -> int:
    # Opt-out: set REPL_METRICS=0 or REPL_METRICS_TOOL_FAILURES=0 to disable.
    if (
        os.environ.get("REPL_METRICS", "1") == "0"
        or os.environ.get("REPL_METRICS_TOOL_FAILURES", "1") == "0"
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

    record = _build_record(payload, repo_root, repo_name)

    try:
        metrics_file.parent.mkdir(parents=True, exist_ok=True)
        with metrics_file.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, separators=(",", ":")) + "\n")
    except OSError:
        return 0

    _emit_pattern_context(payload, metrics_file)
    _auto_extract(payload, repo_root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
