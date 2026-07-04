#!/usr/bin/env python3
"""
Tests for release_preflight.py, check_version_sync.py, and tap_audit.py.

Tier 2 behavioral tests — verify check logic, marker-file contract, and
output/exit-code shape against fixture temp trees. All subprocess and
network boundaries are stubbed: no live gh, git, swift, or HTTP calls.

Usage:
    python3 scripts/test-release-scripts.py
"""

from __future__ import annotations

import contextlib
import importlib.util
import json
import plistlib
import sys
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).parent

ALL_SECRETS = [
    "NOTARIZE_KEY_ID",
    "NOTARIZE_ISSUER_ID",
    "NOTARIZE_API_KEY",
    "DEVELOPER_ID_CERT_BASE64",
    "DEVELOPER_ID_CERT_PASSWORD",
    "APP_PRIVATE_KEY",
]


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _write_plist(path: Path, version: str, build: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        plistlib.dump(
            {"CFBundleShortVersionString": version, "CFBundleVersion": build}, f
        )


# ── check_version_sync ────────────────────────────────────────────────────────


class TestVersionSync(unittest.TestCase):
    def _make_project(
        self,
        tmp: Path,
        *,
        canonical: str = "1.5.0",
        build: str = "42",
        ql_ver: str | None = None,
        ql_build: str | None = None,
        mcp_ver: str | None = None,
        npm_ver: str | None = None,
        server_ver: str | None = None,
        binary_ver: str | None = None,
    ) -> None:
        ql_ver = canonical if ql_ver is None else ql_ver
        ql_build = build if ql_build is None else ql_build
        mcp_ver = canonical if mcp_ver is None else mcp_ver
        npm_ver = canonical if npm_ver is None else npm_ver
        server_ver = npm_ver if server_ver is None else server_ver
        binary_ver = canonical if binary_ver is None else binary_ver

        _write_plist(tmp / "Sources/MarkView/Info.plist", canonical, build)
        _write_plist(tmp / "Sources/MarkViewQuickLook/Info.plist", ql_ver, ql_build)

        mcp_main = tmp / "Sources/MarkViewMCPServer/main.swift"
        mcp_main.parent.mkdir(parents=True, exist_ok=True)
        mcp_main.write_text(
            f'let server = Server(name: "markview", version: "{mcp_ver}")\n'
        )

        npm_dir = tmp / "npm"
        (npm_dir / "scripts").mkdir(parents=True, exist_ok=True)
        (npm_dir / "package.json").write_text(json.dumps({"version": npm_ver}))
        (npm_dir / "server.json").write_text(json.dumps({"version": server_ver}))
        (npm_dir / "scripts/postinstall.js").write_text(
            f'const BINARY_VERSION = "{binary_ver}";\n'
        )

    @contextlib.contextmanager
    def _stubbed(
        self,
        mod,
        tmp: Path,
        *,
        latest_tag: str,
        existing_tags: set[str],
        commits: int = 0,
    ):
        version_tags = [t for t in existing_tags if mod.VERSION_TAG_RE.match(t)]
        with (
            patch.object(mod, "latest_version_tag", new=lambda pd: latest_tag),
            patch.object(mod, "tag_exists", new=lambda pd, tag: tag in existing_tags),
            patch.object(mod, "all_version_tags", new=lambda pd: version_tags),
            patch.object(mod, "commits_since", new=lambda pd, tag: commits),
            patch.object(mod, "INSTALLED_PLIST", tmp / "not-installed.plist"),
            patch("sys.stdout", new_callable=StringIO) as out,
        ):
            yield out

    def test_happy_path_all_in_sync(self):
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            with self._stubbed(
                mod, tmp, latest_tag="1.5.0", existing_tags={"v1.5.0"}
            ) as out:
                rc = mod.run(tmp)
        output = out.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn("Canonical version: 1.5.0 (build 42)", output)
        self.assertIn("✓ Git tag v1.5.0 matches Info.plist 1.5.0", output)
        self.assertIn("✓ All versions in sync", output)
        self.assertNotIn("✗", output)

    def test_quicklook_mismatch_fails(self):
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, ql_ver="1.4.9")
            with self._stubbed(
                mod, tmp, latest_tag="1.5.0", existing_tags={"v1.5.0"}
            ) as out:
                rc = mod.run(tmp)
        output = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn(
            "✗ QuickLook CFBundleShortVersionString: 1.4.9 (expected 1.5.0)", output
        )
        self.assertIn("✗ Version sync failed: 1 mismatches", output)
        self.assertNotIn("✓ All versions in sync", output)

    def test_unreleased_bump_is_warning_not_error(self):
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            # Plist bumped to 1.5.0 but only v1.4.2 tagged; binary still 1.4.2.
            self._make_project(tmp, binary_ver="1.4.2")
            with self._stubbed(
                mod, tmp, latest_tag="1.4.2", existing_tags={"v1.4.2"}
            ) as out:
                rc = mod.run(tmp)
        output = out.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn(
            "⚠ Info.plist is 1.5.0 but no tag v1.5.0 exists yet (unreleased bump",
            output,
        )
        self.assertIn("✓ All versions in sync", output)

    def test_commits_since_tag_warning(self):
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            with self._stubbed(
                mod, tmp, latest_tag="1.5.0", existing_tags={"v1.5.0"}, commits=3
            ) as out:
                rc = mod.run(tmp)
        output = out.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn(
            "⚠ 3 commit(s) since v1.5.0 — consider bumping version before release",
            output,
        )

    def test_binary_version_without_tag_fails(self):
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, binary_ver="1.9.9")
            with self._stubbed(
                mod, tmp, latest_tag="1.5.0", existing_tags={"v1.5.0"}
            ) as out:
                rc = mod.run(tmp)
        output = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn("no tag v1.9.9 — binary download will fail", output)

    def test_unreadable_canonical_plist_exits_1(self):
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)  # empty tree — no Info.plist at all
            with patch("sys.stdout", new_callable=StringIO) as out:
                rc = mod.run(tmp)
        self.assertEqual(rc, 1)
        self.assertIn("✗ Cannot read version from Info.plist", out.getvalue())

    def test_stale_binary_version_fails(self):
        # THE 1.6.0 incident: app released v1.6.0 but postinstall still pins
        # v1.4.0. Old check passed (tag v1.4.0 exists); new check must fail.
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, canonical="1.6.0", binary_ver="1.4.0")
            with self._stubbed(
                mod, tmp, latest_tag="1.6.0", existing_tags={"v1.4.0", "v1.6.0"}
            ) as out:
                rc = mod.run(tmp)
        output = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn(
            "✗ npm/scripts/postinstall.js BINARY_VERSION: 1.4.0 is STALE — "
            "newer release tag v1.6.0 exists",
            output,
        )
        self.assertNotIn("✓ All versions in sync", output)

    def test_binary_version_staleness_sorts_numerically(self):
        # v1.10.0 must beat v1.9.0 — lexicographic sort would invert this.
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, canonical="1.10.0", binary_ver="1.9.0")
            with self._stubbed(
                mod, tmp, latest_tag="1.10.0", existing_tags={"v1.9.0", "v1.10.0"}
            ) as out:
                rc = mod.run(tmp)
        self.assertEqual(rc, 1)
        self.assertIn("BINARY_VERSION: 1.9.0 is STALE", out.getvalue())

    def test_binary_version_mid_release_bump_warns(self):
        # Bump-all commit before tagging: pin == canonical, tag not yet pushed.
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, canonical="1.7.0", binary_ver="1.7.0")
            with self._stubbed(
                mod, tmp, latest_tag="1.6.0", existing_tags={"v1.6.0"}
            ) as out:
                rc = mod.run(tmp)
        output = out.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn(
            "⚠ npm/scripts/postinstall.js BINARY_VERSION: 1.7.0 has no tag yet",
            output,
        )
        self.assertIn("✓ All versions in sync", output)

    def test_stale_npm_package_version_fails(self):
        # npm/package.json left at an older released version than canonical.
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(
                tmp, canonical="1.6.0", npm_ver="1.4.0", binary_ver="1.6.0"
            )
            with self._stubbed(
                mod, tmp, latest_tag="1.6.0", existing_tags={"v1.4.0", "v1.6.0"}
            ) as out:
                rc = mod.run(tmp)
        self.assertEqual(rc, 1)
        self.assertIn("✗ npm/package.json: 1.4.0 is stale", out.getvalue())

    def test_npm_js_only_version_ahead_passes(self):
        # JS-only npm patch: npm ahead of app, no app tag for it — allowed,
        # and BINARY_VERSION stays on the latest released tag.
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(
                tmp, canonical="1.6.0", npm_ver="1.6.2", binary_ver="1.6.0"
            )
            with self._stubbed(
                mod, tmp, latest_tag="1.6.0", existing_tags={"v1.6.0"}
            ) as out:
                rc = mod.run(tmp)
        output = out.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn(
            "✓ npm/package.json: 1.6.2 (JS-only version ahead of app 1.6.0)", output
        )
        self.assertIn("✓ All versions in sync", output)

    def test_expect_tag_all_match_passes(self):
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, canonical="1.7.0")
            with self._stubbed(
                mod, tmp, latest_tag="1.7.0", existing_tags={"v1.7.0"}
            ) as out:
                rc = mod.run(tmp, expect="1.7.0")
        output = out.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn("Strict release mode: every version must equal 1.7.0", output)
        self.assertIn("✓ All versions in sync", output)

    def test_expect_tag_stale_binary_version_fails(self):
        # Release gate replay of 1.6.0: tag v1.6.0 pushed, pin still 1.4.0.
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, canonical="1.6.0", binary_ver="1.4.0")
            with self._stubbed(
                mod, tmp, latest_tag="1.6.0", existing_tags={"v1.4.0", "v1.6.0"}
            ) as out:
                rc = mod.run(tmp, expect="1.6.0")
        output = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn(
            "✗ npm/scripts/postinstall.js BINARY_VERSION: 1.4.0 (expected 1.6.0",
            output,
        )

    def test_expect_tag_canonical_mismatch_fails(self):
        # Tag pushed from a commit whose files were never bumped.
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, canonical="1.6.0")
            with self._stubbed(
                mod, tmp, latest_tag="1.6.0", existing_tags={"v1.6.0"}
            ) as out:
                rc = mod.run(tmp, expect="1.7.0")
        output = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn("✗ Info.plist is 1.6.0 but the release expects 1.7.0", output)

    def test_expect_tag_npm_mismatch_fails(self):
        # In strict mode the JS-only allowance is suspended: npm must equal
        # the release version exactly.
        mod = _load("check_version_sync")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, canonical="1.7.0", npm_ver="1.7.1")
            with self._stubbed(
                mod, tmp, latest_tag="1.7.0", existing_tags={"v1.7.0"}
            ) as out:
                rc = mod.run(tmp, expect="1.7.0")
        self.assertEqual(rc, 1)
        self.assertIn("✗ npm/package.json: 1.7.1 (expected 1.7.0)", out.getvalue())

    def test_version_helpers_numeric_order(self):
        mod = _load("check_version_sync")
        self.assertEqual(
            mod.highest_version_tag(["v1.9.0", "v1.10.0", "v1.2.11"]), "v1.10.0"
        )
        self.assertEqual(mod.highest_version_tag([]), "")
        self.assertEqual(mod._version_key("v1.10.2"), (1, 10, 2))
        self.assertEqual(mod._version_key("1.10.2"), (1, 10, 2))


