#!/usr/bin/env python3
"""
Tests for check_rule_gates.py.

Tier 2 behavioral tests — verify the checker logic against synthetic repo
roots (temp dirs), never against the real rule-gates.json or CI files.
Mirrors the coverage of Tests/test-rule-gates.sh (the black-box CLI test)
at the unit level, plus arg-parsing edge cases.

Usage:
    python3 scripts/test-check-rule-gates.py
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
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


def _write_manifest(root: Path, rules: list[dict]) -> None:
    (root / "scripts").mkdir(parents=True, exist_ok=True)
    (root / "scripts" / "rule-gates.json").write_text(
        json.dumps({"_schema": "1", "rules": rules})
    )


class TestCheckRuleGatesImport(unittest.TestCase):
    def test_imports_cleanly(self):
        mod = _load("check_rule_gates")
        self.assertTrue(hasattr(mod, "main"))
        self.assertTrue(hasattr(mod, "check_rules"))
        self.assertTrue(hasattr(mod, "load_manifest"))


class TestParseRepoRoot(unittest.TestCase):
    def setUp(self):
        self.m = _load("check_rule_gates")

    def test_flag_form(self):
        result = self.m.parse_repo_root(["--repo-root", "/tmp/foo"], Path("/default"))
        self.assertEqual(result, Path("/tmp/foo"))

    def test_positional_form(self):
        result = self.m.parse_repo_root(["/tmp/bar"], Path("/default"))
        self.assertEqual(result, Path("/tmp/bar"))

    def test_no_args_uses_default(self):
        result = self.m.parse_repo_root([], Path("/default"))
        self.assertEqual(result, Path("/default"))

    def test_double_dash_flag_falls_back_to_default(self):
        result = self.m.parse_repo_root(["--extended"], Path("/default"))
        self.assertEqual(result, Path("/default"))


class TestCheckRules(unittest.TestCase):
    def setUp(self):
        self.m = _load("check_rule_gates")

    def test_pattern_present_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".github/workflows").mkdir(parents=True)
            (root / ".github/workflows/guard.yml").write_text(
                "run: bash scripts/check-version-sync.sh"
            )
            rules = [
                {
                    "id": "r1",
                    "ci_files": [".github/workflows/guard.yml"],
                    "ci_pattern": r"check-version-sync\.sh",
                }
            ]
            passes, failures, skipped = self.m.check_rules(root, rules)
            self.assertEqual(passes, ["r1"])
            self.assertEqual(failures, [])
            self.assertEqual(skipped, [])

    def test_pattern_missing_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".github/workflows").mkdir(parents=True)
            (root / ".github/workflows/guard.yml").write_text("run: echo nothing")
            rules = [
                {
                    "id": "r2",
                    "ci_files": [".github/workflows/guard.yml"],
                    "ci_pattern": r"check-rule-gates\.py",
                }
            ]
            passes, failures, skipped = self.m.check_rules(root, rules)
            self.assertEqual(passes, [])
            self.assertEqual(len(failures), 1)
            self.assertEqual(failures[0].rule_id, "r2")

    def test_ci_file_missing_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rules = [
                {
                    "id": "r3",
                    "ci_files": [".github/workflows/nonexistent.yml"],
                    "ci_pattern": "anything",
                }
            ]
            _, failures, _ = self.m.check_rules(root, rules)
            self.assertEqual(len(failures), 1)
            self.assertIn("not found", failures[0].reason)

    def test_pre_push_only_is_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rules = [{"id": "r4", "gate_type": "pre_push_only"}]
            passes, failures, skipped = self.m.check_rules(root, rules)
            self.assertEqual(skipped, ["r4"])
            self.assertEqual(passes, [])
            self.assertEqual(failures, [])

    def test_invalid_regex_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".github/workflows").mkdir(parents=True)
            (root / ".github/workflows/guard.yml").write_text("x")
            rules = [
                {
                    "id": "r5",
                    "ci_files": [".github/workflows/guard.yml"],
                    "ci_pattern": "(unclosed",
                }
            ]
            _, failures, _ = self.m.check_rules(root, rules)
            self.assertEqual(len(failures), 1)
            self.assertIn("invalid ci_pattern regex", failures[0].reason)


class TestMainExitCodes(unittest.TestCase):
    def setUp(self):
        self.m = _load("check_rule_gates")

    def test_manifest_missing_exits_1(self):
        with tempfile.TemporaryDirectory() as tmp:
            rc = self.m.main(["--repo-root", tmp])
            self.assertEqual(rc, 1)

    def test_empty_rules_exits_0(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_manifest(root, [])
            rc = self.m.main(["--repo-root", tmp])
            self.assertEqual(rc, 0)

    def test_all_pass_exits_0(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".github/workflows").mkdir(parents=True)
            (root / ".github/workflows/guard.yml").write_text("check-version-sync.sh")
            _write_manifest(
                root,
                [
                    {
                        "id": "r1",
                        "ci_files": [".github/workflows/guard.yml"],
                        "ci_pattern": "check-version-sync",
                    }
                ],
            )
            rc = self.m.main(["--repo-root", tmp])
            self.assertEqual(rc, 0)

    def test_any_fail_exits_1(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".github/workflows").mkdir(parents=True)
            (root / ".github/workflows/guard.yml").write_text("nothing relevant")
            _write_manifest(
                root,
                [
                    {
                        "id": "r1",
                        "ci_files": [".github/workflows/guard.yml"],
                        "ci_pattern": "check-version-sync",
                    }
                ],
            )
            rc = self.m.main(["--repo-root", tmp])
            self.assertEqual(rc, 1)

    def test_failure_output_names_rule_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".github/workflows").mkdir(parents=True)
            (root / ".github/workflows/guard.yml").write_text("nothing")
            _write_manifest(
                root,
                [
                    {
                        "id": "my-unique-rule-id",
                        "ci_files": [".github/workflows/guard.yml"],
                        "ci_pattern": "pattern-not-in-file",
                    }
                ],
            )
            with patch("sys.stdout", new_callable=StringIO) as mock_out:
                self.m.main(["--repo-root", tmp])
            self.assertIn("my-unique-rule-id", mock_out.getvalue())


class TestThinWrapper(unittest.TestCase):
    def test_check_rule_gates_sh_delegates_to_python(self):
        wrapper = (SCRIPTS / "check-rule-gates.sh").read_text()
        self.assertIn("check_rule_gates.py", wrapper)
        self.assertIn("exec python3", wrapper)
        self.assertIn("bash-justified", wrapper)

    def test_check_rule_gates_sh_passes_args(self):
        wrapper = (SCRIPTS / "check-rule-gates.sh").read_text()
        self.assertIn('"$@"', wrapper)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(__import__("__main__"))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
