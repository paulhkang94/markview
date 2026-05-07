#!/usr/bin/env python3
"""
MarkView unified metrics tracker.

Pulls npm, GitHub traffic, release downloads, and MCP registry data.
Saves a JSONL snapshot and prints a formatted report with diff vs previous.

Usage:
    python3 scripts/metrics.py
    bash scripts/metrics.sh   (thin wrapper)
"""

from __future__ import annotations

import json
import subprocess
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

# ── Constants ─────────────────────────────────────────────────────────────────

REPO = "paulhkang94/markview"
NPM_PKG = "mcp-server-markview"
MCP_SERVER_ID = "io.github.paulhkang94%2Fmarkview"
REPO_ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT_FILE = REPO_ROOT / ".claude" / "memory" / "traction-snapshots.jsonl"

# ── HTTP helpers ──────────────────────────────────────────────────────────────


def fetch_json(url: str) -> dict | list | None:
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": "markview-metrics/1.0"}
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except Exception:
        return None


def gh_api(path: str) -> dict | list | None:
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


# ── Data collection ───────────────────────────────────────────────────────────


def get_github_stats() -> dict:
    print("Fetching GitHub repo stats...", file=sys.stderr)
    data = gh_api(f"repos/{REPO}") or {}
    return {
        "stars": data.get("stargazers_count", "?"),
        "forks": data.get("forks_count", "?"),
        "watchers": data.get("subscribers_count", "?"),
        "open_issues": data.get("open_issues_count", "?"),
    }


def get_github_traffic() -> dict:
    print("Fetching GitHub traffic...", file=sys.stderr)
    clones = gh_api(f"repos/{REPO}/traffic/clones") or {}
    views = gh_api(f"repos/{REPO}/traffic/views") or {}
    print("Fetching top referrers...", file=sys.stderr)
    referrers = gh_api(f"repos/{REPO}/traffic/popular/referrers") or []
    print("Fetching popular paths...", file=sys.stderr)
    popular_paths = gh_api(f"repos/{REPO}/traffic/popular/paths") or []
    return {
        "clones": {
            "total": clones.get("count", "?"),
            "unique": clones.get("uniques", "?"),
        },
        "views": {
            "total": views.get("count", "?"),
            "unique": views.get("uniques", "?"),
        },
        "referrers": [
            {
                "referrer": r.get("referrer"),
                "count": r.get("count"),
                "uniques": r.get("uniques"),
            }
            for r in referrers
        ],
        "popular_paths": [
            {
                "path": p.get("path"),
                "count": p.get("count"),
                "uniques": p.get("uniques"),
            }
            for p in popular_paths
        ],
    }


def get_github_releases() -> list:
    print("Fetching release download counts...", file=sys.stderr)
    releases = gh_api(f"repos/{REPO}/releases") or []
    return [
        {
            "tag_name": r.get("tag_name"),
            "published_at": r.get("published_at", "")[:10],
            "downloads": sum(a.get("download_count", 0) for a in r.get("assets", [])),
        }
        for r in releases
    ]


def get_npm_downloads() -> dict:
    print("Fetching npm download stats...", file=sys.stderr)
    week = fetch_json(f"https://api.npmjs.org/downloads/point/last-week/{NPM_PKG}")
    month = fetch_json(f"https://api.npmjs.org/downloads/point/last-month/{NPM_PKG}")
    daily_data = fetch_json(
        f"https://api.npmjs.org/downloads/range/last-14-days/{NPM_PKG}"
    )
    return {
        "downloads_7d": (week or {}).get("downloads", 0),
        "downloads_30d": (month or {}).get("downloads", 0),
        "daily_last_14d": (daily_data or {}).get("downloads", []),
    }


def get_npm_publish_history(limit: int = 5) -> list:
    print("Fetching npm publish history...", file=sys.stderr)
    data = fetch_json(f"https://registry.npmjs.org/{NPM_PKG}")
    if not data:
        return []
    time_data = data.get("time", {})
    versions = [
        {"version": v, "published": time_data.get(v, "")}
        for v in data.get("versions", {}).keys()
    ]
    versions.sort(key=lambda x: x["published"], reverse=True)
    return versions[:limit]


def get_mcp_info() -> dict:
    print("Fetching MCP registry data...", file=sys.stderr)
    data = fetch_json(
        f"https://registry.modelcontextprotocol.io/v0.1/servers/{MCP_SERVER_ID}/versions"
    )
    if not data:
        return {"active_versions": 0, "latest_published": "unknown"}
    active = [v for v in data.get("versions", []) if v.get("status") == "active"]
    dates = [v.get("published_date") for v in active if v.get("published_date")]
    return {
        "active_versions": len(active),
        "latest_published": max(dates) if dates else "unknown",
    }


# ── Snapshot I/O ──────────────────────────────────────────────────────────────


def load_previous_snapshot() -> dict | None:
    if not SNAPSHOT_FILE.exists():
        return None
    lines = SNAPSHOT_FILE.read_text().splitlines()
    # Second-to-last line is the previous snapshot (last is the one we just wrote)
    for line in reversed(lines[:-1]):
        line = line.strip()
        if line:
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    return None


