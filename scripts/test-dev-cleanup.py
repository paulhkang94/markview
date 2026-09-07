#!/usr/bin/env python3
"""
Tests for dev-cleanup.py (mar-048).

Tier 2 behavioral tests against real temp directories (no subprocess calls
in dev-cleanup.py at all, so nothing to stub) — every test builds an
isolated `project_dir` / `home` under tempfile.TemporaryDirectory() and
asserts against that, never the real repo or the real
~/Library/Developer/Xcode/DerivedData.

Usage:
    python3 scripts/test-dev-cleanup.py
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _write_file(path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * size)


# ── parse_args ───────────────────────────────────────────────────────────────


class TestParseArgs(unittest.TestCase):
    def test_defaults_to_dry_run(self):
        mod = _load("dev-cleanup")
        self.assertEqual(mod.parse_args([]), False)

    def test_apply_flag(self):
        mod = _load("dev-cleanup")
        self.assertEqual(mod.parse_args(["--apply"]), True)

    def test_unknown_option_raises(self):
        mod = _load("dev-cleanup")
        with self.assertRaises(mod.CleanupError) as cm:
            mod.parse_args(["--bogus"])
        self.assertIn("Unknown option: --bogus", str(cm.exception))
        self.assertIn("--apply", str(cm.exception))


# ── human_size ───────────────────────────────────────────────────────────────


class TestHumanSize(unittest.TestCase):
    def test_bytes(self):
        mod = _load("dev-cleanup")
        self.assertEqual(mod.human_size(0), "0 B")
        self.assertEqual(mod.human_size(512), "512 B")

    def test_kb_mb_gb(self):
        mod = _load("dev-cleanup")
        self.assertEqual(mod.human_size(2048), "2.0 KB")
        self.assertEqual(mod.human_size(5 * 1024 * 1024), "5.0 MB")
        self.assertEqual(mod.human_size(3 * 1024 * 1024 * 1024), "3.0 GB")


# ── _dir_size ────────────────────────────────────────────────────────────────


class TestDirSize(unittest.TestCase):
    def test_sums_nested_files(self):
        mod = _load("dev-cleanup")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            _write_file(tmp / "a.txt", 100)
            _write_file(tmp / "nested/b.txt", 200)
            self.assertEqual(mod._dir_size(tmp), 300)

    def test_single_file(self):
        mod = _load("dev-cleanup")
        with tempfile.TemporaryDirectory() as td:
            f = Path(td) / "solo.bin"
            _write_file(f, 42)
            self.assertEqual(mod._dir_size(f), 42)

    def test_missing_path_is_zero(self):
        mod = _load("dev-cleanup")
        self.assertEqual(mod._dir_size(Path("/nonexistent/path/xyz")), 0)


# ── find_targets ─────────────────────────────────────────────────────────────


class TestFindTargets(unittest.TestCase):
    def test_returns_only_existing_targets(self):
        mod = _load("dev-cleanup")
        with tempfile.TemporaryDirectory() as td:
            project_dir = Path(td) / "repo"
            home = Path(td) / "home"
            (project_dir / "build").mkdir(parents=True)
            # MarkView.app and DerivedData deliberately absent.
            targets = mod.find_targets(project_dir, home)
        self.assertEqual(targets, [project_dir / "build"])

    def test_finds_app_bundle_and_derived_data(self):
        mod = _load("dev-cleanup")
        with tempfile.TemporaryDirectory() as td:
            project_dir = Path(td) / "repo"
            home = Path(td) / "home"
            (project_dir / "build").mkdir(parents=True)
            (project_dir / "MarkView.app").mkdir(parents=True)
            dd = home / "Library/Developer/Xcode/DerivedData"
            (dd / "MarkView-abc123").mkdir(parents=True)
            (dd / "MarkView-def456").mkdir(parents=True)
            (dd / "OtherProject-xyz789").mkdir(parents=True)  # must NOT match

            targets = mod.find_targets(project_dir, home)

        self.assertIn(project_dir / "build", targets)
        self.assertIn(project_dir / "MarkView.app", targets)
        self.assertIn(dd / "MarkView-abc123", targets)
        self.assertIn(dd / "MarkView-def456", targets)
        self.assertNotIn(dd / "OtherProject-xyz789", targets)

    def test_no_targets_when_nothing_exists(self):
        mod = _load("dev-cleanup")
        with tempfile.TemporaryDirectory() as td:
            project_dir = Path(td) / "repo"
            home = Path(td) / "home"
            targets = mod.find_targets(project_dir, home)
        self.assertEqual(targets, [])


# ── run_cleanup: dry run (default) ──────────────────────────────────────────


class TestRunCleanupDryRun(unittest.TestCase):
    def test_dry_run_lists_targets_and_deletes_nothing(self):
        mod = _load("dev-cleanup")
        with tempfile.TemporaryDirectory() as td:
            project_dir = Path(td) / "repo"
            home = Path(td) / "home"
            _write_file(project_dir / "build/obj.o", 1024)
            _write_file(project_dir / "MarkView.app/Contents/MacOS/MarkView", 2048)

            out = []
            rc = mod.run_cleanup([], project_dir=project_dir, home=home, out=out.append)

            self.assertEqual(rc, 0)
            text = "\n".join(out)
            self.assertIn("dry run", text.lower())
            self.assertIn(str(project_dir / "build"), text)
            self.assertIn(str(project_dir / "MarkView.app"), text)
            self.assertIn("Dry run only", text)
            # Nothing deleted.
            self.assertTrue((project_dir / "build/obj.o").exists())
            self.assertTrue((project_dir / "MarkView.app").exists())

    def test_no_targets_reports_nothing_to_clean(self):
        mod = _load("dev-cleanup")
        with tempfile.TemporaryDirectory() as td:
            project_dir = Path(td) / "repo"
            home = Path(td) / "home"
            out = []
            rc = mod.run_cleanup([], project_dir=project_dir, home=home, out=out.append)
        self.assertEqual(rc, 0)
        self.assertIn("Nothing to clean", "\n".join(out))


# ── run_cleanup: --apply ─────────────────────────────────────────────────────


class TestRunCleanupApply(unittest.TestCase):
    def test_apply_deletes_targets_and_reports_freed_size(self):
        mod = _load("dev-cleanup")
        with tempfile.TemporaryDirectory() as td:
            project_dir = Path(td) / "repo"
            home = Path(td) / "home"
            _write_file(project_dir / "build/obj.o", 1024)
            _write_file(project_dir / "MarkView.app/Contents/MacOS/MarkView", 1024)
            dd = home / "Library/Developer/Xcode/DerivedData/MarkView-abc123"
            _write_file(dd / "Logs/build.log", 1024)

            out = []
            rc = mod.run_cleanup(["--apply"], project_dir=project_dir, home=home, out=out.append)

        self.assertEqual(rc, 0)
        text = "\n".join(out)
        self.assertIn("Freed", text)
        self.assertFalse((project_dir / "build").exists())
        self.assertFalse((project_dir / "MarkView.app").exists())
        self.assertFalse(dd.exists())

    def test_apply_never_touches_unrelated_derived_data(self):
        mod = _load("dev-cleanup")
        with tempfile.TemporaryDirectory() as td:
            project_dir = Path(td) / "repo"
            home = Path(td) / "home"
            other_dd = home / "Library/Developer/Xcode/DerivedData/OtherProject-xyz789"
            _write_file(other_dd / "Logs/build.log", 1024)
            _write_file(project_dir / "build/obj.o", 1024)

            out = []
            mod.run_cleanup(["--apply"], project_dir=project_dir, home=home, out=out.append)

            self.assertTrue(other_dd.exists())


# ── Verify wiring ────────────────────────────────────────────────────────────


class TestVerifyWiring(unittest.TestCase):
    def test_verify_py_runs_this_suite(self):
        verify_source = (SCRIPTS / "verify.py").read_text()
        self.assertIn("test-dev-cleanup.py", verify_source)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(__import__("__main__"))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
