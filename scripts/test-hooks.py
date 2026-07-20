#!/usr/bin/env python3
"""
Tests for auto_install.py and render_verify_gate.py.

Tier 2 behavioral tests — both scripts are Claude Code hooks that parse a
JSON payload from stdin and decide whether to fire. All git/subprocess
boundaries are stubbed or run against real (but disposable) temp repos —
no live network, no actual `bundle.sh` build, no real Dock reload.

Usage:
    python3 scripts/test-hooks.py
"""

from __future__ import annotations

import importlib.util
import subprocess
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


def _init_git_repo(root: Path) -> None:
    subprocess.run(["git", "init", "-q"], cwd=root, check=True)
    subprocess.run(
        ["git", "config", "user.email", "test@test.com"], cwd=root, check=True
    )
    subprocess.run(["git", "config", "user.name", "test"], cwd=root, check=True)


# ── auto_install.py ─────────────────────────────────────────────────────────


class TestAutoInstallImport(unittest.TestCase):
    def test_imports_cleanly(self):
        mod = _load("auto_install")
        self.assertTrue(hasattr(mod, "main"))
        self.assertTrue(hasattr(mod, "should_fire"))


class TestShouldFire(unittest.TestCase):
    def setUp(self):
        self.m = _load("auto_install")

    def test_fires_on_successful_git_push(self):
        payload = {
            "tool_name": "Bash",
            "tool_response": {"exit_code": 0},
            "tool_input": {"command": "git push origin main"},
        }
        self.assertTrue(self.m.should_fire(payload))

    def test_fires_on_git_push_with_tags(self):
        # Regression: the original bash regex matched `git push --tags` too,
        # despite the comment claiming otherwise. Behavior preserved exactly.
        payload = {
            "tool_name": "Bash",
            "tool_response": {"exit_code": 0},
            "tool_input": {"command": "git push origin main --tags"},
        }
        self.assertTrue(self.m.should_fire(payload))

    def test_does_not_fire_on_non_bash_tool(self):
        payload = {
            "tool_name": "Edit",
            "tool_response": {"exit_code": 0},
            "tool_input": {"command": "git push"},
        }
        self.assertFalse(self.m.should_fire(payload))

    def test_does_not_fire_on_failed_push(self):
        payload = {
            "tool_name": "Bash",
            "tool_response": {"exit_code": 1},
            "tool_input": {"command": "git push"},
        }
        self.assertFalse(self.m.should_fire(payload))

    def test_does_not_fire_on_non_push_command(self):
        payload = {
            "tool_name": "Bash",
            "tool_response": {"exit_code": 0},
            "tool_input": {"command": "git status"},
        }
        self.assertFalse(self.m.should_fire(payload))

    def test_handles_camelcase_exit_code_key(self):
        payload = {
            "tool_name": "Bash",
            "tool_response": {"exitCode": 0},
            "tool_input": {"command": "git push"},
        }
        self.assertTrue(self.m.should_fire(payload))

    def test_empty_payload_does_not_fire(self):
        self.assertFalse(self.m.should_fire({}))


class TestReadPayload(unittest.TestCase):
    def setUp(self):
        self.m = _load("auto_install")

    def test_reads_valid_json(self):
        import io

        stream = io.StringIO('{"tool_name": "Bash"}')
        self.assertEqual(self.m.read_payload(stream), {"tool_name": "Bash"})

    def test_invalid_json_returns_empty_dict(self):
        import io

        stream = io.StringIO("not json")
        self.assertEqual(self.m.read_payload(stream), {})


# ── render_verify_gate.py ───────────────────────────────────────────────────


class TestRenderVerifyGateImport(unittest.TestCase):
    def test_imports_cleanly(self):
        mod = _load("render_verify_gate")
        self.assertTrue(hasattr(mod, "main"))
        self.assertTrue(hasattr(mod, "is_commit_or_push"))
        self.assertTrue(hasattr(mod, "stamp_age_seconds"))