def save_snapshot(snapshot: dict) -> None:
    SNAPSHOT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with SNAPSHOT_FILE.open("a") as f:
        f.write(json.dumps(snapshot, separators=(",", ":")) + "\n")


# ── Output helpers ────────────────────────────────────────────────────────────


def _bar(downloads: int, max_width: int = 50) -> str:
    width = min(max(downloads // 2, 0), max_width)
    return "█" * width


def print_report(
    stats: dict,
    traffic: dict,
    releases: list,
    npm: dict,
    npm_history: list,
    mcp: dict,
) -> None:
    print()
    print("GitHub Stats:")
    print(
        f"  Stars: {stats['stars']:<6}  Forks: {stats['forks']:<6}"
        f"  Watchers: {stats['watchers']:<6}  Open Issues: {stats['open_issues']}"
    )
    print()

    print("GitHub Traffic (14d):")
    c = traffic["clones"]
    v = traffic["views"]
    print(f"  Clones: {c['total']} total, {c['unique']} unique")
    print(f"  Views:  {v['total']} total, {v['unique']} unique")
    print()

    print("NPM Downloads:")
    print(f"  Last 7 days:  {npm['downloads_7d']}")
    print(f"  Last 30 days: {npm['downloads_30d']}")
    print()

    print("NPM Daily Downloads (last 14 days):")
    for entry in npm["daily_last_14d"]:
        day = entry.get("day", "")
        dl = entry.get("downloads", 0)
        print(f"  {day}: {_bar(dl)} {dl}")
    print()

    print("Top Referrers:")
    if traffic["referrers"]:
        for r in traffic["referrers"]:
            print(f"  {r['referrer']}: {r['count']} ({r['uniques']} unique)")
    else:
        print("  (none)")
    print()

    print("Popular Paths:")
    for p in traffic["popular_paths"][:5]:
        print(f"  {p['path']}: {p['count']} ({p['uniques']} unique)")
    if not traffic["popular_paths"]:
        print("  (none)")
    print()

    print("Top Release Downloads:")
    for r in releases[:5]:
        print(
            f"  {r['tag_name']}: {r['downloads']} downloads (published {r['published_at']})"
        )
    if not releases:
        print("  (none)")
    print()

    print("NPM Publish History (last 5 versions):")
    for v in npm_history:
        pub = v.get("published", "")[:10]
        print(f"  {v['version']}: {pub}")
    if not npm_history:
        print("  (none)")
    print()

    print("MCP Registry:")
    print(f"  Active versions: {mcp['active_versions']}")
    print(f"  Latest published: {mcp['latest_published']}")
    print()


def print_diff(prev: dict, curr: dict) -> None:
    print("=== Notable Changes Since Last Snapshot ===")
    print()

    def _int(d: dict, *keys: str) -> int:
        val = d
        for k in keys:
            val = val.get(k, 0) if isinstance(val, dict) else 0
        return int(val) if str(val).lstrip("-").isdigit() else 0

    deltas = {
        "⭐  Stars": (
            _int(prev, "github", "stars"),
            _int(curr, "github", "stars"),
        ),
        "📦 NPM 7d": (
            _int(prev, "npm", "downloads_7d"),
            _int(curr, "npm", "downloads_7d"),
        ),
        "📥 Clones": (
            _int(prev, "github", "traffic_14d", "clones", "total"),
            _int(curr, "github", "traffic_14d", "clones", "total"),
        ),
        "👁  Views": (
            _int(prev, "github", "traffic_14d", "views", "total"),
            _int(curr, "github", "traffic_14d", "views", "total"),
        ),
    }

    any_change = False
    for label, (p, c) in deltas.items():
        delta = c - p
        if delta != 0:
            print(f"  {label}: {delta:+d} (now {c})")
            any_change = True

    if not any_change:
        print("  (no significant changes)")
    print()


# ── Main ──────────────────────────────────────────────────────────────────────


def main() -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"=== MarkView Metrics Snapshot — {ts} ===", file=sys.stderr)
    print(file=sys.stderr)

    stats = get_github_stats()
    traffic = get_github_traffic()
    releases = get_github_releases()
    npm = get_npm_downloads()
    npm_history = get_npm_publish_history()
    mcp = get_mcp_info()

    snapshot = {
        "timestamp": ts,
        "github": {
            "stars": stats["stars"],
            "forks": stats["forks"],
            "watchers": stats["watchers"],
            "open_issues": stats["open_issues"],
            "traffic_14d": {
                "clones": traffic["clones"],
                "views": traffic["views"],
            },
            "referrers": traffic["referrers"],
            "popular_paths": traffic["popular_paths"],
            "releases": releases,
        },
        "npm": npm | {"publish_history": npm_history},
        "mcp_registry": mcp,
    }

    prev = load_previous_snapshot()
    save_snapshot(snapshot)

    print_report(stats, traffic, releases, npm, npm_history, mcp)

    if prev:
        print_diff(prev, snapshot)
    else:
        print("=== Notable Changes Since Last Snapshot ===")
        print()
        print("  (no previous snapshot)")
        print()

    print(f"Snapshot saved: {SNAPSHOT_FILE}")


if __name__ == "__main__":
    main()
