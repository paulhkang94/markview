#!/usr/bin/env python3
"""
Tests for metrics.py and check_traction.py.

Tier 2 behavioral tests — verify correctness of pure functions and
snapshot I/O without hitting live APIs.

Usage:
    python3 scripts/test-metrics.py
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).parent


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestMetricsImport(unittest.TestCase):
    def test_metrics_imports_cleanly(self):
        mod = _load("metrics")
        self.assertTrue(hasattr(mod, "main"))
        self.assertTrue(hasattr(mod, "fetch_json"))
        self.assertTrue(hasattr(mod, "gh_api"))

    def test_check_traction_imports_cleanly(self):
        mod = _load("check_traction")
        self.assertTrue(hasattr(mod, "main"))
        self.assertTrue(hasattr(mod, "collect"))
        self.assertTrue(hasattr(mod, "print_human"))


class TestBarChart(unittest.TestCase):
    def setUp(self):
        self.m = _load("metrics")

    def test_zero_downloads(self):
        self.assertEqual(self.m._bar(0), "")

    def test_two_downloads(self):
        self.assertEqual(self.m._bar(2), "█")

    def test_bar_capped_at_max_width(self):
        bar = self.m._bar(200, max_width=50)
        self.assertEqual(len(bar), 50)

    def test_bar_proportional(self):
        self.assertEqual(len(self.m._bar(10)), 5)
        self.assertEqual(len(self.m._bar(20)), 10)

    def test_bar_uses_block_char(self):
        bar = self.m._bar(4)
        self.assertTrue(all(c == "█" for c in bar))


class TestSnapshotIO(unittest.TestCase):
    def setUp(self):
        self.m = _load("metrics")

    def test_save_and_load_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            self.m.SNAPSHOT_FILE = Path(tmpdir) / "snapshots.jsonl"
            snap1 = {
                "timestamp": "2026-01-01T00:00:00Z",
                "github": {"stars": 10},
                "npm": {},
            }
            snap2 = {
                "timestamp": "2026-01-02T00:00:00Z",
                "github": {"stars": 12},
                "npm": {},
            }
            self.m.save_snapshot(snap1)
            self.m.save_snapshot(snap2)

            # load_previous_snapshot returns the one before the last
            prev = self.m.load_previous_snapshot()
            self.assertIsNotNone(prev)
            self.assertEqual(prev["github"]["stars"], 10)

    def test_no_previous_snapshot_returns_none(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            self.m.SNAPSHOT_FILE = Path(tmpdir) / "snapshots.jsonl"
            self.assertIsNone(self.m.load_previous_snapshot())

    def test_single_snapshot_returns_none_for_previous(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            self.m.SNAPSHOT_FILE = Path(tmpdir) / "snapshots.jsonl"
            self.m.save_snapshot({"timestamp": "2026-01-01T00:00:00Z"})
            self.assertIsNone(self.m.load_previous_snapshot())

    def test_snapshot_file_is_valid_jsonl(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            self.m.SNAPSHOT_FILE = Path(tmpdir) / "snapshots.jsonl"
            for i in range(3):
                self.m.save_snapshot(
                    {"timestamp": f"2026-01-0{i + 1}T00:00:00Z", "val": i}
                )
            lines = (Path(tmpdir) / "snapshots.jsonl").read_text().splitlines()
            self.assertEqual(len(lines), 3)
            for line in lines:
                parsed = json.loads(line)
                self.assertIn("timestamp", parsed)


class TestDiff(unittest.TestCase):
    def setUp(self):
        self.m = _load("metrics")

    def test_diff_no_change(self):
        snap = {
            "github": {
                "stars": 10,
                "traffic_14d": {"clones": {"total": 100}, "views": {"total": 50}},
            },
            "npm": {"downloads_7d": 30},
        }
        # Just verify print_diff doesn't crash with equal snapshots
        from io import StringIO

        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            self.m.print_diff(snap, snap)
        self.assertIn("no significant changes", mock_out.getvalue())

    def test_diff_shows_star_increase(self):
        prev = {
            "github": {
                "stars": 10,
                "traffic_14d": {"clones": {"total": 0}, "views": {"total": 0}},
            },
            "npm": {"downloads_7d": 0},
        }
        curr = {
            "github": {
                "stars": 15,
                "traffic_14d": {"clones": {"total": 0}, "views": {"total": 0}},
            },
            "npm": {"downloads_7d": 0},
        }
        from io import StringIO

        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            self.m.print_diff(prev, curr)
        output = mock_out.getvalue()
        self.assertIn("+5", output)
        self.assertIn("Stars", output)


class TestCheckTractionJsonFlag(unittest.TestCase):
    def test_json_output_is_valid(self):
        ct = _load("check_traction")
        fake_repo = {
            "stargazers_count": 29,
            "forks_count": 3,
            "subscribers_count": 0,
            "open_issues_count": 3,
        }
        fake_clones = {"count": 491, "uniques": 188}
        fake_views = {"count": 102, "uniques": 39}
        fake_referrers = [{"referrer": "reddit.com", "count": 26, "uniques": 18}]
        fake_releases = [
            {
                "tag_name": "v1.4.2",
                "assets": [{"download_count": 102}],
            }
        ]

        def mock_gh_api(path):
            if path.endswith(f"repos/{ct.REPO}"):
                return fake_repo
            if "traffic/clones" in path:
                return fake_clones
            if "traffic/views" in path:
                return fake_views
            if "popular/referrers" in path:
                return fake_referrers
            if "/releases" in path:
                return fake_releases
            return None

        with patch.object(ct, "gh_api", side_effect=mock_gh_api):
            data = ct.collect()

        self.assertEqual(data["stars"], 29)
        self.assertEqual(data["clones_14d"]["total"], 491)
        self.assertEqual(data["top_referrers"][0]["referrer"], "reddit.com")
        self.assertEqual(data["releases"][0]["tag"], "v1.4.2")
        self.assertEqual(data["releases"][0]["downloads"], 102)

        # Verify the data serializes to valid JSON
        serialized = json.dumps(data)
        parsed = json.loads(serialized)
        self.assertEqual(parsed["stars"], 29)

    def test_print_human_does_not_crash(self):
        ct = _load("check_traction")
        data = {
            "timestamp": "2026-05-07T00:00:00Z",
            "stars": 29,
            "forks": 3,
            "watchers": 0,
            "open_issues": 3,
            "clones_14d": {"total": 491, "unique": 188},
            "views_14d": {"total": 102, "unique": 39},
            "top_referrers": [{"referrer": "reddit.com", "count": 26, "uniques": 18}],
            "releases": [{"tag": "v1.4.2", "downloads": 102}],
        }
        from io import StringIO

        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            ct.print_human(data)
        output = mock_out.getvalue()
        self.assertIn("reddit.com", output)
        self.assertIn("v1.4.2", output)
        self.assertIn("29", output)


class TestThinWrappers(unittest.TestCase):
    def test_metrics_sh_delegates_to_python(self):
        wrapper = (SCRIPTS / "metrics.sh").read_text()
        self.assertIn("metrics.py", wrapper)
        self.assertIn("exec python3", wrapper)
        self.assertIn("bash-justified", wrapper)

    def test_check_traction_sh_delegates_to_python(self):
        wrapper = (SCRIPTS / "check-traction.sh").read_text()
        self.assertIn("check_traction.py", wrapper)
        self.assertIn("exec python3", wrapper)
        self.assertIn("bash-justified", wrapper)

    def test_metrics_sh_passes_args(self):
        wrapper = (SCRIPTS / "metrics.sh").read_text()
        self.assertIn('"$@"', wrapper)

    def test_check_traction_sh_passes_args(self):
        wrapper = (SCRIPTS / "check-traction.sh").read_text()
        self.assertIn('"$@"', wrapper)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(__import__("__main__"))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
