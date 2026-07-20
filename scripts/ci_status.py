#!/usr/bin/env python3
"""
ci_status.py — Check CI status for a PR or the latest push on a branch.

Usage:
    python3 scripts/ci_status.py [PR_NUMBER]
    python3 scripts/ci_status.py          # uses current branch's latest run
    bash scripts/ci-status.sh [PR_NUMBER] # thin wrapper

Outputs a summary line per check, then an overall PASS/FAIL/PENDING verdict.

Exit codes:
    0  all checks succeeded
    1  one or more checks failed
    2  one or more checks still pending
"""

from __future__ import annotations

import json
import subprocess
import sys

REPO = "paulhkang94/markview"


def gh_json(args: list[str]) -> object | None:
    """Run `gh <args...>` and parse stdout as JSON. Returns None on any
    failure (non-zero exit, unparseable output) — never raises, matching
    the original bash's tolerance for a missing/errored `gh` call."""
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def current_branch() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return "main"


def get_checks_for_pr(pr: str, repo: str = REPO) -> list[dict]:
    data = gh_json(["pr", "view", pr, "--repo", repo, "--json", "statusCheckRollup"])
    if not isinstance(data, dict):
        return []
    rollup = data.get("statusCheckRollup")
    return rollup if isinstance(rollup, list) else []


def get_checks_for_branch(branch: str, repo: str = REPO) -> list[dict]:
    runs = gh_json(
        [
            "run",
            "list",
            "--repo",
            repo,
            "--branch",
            branch,
            "--limit",
            "1",
            "--json",
            "databaseId",
        ]
    )
    if not isinstance(runs, list) or not runs:
        return []
    run_id = runs[0].get("databaseId")
    if run_id is None:
        return []
    data = gh_json(["run", "view", str(run_id), "--repo", repo, "--json", "jobs"])
    if not isinstance(data, dict):
        return []
    jobs = data.get("jobs", [])
    return [
        {
            "name": j.get("name"),
            "status": j.get("status"),
            "conclusion": j.get("conclusion"),
        }
        for j in jobs
    ]


def summarize(checks: list[dict]) -> tuple[int, int, int]:
    """Returns (pending_count, failed_count, total_count)."""
    total = len(checks)
    pending = sum(1 for c in checks if c.get("status") != "COMPLETED")
    failed = sum(1 for c in checks if c.get("conclusion") == "FAILURE")
    return pending, failed, total


def format_table(checks: list[dict]) -> str:
    rows = []
    for c in checks:
        label = (c.get("conclusion") or c.get("status") or "").upper()
        rows.append((label, c.get("name", "")))
    rows.sort()
    if not rows:
        return ""
    width = max(len(label) for label, _ in rows) + 2
    return "\n".join(f"{label:<{width}}{name}" for label, name in rows)


def decide_exit_code(pending: int, failed: int) -> int:
    if pending > 0:
        return 2
    if failed > 0:
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv

    if argv and argv[0].isdigit():
        checks = get_checks_for_pr(argv[0])
    else:
        checks = get_checks_for_branch(current_branch())

    if not checks:
        print("No checks found.")
        return 0

    table = format_table(checks)
    if table:
        print(table)
    print()

    pending, failed, total = summarize(checks)

    if pending > 0:
        print(f"PENDING — {pending}/{total} checks still running")
    elif failed > 0:
        print(f"FAILED — {failed}/{total} checks failed")
    else:
        print(f"PASS — all {total} checks succeeded")

    return decide_exit_code(pending, failed)


if __name__ == "__main__":
    sys.exit(main())
