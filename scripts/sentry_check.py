#!/usr/bin/env python3
"""
sentry_check.py - query Sentry field telemetry for MarkView and run release close-gates.

Replaces the ad-hoc curl + inline-python pattern used for the recurring
"can we close the hang tracker yet?" checks (mar-043 and successors).

Usage:
    python3 scripts/sentry_check.py                       # unresolved issues, last 14d
    python3 scripts/sentry_check.py --release 1.7.1       # issues with events on that release
    python3 scripts/sentry_check.py --gate 1.7.1 --watch APPLE-MACOS-33,APPLE-MACOS-3B
                                                          # close-gate verdict for a release
    python3 scripts/sentry_check.py --json                # machine-readable output

Token: macOS Keychain item SENTRY_AUTH_TOKEN (account "sentry"). Never passed
via argv or exported env.

Exit codes:
    0  listing OK / gate PASS
    1  gate FAIL (a watched group fired on the release, or release has no
       field events yet - "no adoption" is indistinguishable from healthy,
       so the gate refuses to pass on zero data)
    2  auth/API/config error
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ORG = "paulkang"
PROJECT = "apple-macos"
BASE = "https://sentry.io/api/0"


def keychain_token() -> str | None:
    result = subprocess.run(
        [
            "security",
            "find-generic-password",
            "-s",
            "SENTRY_AUTH_TOKEN",
            "-a",
            "sentry",
            "-w",
        ],
        capture_output=True,
        text=True,
    )
    token = result.stdout.strip()
    return token if result.returncode == 0 and token else None


class SentryAPI:
    def __init__(self, token: str):
        self._token = token

    def get(self, path: str, params: dict | None = None) -> object:
        url = f"{BASE}{path}"
        if params:
            url += "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(
            url, headers={"Authorization": f"Bearer {self._token}"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)


def fetch_issues(
    api: SentryAPI, query: str, stats_period: str | None = "14d"
) -> list[dict]:
    params: dict = {"query": query}
    # Sentry rejects statsPeriod values other than '', '24h', '14d' on this endpoint;
    # release-scoped queries use the default window (omit the param).
    if stats_period:
        params["statsPeriod"] = stats_period
    data = api.get(f"/projects/{ORG}/{PROJECT}/issues/", params)
    return data if isinstance(data, list) else []


def latest_event_release(api: SentryAPI, issue_id: str) -> str:
    try:
        ev = api.get(f"/organizations/{ORG}/issues/{issue_id}/events/latest/")
    except urllib.error.HTTPError:
        return "?"
    if not isinstance(ev, dict):
        return "?"
    rel = ev.get("release") or {}
    return rel.get("version", "?") if isinstance(rel, dict) else "?"


def issue_row(issue: dict, latest_release: str | None = None) -> dict:
    return {
        "shortId": issue.get("shortId", "?"),
        "title": (issue.get("title") or "")[:70],
        "culprit": (issue.get("culprit") or "")[:70],
        "count": issue.get("count", "?"),
        "firstSeen": (issue.get("firstSeen") or "")[:10],
        "lastSeen": (issue.get("lastSeen") or "")[:10],
        "latestEventRelease": latest_release,
    }


def release_report(api: SentryAPI, release: str) -> list[dict]:
    issues = fetch_issues(api, f"release:{release}", stats_period=None)
    return [issue_row(i, latest_event_release(api, str(i.get("id")))) for i in issues]


def is_hang(row: dict) -> bool:
    return "App Hanging" in (row.get("title") or "")


def gate_verdict(rows: list[dict], release: str, watch: list[str]) -> dict:
    """Close-gate semantics: PASS only if the release HAS field events (adoption)
    AND no watched group fired on it AND no hang group's latest event is on it."""
    watched_fired = [r for r in rows if r["shortId"] in watch]
    live_hangs = [
        r for r in rows if is_hang(r) and r.get("latestEventRelease") == release
    ]
    if not rows:
        verdict = "NO_ADOPTION"
    elif watched_fired or live_hangs:
        verdict = "FAIL"
    else:
        verdict = "PASS"
    return {
        "release": release,
        "verdict": verdict,
        "watched_fired": [r["shortId"] for r in watched_fired],
        "live_hang_groups": [
            {"shortId": r["shortId"], "culprit": r["culprit"], "count": r["count"]}
            for r in live_hangs
        ],
        "issues_with_release_events": len(rows),
    }


def format_rows(rows: list[dict]) -> str:
    lines = []
    for r in rows:
        rel = (
            f" | latest-release: {r['latestEventRelease']}"
            if r.get("latestEventRelease")
            else ""
        )
        lines.append(
            f"{r['shortId']:<16} | {r['culprit'] or r['title']:<50} "
            f"| count: {r['count']:>4} | {r['firstSeen']} -> {r['lastSeen']}{rel}"
        )
    return "\n".join(lines)


def main(argv: list[str] | None = None, api: SentryAPI | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", help="list issues with events on this release")
    parser.add_argument(
        "--gate", metavar="RELEASE", help="run close-gate verdict for a release"
    )
    parser.add_argument(
        "--watch",
        default="",
        help="comma-separated Sentry shortIds that must NOT fire on the gated release",
    )
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args(argv)

    if api is None:
        token = keychain_token()
        if not token:
            print(
                "ERROR: SENTRY_AUTH_TOKEN not found in Keychain (account 'sentry')",
                file=sys.stderr,
            )
            return 2
        api = SentryAPI(token)

    try:
        if args.gate:
            rows = release_report(api, args.gate)
            watch = [w.strip() for w in args.watch.split(",") if w.strip()]
            result = gate_verdict(rows, args.gate, watch)
            if args.as_json:
                print(json.dumps({"rows": rows, "gate": result}, indent=2))
            else:
                print(format_rows(rows))
                print(
                    f"\nGATE {result['verdict']} - release {args.gate}: "
                    f"{result['issues_with_release_events']} issue group(s) with events, "
                    f"watched fired: {result['watched_fired'] or 'none'}, "
                    f"live hang groups: {[g['shortId'] for g in result['live_hang_groups']] or 'none'}"
                )
            return 0 if result["verdict"] == "PASS" else 1

        if args.release:
            rows = release_report(api, args.release)
            print(json.dumps(rows, indent=2) if args.as_json else format_rows(rows))
            return 0

        issues = fetch_issues(api, "is:unresolved")
        rows = [issue_row(i) for i in issues]
        print(json.dumps(rows, indent=2) if args.as_json else format_rows(rows))
        return 0
    except urllib.error.HTTPError as e:
        print(
            f"ERROR: Sentry API {e.code}: {e.read().decode(errors='replace')[:200]}",
            file=sys.stderr,
        )
        return 2
    except urllib.error.URLError as e:
        print(f"ERROR: Sentry API unreachable: {e.reason}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
