#!/usr/bin/env python3
"""
MarkView traction checker — quick snapshot before/after launch posts.

Usage:
    python3 scripts/check_traction.py [--json]
    bash scripts/check-traction.sh [--json]   (thin wrapper)
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone


# ── Constants ─────────────────────────────────────────────────────────────────

REPO = "paulhkang94/markview"


# ── GitHub API helper ─────────────────────────────────────────────────────────


def gh_api(path: str) -> dict | list | None:
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


# ── Data collection ───────────────────────────────────────────────────────────


def collect() -> dict:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    repo = gh_api(f"repos/{REPO}") or {}
    clones = gh_api(f"repos/{REPO}/traffic/clones") or {}
    views = gh_api(f"repos/{REPO}/traffic/views") or {}
    referrers = gh_api(f"repos/{REPO}/traffic/popular/referrers") or []
    releases_raw = gh_api(f"repos/{REPO}/releases") or []

    releases = [
        {
            "tag": r.get("tag_name"),
            "downloads": sum(a.get("download_count", 0) for a in r.get("assets", [])),
        }
        for r in releases_raw
    ]

    return {
        "timestamp": ts,
        "stars": repo.get("stargazers_count", "?"),
        "forks": repo.get("forks_count", "?"),
        "watchers": repo.get("subscribers_count", "?"),
        "open_issues": repo.get("open_issues_count", "?"),
        "clones_14d": {
            "total": clones.get("count", "?"),
            "unique": clones.get("uniques", "?"),
        },
        "views_14d": {
            "total": views.get("count", "?"),
            "unique": views.get("uniques", "?"),
        },
        "top_referrers": [
            {
                "referrer": r.get("referrer"),
                "count": r.get("count"),
                "uniques": r.get("uniques"),
            }
            for r in referrers
        ],
        "releases": releases,
    }


# ── Output ────────────────────────────────────────────────────────────────────


def print_human(data: dict) -> None:
    print(f"=== MarkView Traction — {data['timestamp']} ===")
    print()
    print(
        f"  Stars: {data['stars']:<6}  Forks: {data['forks']:<6}"
        f"  Watchers: {data['watchers']:<6}  Issues: {data['open_issues']}"
    )
    print()

    c = data["clones_14d"]
    v = data["views_14d"]
    print(f"  Clones (14d): {c['total']} total, {c['unique']} unique")
    print(f"  Views  (14d): {v['total']} total, {v['unique']} unique")
    print()

    print("  Top referrers:")
    if data["top_referrers"]:
        for r in data["top_referrers"]:
            print(f"    {r['referrer']}: {r['count']} ({r['uniques']} unique)")
    else:
        print("    (none)")
    print()

    print("  Release downloads:")
    if data["releases"]:
        for r in data["releases"]:
            print(f"    {r['tag']}: {r['downloads']} downloads")
    else:
        print("    (none)")


# ── Main ──────────────────────────────────────────────────────────────────────


def main() -> None:
    json_mode = "--json" in sys.argv

    data = collect()

    if json_mode:
        print(json.dumps(data, indent=2))
    else:
        print_human(data)


if __name__ == "__main__":
    main()