# ── release_preflight ─────────────────────────────────────────────────────────


class TestReleasePreflight(unittest.TestCase):
    def _make_project(
        self, tmp: Path, version: str = "9.9.9", changelog: bool = True
    ) -> None:
        _write_plist(tmp / "Sources/MarkView/Info.plist", version, "1")
        workflows = tmp / ".github/workflows"
        workflows.mkdir(parents=True, exist_ok=True)
        (workflows / "release.yml").write_text(
            "permissions:\n"
            "  contents: write\n"
            "jobs:\n"
            "  release:\n"
            "    steps:\n"
            "      - name: Build, sign, notarize\n"
            "        env:\n"
            "          NOTARIZE_KEY_ID: ${{ secrets.NOTARIZE_KEY_ID }}\n"
        )
        (tmp / "scripts").mkdir(exist_ok=True)
        (tmp / "scripts/check_version_sync.py").write_text("# stub\n")
        if changelog:
            (tmp / "CHANGELOG.md").write_text(
                f"# Changelog\n\n## v{version}\n\n- Release notes stub\n"
            )

    def _fake_run(
        self,
        *,
        secrets: list[str],
        variables: tuple[str, ...] = ("APP_ID",),
        swift_ok: bool = True,
        dist_ok: bool = True,
        sync_rc: int = 0,
        dirty: bool = False,
        branch: str = "main",
        local_tag: str = "",
        remote_tag: str = "",
        npm_view_out: str = "",
    ):
        def fake_run(cmd, cwd=None):
            prog = Path(str(cmd[0])).name
            if prog == "gh":
                sub = cmd[1]
                if sub == "--version":
                    return 0, "gh version 2.62.0 (2026-01-01)\n", ""
                if sub == "auth":
                    return 0, "", ""
                if sub == "secret":
                    body = "".join(f"{s}\t2026-01-01\n" for s in secrets)
                    return 0, body, ""
                if sub == "variable":
                    body = "".join(f"{v}\tvalue\t2026-01-01\n" for v in variables)
                    return 0, body, ""
                return 1, "", "unexpected gh call"
            if prog == "git":
                sub = cmd[1]
                if sub == "status":
                    return 0, ("?? untracked.txt\n" if dirty else ""), ""
                if sub == "rev-parse":
                    return 0, f"{branch}\n", ""
                if sub == "tag":
                    return 0, (f"{local_tag}\n" if local_tag else ""), ""
                if sub == "ls-remote":
                    body = f"deadbeef\trefs/tags/{remote_tag}\n" if remote_tag else ""
                    return 0, body, ""
                return 1, "", "unexpected git call"
            if prog == "npm":
                if npm_view_out:
                    return 0, f"{npm_view_out}\n", ""
                return 1, "", "npm ERR! 404"
            if prog == "swift":
                if swift_ok:
                    return 0, "Total: 300 passed, 0 failed\n", ""
                return 1, "Total: 298 passed, 2 failed\n", ""
            if any("check_version_sync.py" in str(part) for part in cmd):
                return sync_rc, "", ""
            if prog == "bash":
                if dist_ok:
                    return 0, "Distribution test passed\n", ""
                return 1, "signature invalid\n", ""
            return 0, "", ""

        return fake_run

    def _run_preflight(self, tmp: Path, fake_run, spm_artifacts: Path | None = None):
        mod = _load("release_preflight")
        mod.PROJECT_DIR = tmp
        mod.SPM_ARTIFACTS = spm_artifacts or (tmp / "spm-artifacts-absent")
        mod._run = fake_run
        mod._which = lambda name: "/opt/homebrew/bin/gh"
        with patch("sys.stdout", new_callable=StringIO) as out:
            rc = mod.run_preflight()
        return rc, out.getvalue()

    def test_all_checks_pass_writes_sentinel(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, version="9.9.9")
            rc, output = self._run_preflight(tmp, self._fake_run(secrets=ALL_SECRETS))
            sentinel = tmp / ".release-preflight-passed-9.9.9"
            self.assertEqual(rc, 0)
            self.assertTrue(sentinel.exists())
        self.assertIn("Pre-flight passed. Safe to tag.", output)
        self.assertIn("Sentinel written: .release-preflight-passed-9.9.9", output)
        self.assertIn("Next: git tag v9.9.9 && git push origin v9.9.9", output)
        self.assertIn("[OK] Secret: APP_PRIVATE_KEY", output)
        self.assertIn("[OK] Variable: APP_ID (tap-update GitHub App)", output)
        self.assertNotIn("[FAIL]", output)

    def test_missing_secret_fails_without_sentinel(self):
        secrets = [s for s in ALL_SECRETS if s != "APP_PRIVATE_KEY"]
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, version="9.9.9")
            rc, output = self._run_preflight(tmp, self._fake_run(secrets=secrets))
            self.assertEqual(rc, 1)
            self.assertFalse((tmp / ".release-preflight-passed-9.9.9").exists())
        self.assertIn(
            "[FAIL] Missing secret: APP_PRIVATE_KEY "
            "(set via: gh secret set APP_PRIVATE_KEY)",
            output,
        )
        self.assertIn("1 check(s) failed. Fix before tagging.", output)

    def test_missing_app_id_variable_fails(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            rc, output = self._run_preflight(
                tmp, self._fake_run(secrets=ALL_SECRETS, variables=())
            )
        self.assertEqual(rc, 1)
        self.assertIn(
            "[FAIL] Missing repo variable: APP_ID (set via: gh variable set APP_ID)",
            output,
        )

    def test_failing_distribution_test_blocks(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            rc, output = self._run_preflight(
                tmp, self._fake_run(secrets=ALL_SECRETS, dist_ok=False)
            )
        self.assertEqual(rc, 1)
        self.assertIn(
            "[FAIL] Distribution path test FAILED — fix signing/bundle before tagging",
            output,
        )

    def test_failing_version_sync_blocks(self):
        # Inverts the old warning-only contract: WARN-level sync is what let
        # 1.6.0 tag with a stale BINARY_VERSION. Sync failure now blocks.
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            rc, output = self._run_preflight(
                tmp, self._fake_run(secrets=ALL_SECRETS, sync_rc=1)
            )
            self.assertFalse((tmp / ".release-preflight-passed-9.9.9").exists())
        self.assertEqual(rc, 1)
        self.assertIn("[FAIL] Version sync FAILED", output)
        self.assertIn("--expect-tag v9.9.9", output)

    def test_version_sync_called_in_strict_mode(self):
        calls: list[list[str]] = []
        inner = self._fake_run(secrets=ALL_SECRETS)

        def recording(cmd, cwd=None):
            calls.append([str(part) for part in cmd])
            return inner(cmd, cwd)

        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, version="9.9.9")
            rc, _ = self._run_preflight(tmp, recording)
        self.assertEqual(rc, 0)
        sync_calls = [c for c in calls if any("check_version_sync.py" in p for p in c)]
        self.assertEqual(len(sync_calls), 1)
        self.assertIn("--expect-tag", sync_calls[0])
        self.assertIn("v9.9.9", sync_calls[0])

    def test_dirty_tree_fails(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            rc, output = self._run_preflight(
                tmp, self._fake_run(secrets=ALL_SECRETS, dirty=True)
            )
        self.assertEqual(rc, 1)
        self.assertIn(
            "[FAIL] Working tree dirty — commit or stash before tagging", output
        )

    def test_wrong_branch_fails(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            rc, output = self._run_preflight(
                tmp, self._fake_run(secrets=ALL_SECRETS, branch="release-hardening")
            )
        self.assertEqual(rc, 1)
        self.assertIn(
            "[FAIL] On branch 'release-hardening' — releases are tagged from main only",
            output,
        )

    def test_existing_tag_fails(self):
        for kwargs in ({"local_tag": "v9.9.9"}, {"remote_tag": "v9.9.9"}):
            with self.subTest(**kwargs):
                with tempfile.TemporaryDirectory() as td:
                    tmp = Path(td)
                    self._make_project(tmp)
                    rc, output = self._run_preflight(
                        tmp, self._fake_run(secrets=ALL_SECRETS, **kwargs)
                    )
                self.assertEqual(rc, 1)
                self.assertIn(
                    "[FAIL] Tag v9.9.9 already exists — bump the version first",
                    output,
                )

    def test_missing_changelog_entry_fails(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp, changelog=False)
            rc, output = self._run_preflight(tmp, self._fake_run(secrets=ALL_SECRETS))
        self.assertEqual(rc, 1)
        self.assertIn("[FAIL] CHANGELOG.md has no '## v9.9.9' entry", output)

    def test_npm_version_collision_fails(self):
        # mcp-server-markview@9.9.9 already on the registry: npm-publish.yml
        # would skip the publish and npm users keep the previous binary pin.
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            rc, output = self._run_preflight(
                tmp, self._fake_run(secrets=ALL_SECRETS, npm_view_out="9.9.9")
            )
        self.assertEqual(rc, 1)
        self.assertIn("[FAIL] mcp-server-markview@9.9.9 is already published", output)

    def test_stale_spm_cache_is_cleared(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            spm = tmp / "spm-artifacts"
            spm.mkdir()
            (spm / "stale-artifact").write_text("stale")
            rc, output = self._run_preflight(
                tmp, self._fake_run(secrets=ALL_SECRETS), spm_artifacts=spm
            )
            self.assertEqual(rc, 0)
            self.assertFalse(spm.exists())
        self.assertIn("Stale SPM binary artifact cache found", output)
        self.assertIn(
            "[OK] SPM artifact cache cleared (prevents exit code 74 on release CI)",
            output,
        )


# ── tap_audit ─────────────────────────────────────────────────────────────────

FAKE_CASK = 'cask "markview" do\n  version "1.4.2"\n  sha256 "0f5a3d"\nend\n'


class TestTapAudit(unittest.TestCase):
    def _run_main(self, mod) -> tuple[int, str]:
        with patch("sys.stdout", new_callable=StringIO) as out:
            with self.assertRaises(SystemExit) as cm:
                mod.main()
        return cm.exception.code, out.getvalue()

    def test_extract_tap_version(self):
        mod = _load("tap_audit")
        self.assertEqual(mod.extract_tap_version(FAKE_CASK), "1.4.2")
        self.assertEqual(mod.extract_tap_version(""), "")
        self.assertEqual(mod.extract_tap_version("no version here"), "")

    def test_match_exits_zero(self):
        mod = _load("tap_audit")
        with (
            patch.object(mod, "latest_release_tag", new=lambda: "1.4.2"),
            patch.object(mod, "fetch_cask", new=lambda: FAKE_CASK),
        ):
            code, output = self._run_main(mod)
        self.assertEqual(code, 0)
        self.assertIn("✓ Homebrew tap v1.4.2 matches latest release v1.4.2", output)

    def test_mismatch_exits_one_with_fix_command(self):
        mod = _load("tap_audit")
        with (
            patch.object(mod, "latest_release_tag", new=lambda: "1.5.0"),
            patch.object(mod, "fetch_cask", new=lambda: FAKE_CASK),
        ):
            code, output = self._run_main(mod)
        self.assertEqual(code, 1)
        self.assertIn("MISMATCH: Homebrew tap v1.4.2 ≠ latest release v1.5.0", output)
        self.assertIn(
            "gh workflow run tap-update.yml --repo paulhkang94/markview "
            "--field tag_name=v1.5.0",
            output,
        )

    def test_unfetchable_cask_exits_one(self):
        mod = _load("tap_audit")
        with (
            patch.object(mod, "latest_release_tag", new=lambda: "1.5.0"),
            patch.object(mod, "fetch_cask", new=lambda: ""),
        ):
            code, output = self._run_main(mod)
        self.assertEqual(code, 1)
        self.assertIn("ERROR: could not fetch tap cask from", output)


# ── npm_publish_gate ──────────────────────────────────────────────────────────


class TestNpmPublishGate(unittest.TestCase):
    REPO = "paulhkang94/markview"

    def _make_npm(self, tmp: Path, *, npm_ver: str, binary_ver: str) -> None:
        (tmp / "npm/scripts").mkdir(parents=True, exist_ok=True)
        (tmp / "npm/package.json").write_text(json.dumps({"version": npm_ver}))
        (tmp / "npm/scripts/postinstall.js").write_text(
            f'const BINARY_VERSION = "{binary_ver}";\n'
        )

    @contextlib.contextmanager
    def _stubbed(
        self,
        mod,
        *,
        remote_tags: set[str] | None = None,
        tags_after_wait: set[str] | None = None,
        releases: dict[str, list[str]] | None = None,
        latest: str = "",
    ):
        """Stub the GitHub + sleep boundaries.

        `remote_tags` are visible immediately; `tags_after_wait` become
        visible only after the first _sleep call (models the coordinated-
        release race where the tag push trails the main push).
        """
        remote_tags = remote_tags or set()
        tags_after_wait = tags_after_wait or set()
        releases = releases or {}
        sleeps: list[float] = []
        visible = set(remote_tags)

        def fake_sleep(seconds: float) -> None:
            sleeps.append(seconds)
            visible.update(tags_after_wait)

        with (
            patch.object(mod, "remote_tag_exists", new=lambda r, t: t in visible),
            patch.object(mod, "release_assets", new=lambda r, t: releases.get(t)),
            patch.object(mod, "latest_release_tag", new=lambda r: latest),
            patch.object(mod, "_sleep", new=fake_sleep),
            patch("sys.stdout", new_callable=StringIO) as out,
        ):
            yield out, sleeps

    def test_coordinated_release_with_asset_passes(self):
        mod = _load("npm_publish_gate")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_npm(tmp, npm_ver="1.7.0", binary_ver="1.7.0")
            with self._stubbed(
                mod,
                remote_tags={"v1.7.0"},
                releases={"v1.7.0": ["MarkView-1.7.0.zip", "MarkView-1.7.0.tar.gz"]},
            ) as (out, sleeps):
                rc = mod.run_gate(tmp, self.REPO)
        output = out.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn("✓ BINARY_VERSION matches the npm version (1.7.0)", output)
        self.assertIn("✓ Release v1.7.0 carries MarkView-1.7.0.tar.gz", output)
        self.assertIn("✓ npm publish gate passed", output)
        self.assertEqual(sleeps, [])  # pin == npm version: no tag wait needed

    def test_release_still_building_fails_with_retry_hint(self):
        # Coordinated release: main push triggered npm-publish before
        # release.yml finished uploading artifacts.
        mod = _load("npm_publish_gate")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_npm(tmp, npm_ver="1.7.0", binary_ver="1.7.0")
            with self._stubbed(mod, remote_tags={"v1.7.0"}, releases={}) as (
                out,
                _,
            ):
                rc = mod.run_gate(tmp, self.REPO)
        output = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn("✗ GitHub release v1.7.0 does not exist (yet)", output)
        self.assertIn("re-runs automatically", output)

    def test_stale_pin_with_app_tag_fails(self):
        # THE 1.6.0 replay at the publish boundary: npm 1.6.0 about to
        # publish while postinstall still pins 1.4.0 and tag v1.6.0 exists.
        mod = _load("npm_publish_gate")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_npm(tmp, npm_ver="1.6.0", binary_ver="1.4.0")
            with self._stubbed(
                mod,
                remote_tags={"v1.4.0", "v1.6.0"},
                releases={"v1.4.0": ["MarkView-1.4.0.tar.gz"]},
                latest="v1.6.0",
            ) as (out, _):
                rc = mod.run_gate(tmp, self.REPO)
        output = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn("✗ STALE BINARY_VERSION: app tag v1.6.0 exists", output)
        self.assertIn("the 1.6.0 incident", output)

    def test_stale_pin_catches_tag_arriving_during_wait(self):
        # Race shape: main push fires the workflow, tag push lands seconds
        # later. The gate must wait for the tag instead of concluding
        # "JS-only" and letting the stale pin publish immutably.
        mod = _load("npm_publish_gate")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_npm(tmp, npm_ver="1.7.0", binary_ver="1.6.0")
            with self._stubbed(
                mod,
                tags_after_wait={"v1.7.0"},
                releases={"v1.6.0": ["MarkView-1.6.0.tar.gz"]},
                latest="v1.6.0",
            ) as (out, sleeps):
                rc = mod.run_gate(tmp, self.REPO, tag_wait_seconds=60)
        output = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertGreaterEqual(len(sleeps), 1)
        self.assertIn("✗ STALE BINARY_VERSION: app tag v1.7.0 exists", output)

    def test_js_only_publish_with_current_pin_passes(self):
        # npm 1.6.2 (no app tag), pin 1.6.0 == latest release: legitimate.
        mod = _load("npm_publish_gate")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_npm(tmp, npm_ver="1.6.2", binary_ver="1.6.0")
            with self._stubbed(
                mod,
                releases={"v1.6.0": ["MarkView-1.6.0.tar.gz"]},
                latest="v1.6.0",
            ) as (out, sleeps):
                rc = mod.run_gate(tmp, self.REPO, tag_wait_seconds=30)
        output = out.getvalue()
        self.assertEqual(rc, 0)
        self.assertGreaterEqual(len(sleeps), 1)  # waited before deciding JS-only
        self.assertIn("treating as a JS-only npm publish", output)
        self.assertIn("✓ BINARY_VERSION 1.6.0 is the latest published release", output)

    def test_js_only_publish_with_stale_pin_fails(self):
        mod = _load("npm_publish_gate")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_npm(tmp, npm_ver="1.6.2", binary_ver="1.4.0")
            with self._stubbed(
                mod,
                releases={"v1.4.0": ["MarkView-1.4.0.tar.gz"]},
                latest="v1.6.0",
            ) as (out, _):
                rc = mod.run_gate(tmp, self.REPO, tag_wait_seconds=30)
        output = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn(
            "✗ STALE BINARY_VERSION: 1.4.0 but the latest published release is v1.6.0",
            output,
        )

    def test_release_missing_tarball_asset_fails(self):
        mod = _load("npm_publish_gate")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_npm(tmp, npm_ver="1.7.0", binary_ver="1.7.0")
            with self._stubbed(
                mod,
                remote_tags={"v1.7.0"},
                releases={"v1.7.0": ["MarkView-1.7.0.zip"]},
            ) as (out, _):
                rc = mod.run_gate(tmp, self.REPO)
        output = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn("has no MarkView-1.7.0.tar.gz asset", output)

    def test_unreadable_inputs_fail(self):
        mod = _load("npm_publish_gate")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)  # no npm/ tree at all
            with self._stubbed(mod) as (out, _):
                rc = mod.run_gate(tmp, self.REPO)
        self.assertEqual(rc, 1)
        self.assertIn("✗ Cannot read version from npm/package.json", out.getvalue())


# ── Thin wrappers + wiring ────────────────────────────────────────────────────


class TestThinWrappers(unittest.TestCase):
    WRAPPERS = {
        "check-version-sync.sh": "check_version_sync.py",
        "release-preflight.sh": "release_preflight.py",
        "tap-audit.sh": "tap_audit.py",
    }

    def test_wrappers_delegate_to_python(self):
        for wrapper_name, module_name in self.WRAPPERS.items():
            with self.subTest(wrapper=wrapper_name):
                wrapper = (SCRIPTS / wrapper_name).read_text()
                self.assertIn(module_name, wrapper)
                self.assertIn("exec python3", wrapper)
                self.assertIn("bash-justified", wrapper)

    def test_wrappers_pass_args(self):
        for wrapper_name in self.WRAPPERS:
            with self.subTest(wrapper=wrapper_name):
                wrapper = (SCRIPTS / wrapper_name).read_text()
                self.assertIn('"$@"', wrapper)


class TestVerifyWiring(unittest.TestCase):
    def test_verify_py_runs_this_suite(self):
        # Wire test (paired with the behavioral tests above): verify.py's
        # Script Tests stage must invoke this file or it is dead code.
        verify_source = (SCRIPTS / "verify.py").read_text()
        self.assertIn("test-release-scripts.py", verify_source)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(__import__("__main__"))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
