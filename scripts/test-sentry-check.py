#!/usr/bin/env python3
"""
Tests for sentry_check.py.

Tier 2 behavioral tests - verify issue-row shaping, gate verdict logic, and
exit codes against a fake SentryAPI. No live network, no Keychain access.

Usage:
    python3 scripts/test-sentry-check.py
"""

from __future__ import annotations

import importlib.util
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).parent


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _issue(
    short_id,
    title="App Hanging: App hanging for at least 2000 ms.",
    culprit="X.y",
    count="3",
    iid="100",
):
    return {
        "id": iid,
        "shortId": short_id,
        "title": title,
        "culprit": culprit,
        "count": count,
        "firstSeen": "2026-07-06T00:00:00Z",
        "lastSeen": "2026-07-29T00:00:00Z",
    }


class FakeAPI:
    """Duck-typed stand-in for SentryAPI: path -> canned response."""

    def __init__(self, issues=None, latest_releases=None):
        self.issues = issues or []
        self.latest_releases = latest_releases or {}

    def get(self, path, params=None):
        if path.endswith("/issues/") and "/projects/" in path:
            return self.issues
        for iid, rel in self.latest_releases.items():
            if f"/issues/{iid}/events/latest/" in path:
                return {"release": {"version": rel}}
        return {}


class TestIssueRow(unittest.TestCase):
    def setUp(self):
        self.m = _load("sentry_check")

    def test_shapes_fields(self):
        row = self.m.issue_row(_issue("APPLE-MACOS-2Z"), "1.7.1")
        self.assertEqual(row["shortId"], "APPLE-MACOS-2Z")
        self.assertEqual(row["firstSeen"], "2026-07-06")
        self.assertEqual(row["lastSeen"], "2026-07-29")
        self.assertEqual(row["latestEventRelease"], "1.7.1")

    def test_tolerates_missing_fields(self):
        row = self.m.issue_row({})
        self.assertEqual(row["shortId"], "?")
        self.assertEqual(row["culprit"], "")
        self.assertIsNone(row["latestEventRelease"])


class TestGateVerdict(unittest.TestCase):
    def setUp(self):
        self.m = _load("sentry_check")

    def _rows(self, api, release="1.7.1"):
        return self.m.release_report(api, release)

    def test_no_adoption_fails(self):
        result = self.m.gate_verdict([], "1.7.1", watch=[])
        self.assertEqual(result["verdict"], "NO_ADOPTION")

    def test_watched_group_fired_fails(self):
        api = FakeAPI(
            issues=[_issue("APPLE-MACOS-33", iid="1")], latest_releases={"1": "1.7.0"}
        )
        rows = self._rows(api)
        result = self.m.gate_verdict(rows, "1.7.1", watch=["APPLE-MACOS-33"])
        self.assertEqual(result["verdict"], "FAIL")
        self.assertEqual(result["watched_fired"], ["APPLE-MACOS-33"])

    def test_live_hang_group_fails_even_if_unwatched(self):
        api = FakeAPI(
            issues=[_issue("APPLE-MACOS-2Z", iid="2")], latest_releases={"2": "1.7.1"}
        )
        rows = self._rows(api)
        result = self.m.gate_verdict(rows, "1.7.1", watch=[])
        self.assertEqual(result["verdict"], "FAIL")
        self.assertEqual(result["live_hang_groups"][0]["shortId"], "APPLE-MACOS-2Z")

    def test_non_hang_issue_with_old_latest_release_passes(self):
        api = FakeAPI(
            issues=[
                _issue("APPLE-MACOS-2", title="NSCocoaErrorDomain: Code: 260", iid="3")
            ],
            latest_releases={"3": "1.5.0"},
        )
        rows = self._rows(api)
        result = self.m.gate_verdict(rows, "1.7.1", watch=["APPLE-MACOS-33"])
        self.assertEqual(result["verdict"], "PASS")

    def test_hang_with_older_latest_release_passes(self):
        api = FakeAPI(
            issues=[_issue("APPLE-MACOS-4", iid="4")], latest_releases={"4": "1.4.2"}
        )
        rows = self._rows(api)
        result = self.m.gate_verdict(rows, "1.7.1", watch=[])
        self.assertEqual(result["verdict"], "PASS")


class TestMainExitCodes(unittest.TestCase):
    def setUp(self):
        self.m = _load("sentry_check")

    def test_gate_fail_exits_1(self):
        api = FakeAPI(
            issues=[_issue("APPLE-MACOS-2Z", iid="2")], latest_releases={"2": "1.7.1"}
        )
        with patch("sys.stdout", new=StringIO()) as out:
            rc = self.m.main(["--gate", "1.7.1"], api=api)
        self.assertEqual(rc, 1)
        self.assertIn("GATE FAIL", out.getvalue())

    def test_gate_pass_exits_0(self):
        api = FakeAPI(
            issues=[_issue("APPLE-MACOS-4", iid="4")], latest_releases={"4": "1.4.2"}
        )
        with patch("sys.stdout", new=StringIO()) as out:
            rc = self.m.main(["--gate", "1.7.1", "--watch", "APPLE-MACOS-33"], api=api)
        self.assertEqual(rc, 0)
        self.assertIn("GATE PASS", out.getvalue())

    def test_no_adoption_exits_1(self):
        api = FakeAPI(issues=[])
        with patch("sys.stdout", new=StringIO()) as out:
            rc = self.m.main(["--gate", "1.7.2"], api=api)
        self.assertEqual(rc, 1)
        self.assertIn("NO_ADOPTION", out.getvalue())

    def test_unresolved_listing_exits_0(self):
        api = FakeAPI(issues=[_issue("APPLE-MACOS-C", iid="5")])
        with patch("sys.stdout", new=StringIO()) as out:
            rc = self.m.main([], api=api)
        self.assertEqual(rc, 0)
        self.assertIn("APPLE-MACOS-C", out.getvalue())

    def test_missing_token_exits_2(self):
        mod = self.m
        with patch.object(mod, "keychain_token", return_value=None):
            with patch("sys.stderr", new=StringIO()):
                rc = mod.main([])
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
