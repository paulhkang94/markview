#!/usr/bin/env python3
"""
Tests for ci_status.py.

Tier 2 behavioral tests — verify summarization, table formatting, and exit
code logic against fixture check lists. All `gh`/`git` subprocess calls are
mocked; no live network, no real gh CLI invocation.

Usage:
    python3 scripts/test-ci-status.py
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import MagicMock, patch

SCRIPTS = Path(__file__).parent


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _fake_run(returncode: int, stdout: str = ""):
    result = MagicMock()
    result.returncode = returncode
    result.stdout = stdout
    return result


class TestImport(unittest.TestCase):
    def test_imports_cleanly(self):
        mod = _load("ci_status")
        self.assertTrue(hasattr(mod, "main"))
        self.assertTrue(hasattr(mod, "summarize"))


class TestSummarize(unittest.TestCase):
    def setUp(self):
        self.m = _load("ci_status")

    def test_all_completed_and_passed(self):
        checks = [
            {"status": "COMPLETED", "conclusion": "SUCCESS"},
            {"status": "COMPLETED", "conclusion": "SUCCESS"},
        ]
        pending, failed, total = self.m.summarize(checks)
        self.assertEqual((pending, failed, total), (0, 0, 2))

    def test_one_pending(self):
        checks = [
            {"status": "COMPLETED", "conclusion": "SUCCESS"},
            {"status": "IN_PROGRESS", "conclusion": None},
        ]
        pending, failed, total = self.m.summarize(checks)
        self.assertEqual((pending, failed, total), (1, 0, 2))

    def test_one_failed(self):
        checks = [
            {"status": "COMPLETED", "conclusion": "FAILURE"},
            {"status": "COMPLETED", "conclusion": "SUCCESS"},
        ]
        pending, failed, total = self.m.summarize(checks)
        self.assertEqual((pending, failed, total), (0, 1, 2))


class TestDecideExitCode(unittest.TestCase):
    def setUp(self):
        self.m = _load("ci_status")

    def test_pending_wins_over_failed(self):
        self.assertEqual(self.m.decide_exit_code(pending=1, failed=1), 2)

    def test_failed_when_no_pending(self):
        self.assertEqual(self.m.decide_exit_code(pending=0, failed=1), 1)

    def test_pass_when_clean(self):
        self.assertEqual(self.m.decide_exit_code(pending=0, failed=0), 0)


class TestFormatTable(unittest.TestCase):
    def setUp(self):
        self.m = _load("ci_status")

    def test_empty_list_returns_empty_string(self):
        self.assertEqual(self.m.format_table([]), "")

    def test_includes_name_and_conclusion(self):
        checks = [{"name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"}]
        table = self.m.format_table(checks)
        self.assertIn("build", table)
        self.assertIn("SUCCESS", table)

    def test_falls_back_to_status_when_no_conclusion(self):
        checks = [{"name": "build", "status": "IN_PROGRESS", "conclusion": None}]
        table = self.m.format_table(checks)
        self.assertIn("IN_PROGRESS", table)


class TestGhJson(unittest.TestCase):
    def setUp(self):
        self.m = _load("ci_status")

    def test_nonzero_exit_returns_none(self):
        with patch.object(self.m.subprocess, "run", return_value=_fake_run(1)):
            self.assertIsNone(self.m.gh_json(["pr", "view", "1"]))

    def test_invalid_json_returns_none(self):
        with patch.object(
            self.m.subprocess, "run", return_value=_fake_run(0, "not json")
        ):
            self.assertIsNone(self.m.gh_json(["pr", "view", "1"]))

    def test_valid_json_parses(self):
        with patch.object(
            self.m.subprocess, "run", return_value=_fake_run(0, '{"a": 1}')
        ):
            self.assertEqual(self.m.gh_json(["pr", "view", "1"]), {"a": 1})


class TestGetChecksForPr(unittest.TestCase):
    def setUp(self):
        self.m = _load("ci_status")

    def test_extracts_rollup(self):
        payload = {"statusCheckRollup": [{"name": "build", "status": "COMPLETED"}]}
        with patch.object(self.m, "gh_json", return_value=payload):
            checks = self.m.get_checks_for_pr("42")
        self.assertEqual(checks, [{"name": "build", "status": "COMPLETED"}])

    def test_missing_rollup_returns_empty(self):
        with patch.object(self.m, "gh_json", return_value={}):
            self.assertEqual(self.m.get_checks_for_pr("42"), [])

    def test_gh_failure_returns_empty(self):
        with patch.object(self.m, "gh_json", return_value=None):
            self.assertEqual(self.m.get_checks_for_pr("42"), [])


class TestGetChecksForBranch(unittest.TestCase):
    def setUp(self):
        self.m = _load("ci_status")

    def test_chains_run_list_then_run_view(self):
        run_list_result = [{"databaseId": 999}]
        run_view_result = {
            "jobs": [{"name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"}]
        }

        def fake_gh_json(args):
            if args[:2] == ["run", "list"]:
                return run_list_result
            if args[:2] == ["run", "view"]:
                return run_view_result
            return None

        with patch.object(self.m, "gh_json", side_effect=fake_gh_json):
            checks = self.m.get_checks_for_branch("main")
        self.assertEqual(len(checks), 1)
        self.assertEqual(checks[0]["name"], "build")

    def test_no_runs_returns_empty(self):
        with patch.object(self.m, "gh_json", return_value=[]):
            self.assertEqual(self.m.get_checks_for_branch("main"), [])


class TestMain(unittest.TestCase):
    def setUp(self):
        self.m = _load("ci_status")

    def test_no_checks_prints_message_and_exits_zero(self):
        with (
            patch.object(self.m, "get_checks_for_branch", return_value=[]),
            patch("sys.stdout", new_callable=StringIO) as mock_out,
        ):
            rc = self.m.main([])
        self.assertEqual(rc, 0)
        self.assertIn("No checks found.", mock_out.getvalue())

    def test_pr_number_routes_to_pr_lookup(self):
        with (
            patch.object(self.m, "get_checks_for_pr", return_value=[]) as mock_pr,
            patch.object(self.m, "get_checks_for_branch") as mock_branch,
            patch("sys.stdout", new_callable=StringIO),
        ):
            self.m.main(["123"])
        mock_pr.assert_called_once_with("123")
        mock_branch.assert_not_called()

    def test_all_pass_exits_zero(self):
        checks = [{"name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"}]
        with (
            patch.object(self.m, "get_checks_for_branch", return_value=checks),
            patch("sys.stdout", new_callable=StringIO) as mock_out,
        ):
            rc = self.m.main([])
        self.assertEqual(rc, 0)
        self.assertIn("PASS", mock_out.getvalue())

    def test_failure_exits_one(self):
        checks = [{"name": "build", "status": "COMPLETED", "conclusion": "FAILURE"}]
        with (
            patch.object(self.m, "get_checks_for_branch", return_value=checks),
            patch("sys.stdout", new_callable=StringIO) as mock_out,
        ):
            rc = self.m.main([])
        self.assertEqual(rc, 1)
        self.assertIn("FAILED", mock_out.getvalue())

    def test_pending_exits_two(self):
        checks = [{"name": "build", "status": "IN_PROGRESS", "conclusion": None}]
        with (
            patch.object(self.m, "get_checks_for_branch", return_value=checks),
            patch("sys.stdout", new_callable=StringIO) as mock_out,
        ):
            rc = self.m.main([])
        self.assertEqual(rc, 2)
        self.assertIn("PENDING", mock_out.getvalue())


class TestThinWrapper(unittest.TestCase):
    def test_sh_delegates_to_python(self):
        wrapper = (SCRIPTS / "ci-status.sh").read_text()
        self.assertIn("ci_status.py", wrapper)
        self.assertIn("exec python3", wrapper)
        self.assertIn("bash-justified", wrapper)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(__import__("__main__"))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
