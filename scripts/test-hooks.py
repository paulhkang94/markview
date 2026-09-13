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


class TestPrePush(unittest.TestCase):
    """No network, native build, or real sentinel is touched by these fixtures."""

    def setUp(self):
        import json
        from types import SimpleNamespace
        self.json = json
        self.Result = SimpleNamespace
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.module = _load("pre_push")
        self.plan = {"commits": ["a" * 40, "b" * 40], "refs": ["refs/heads/main"]}
        self.calls = []
        self.guard_rc = 0
        self.build_rc = 0
        self.diff_rc = 0
        self.paths = {"a" * 40: "Sources/App.swift\0", "b" * 40: "README.md\0"}

    def runner(self, command, **kwargs):
        self.calls.append((command, kwargs))
        if command[0] == sys.executable:
            return self.Result(returncode=self.guard_rc, stdout=self.json.dumps(self.plan), stderr="")
        if command[0] == "git":
            return self.Result(returncode=self.diff_rc, stdout=self.paths.get(command[-1], ""), stderr="")
        self.assertEqual(command, ["bash", str(self.root / "scripts/bundle.sh"), "--install"])
        return self.Result(returncode=self.build_rc)

    def run_push(self):
        return self.module.pre_push("original Git stdin", self.root, ("origin", "remote-url"), self.runner)

    def sentinel(self, version="1.2.3"):
        path = self.root / (".release-preflight-passed-" + version)
        path.touch()
        return path

    def test_shared_guard_failure_prevents_build_and_preserves_preflight(self):
        sentinel = self.sentinel()
        self.plan["refs"] = ["refs/tags/v1.2.3"]
        self.guard_rc = 1
        self.assertEqual(self.run_push(), 1)
        self.assertEqual(len(self.calls), 1)
        self.assertTrue(sentinel.exists())

    def test_earlier_native_commit_builds_even_when_tip_is_documentation(self):
        self.assertEqual(self.run_push(), 0)
        self.assertEqual(self.calls[0][1]["input"], "original Git stdin")
        self.assertIn("--json", self.calls[0][0])
        self.assertEqual(self.calls[0][0][-2:], ["origin", "remote-url"])
        self.assertEqual(self.calls[-1][0][0], "bash")
        self.assertEqual(sum(c[0][0] == "bash" for c in self.calls), 1)

    def test_docs_only_and_delete_only_pushes_do_not_build(self):
        for plan in [{"commits": ["b" * 40], "refs": ["refs/heads/main"]},
                     {"commits": [], "refs": []}]:
            self.plan = plan
            self.calls.clear()
            self.assertEqual(self.run_push(), 0)
            self.assertFalse(any(c[0][0] == "bash" for c in self.calls))

    def test_all_release_tags_need_preflight_before_any_sentinel_is_consumed(self):
        sentinel = self.sentinel()
        self.plan["refs"] = ["refs/tags/v1.2.3", "refs/tags/v1.2.4"]
        self.assertEqual(self.run_push(), 1)
        self.assertTrue(sentinel.exists())
        self.assertEqual(len(self.calls), 1)

    def test_build_failure_preserves_sentinel_and_success_consumes_it(self):
        sentinel = self.sentinel()
        self.plan["refs"] = ["refs/tags/v1.2.3"]
        self.build_rc = 1
        self.assertEqual(self.run_push(), 1)
        self.assertTrue(sentinel.exists())
        self.build_rc = 0
        self.assertEqual(self.run_push(), 0)
        self.assertFalse(sentinel.exists())

    def test_invalid_plan_and_unreadable_git_changes_block(self):
        self.plan["commits"] = ["--not-a-commit"]
        self.assertEqual(self.run_push(), 1)
        self.plan["commits"] = ["a" * 40]
        self.diff_rc = 1
        self.assertEqual(self.run_push(), 1)
        self.assertFalse(any(c[0][0] == "bash" for c in self.calls))

    def test_release_tag_cannot_escape_sentinel_directory(self):
        self.plan["refs"] = ["refs/tags/v../../bad"]
        self.assertEqual(self.run_push(), 1)
        self.assertEqual(len(self.calls), 1)