class TestIsCommitOrPush(unittest.TestCase):
    def setUp(self):
        self.m = _load("render_verify_gate")

    def test_matches_commit(self):
        self.assertTrue(self.m.is_commit_or_push("git commit -m foo"))

    def test_matches_push(self):
        self.assertTrue(self.m.is_commit_or_push("git push origin main"))

    def test_does_not_match_status(self):
        self.assertFalse(self.m.is_commit_or_push("git status"))

    def test_does_not_match_unrelated_command(self):
        self.assertFalse(self.m.is_commit_or_push("ls -la"))


class TestStampAgeSeconds(unittest.TestCase):
    def setUp(self):
        self.m = _load("render_verify_gate")

    def test_missing_stamp_returns_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            stamp = Path(tmp) / ".last-verify-at"
            self.assertIsNone(self.m.stamp_age_seconds(stamp, now=1000.0))

    def test_ha008_format(self):
        with tempfile.TemporaryDirectory() as tmp:
            stamp = Path(tmp) / ".last-verify-at"
            stamp.write_text("TIER=test\nTS=1000\n")
            self.assertEqual(self.m.stamp_age_seconds(stamp, now=1600.0), 600)

    def test_legacy_bare_epoch_format(self):
        with tempfile.TemporaryDirectory() as tmp:
            stamp = Path(tmp) / ".last-verify-at"
            stamp.write_text("1000\n")
            self.assertEqual(self.m.stamp_age_seconds(stamp, now=1300.0), 300)

    def test_unparseable_stamp_returns_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            stamp = Path(tmp) / ".last-verify-at"
            stamp.write_text("garbage\n")
            self.assertIsNone(self.m.stamp_age_seconds(stamp, now=1000.0))


class TestAnyCriticalFileStale(unittest.TestCase):
    def setUp(self):
        self.m = _load("render_verify_gate")

    def test_no_critical_files_present_is_not_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _init_git_repo(root)
            self.assertFalse(self.m.any_critical_file_stale(root, critical_files=()))

    def test_changed_critical_file_is_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _init_git_repo(root)
            target = root / "template.html"
            target.write_text("<html></html>")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=root, check=True)
            target.write_text("<html>changed</html>")
            self.assertTrue(
                self.m.any_critical_file_stale(root, critical_files=("template.html",))
            )

    def test_unchanged_critical_file_is_not_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _init_git_repo(root)
            target = root / "template.html"
            target.write_text("<html></html>")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=root, check=True)
            self.assertFalse(
                self.m.any_critical_file_stale(root, critical_files=("template.html",))
            )


class TestMainNeverBlocks(unittest.TestCase):
    """The gate is warn-only — main() must always return 0."""

    def setUp(self):
        self.m = _load("render_verify_gate")

    def test_returns_zero_for_non_commit_command(self):
        import io

        with patch("sys.stdin", io.StringIO('{"tool_input": {"command": "ls"}}')):
            self.assertEqual(self.m.main(), 0)

    def test_returns_zero_even_when_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _init_git_repo(root)
            target = root / "Sources/MarkViewCore/Resources/template.html"
            target.parent.mkdir(parents=True)
            target.write_text("<html></html>")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=root, check=True)
            target.write_text("<html>changed</html>")

            import io

            with (
                patch("os.getcwd", return_value=str(root)),
                patch("pathlib.Path.cwd", return_value=root),
                patch(
                    "sys.stdin",
                    io.StringIO('{"tool_input": {"command": "git commit -m x"}}'),
                ),
            ):
                self.assertEqual(self.m.main(), 0)


# ── Thin wrapper delegation ──────────────────────────────────────────────────


class TestThinWrappers(unittest.TestCase):
    def test_auto_install_sh_delegates_to_python(self):
        wrapper = (SCRIPTS / "auto-install.sh").read_text()
        self.assertIn("auto_install.py", wrapper)
        self.assertIn("exec python3", wrapper)
        self.assertIn("bash-justified", wrapper)

    def test_render_verify_gate_sh_delegates_to_python(self):
        wrapper = (SCRIPTS / "render-verify-gate.sh").read_text()
        self.assertIn("render_verify_gate.py", wrapper)
        self.assertIn("exec python3", wrapper)
        self.assertIn("bash-justified", wrapper)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(__import__("__main__"))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