class TestPublicDocsPolicy(unittest.TestCase):
    def setUp(self):
        import os
        import shutil
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {key: value for key, value in os.environ.items()
                    if key not in {"GIT_DIR", "GIT_INDEX_FILE", "GIT_WORK_TREE", "GIT_COMMON_DIR"}}
        for name in [".public-docs.json", ".gitignore"]:
            shutil.copyfile(SCRIPTS.parent / name, self.root / name)
        (self.root / "scripts").mkdir()
        shutil.copyfile(SCRIPTS / "public_repo_guard.py", self.root / "scripts/public_repo_guard.py")
        self.git("init", "-q")
        self.git("config", "user.name", "Policy Test")
        self.git("config", "user.email", "contact@paulkang.dev")
        (self.root / "README.md").write_text("Synthetic public documentation\n")
        self.git("add", ".")

    def git(self, *args):
        result = subprocess.run(["git", "-C", str(self.root), *args],
                                capture_output=True, text=True, env=self.env, check=True)
        return result.stdout.strip()

    def checker(self, *args):
        return subprocess.run([sys.executable, str(SCRIPTS / "public_repo_guard.py"),
                               "--repo", str(self.root), *args],
                              capture_output=True, text=True, env=self.env)

    def test_actual_manifest_and_ignore_block_agree(self):
        original = (self.root / ".gitignore").read_bytes()
        result = self.checker("--write-ignore")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / ".gitignore").read_bytes(), original)
        self.assertEqual(self.checker("--docs-only").returncode, 0)

    def test_already_tracked_research_is_checked_even_if_ignored(self):
        path = self.root / "docs/research/unreviewed-fixture.md"
        path.parent.mkdir(parents=True)
        path.write_text("Synthetic unreviewed document\n")
        self.git("add", "-f", "--", "docs/research/unreviewed-fixture.md")
        self.assertEqual(self.checker("--docs-only").returncode, 1)

    def test_real_shared_guard_and_app_wrapper_agree_for_docs_only_push(self):
        message = self.root / "message.txt"
        message.write_text("Synthetic public docs fixture\n")
        self.git("commit", "-q", "-F", str(message))
        tip = self.git("rev-parse", "HEAD")
        module = _load("pre_push")
        stdin = "refs/heads/main " + tip + " refs/heads/main " + "0" * 40 + "\n"
        self.assertEqual(module.pre_push(stdin, self.root), 0)
        self.assertFalse((self.root / "scripts/bundle.sh").exists())

    def test_installed_pre_push_copy_uses_the_worktree_root(self):
        import shutil
        message = self.root / "message.txt"
        message.write_text("Synthetic installed hook fixture\n")
        self.git("commit", "-q", "-F", str(message))
        tip = self.git("rev-parse", "HEAD")
        hook = self.root / ".git/hooks/pre-push"
        shutil.copyfile(SCRIPTS / "pre_push.py", hook)
        stdin = "refs/heads/main " + tip + " refs/heads/main " + "0" * 40 + "\n"
        result = subprocess.run([sys.executable, str(hook)], cwd=self.root,
                                input=stdin, capture_output=True, text=True, env=self.env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_branch_to_tag_push_requires_preflight(self):
        message = self.root / "message.txt"
        message.write_text("Synthetic release boundary fixture\n")
        self.git("commit", "-q", "-F", str(message))
        tip = self.git("rev-parse", "HEAD")
        module = _load("pre_push")
        stdin = "refs/heads/main " + tip + " refs/tags/v1.2.3 " + "0" * 40 + "\n"
        self.assertEqual(module.pre_push(stdin, self.root), 1)

    def test_ci_consumers_use_the_shared_committed_revision_check(self):
        for name in ["ci.yml", "guard.yml"]:
            text = (SCRIPTS.parent / ".github/workflows" / name).read_text()
            self.assertIn("python3 scripts/public_repo_guard.py --docs-only --ref HEAD", text)
            self.assertNotIn("APPROVED=(", text)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(__import__("__main__"))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
