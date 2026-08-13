#!/usr/bin/env python3
"""
Tests for bundle.py (mar-045 migration from scripts/bundle.sh).

Tier 2 behavioral tests — verify step logic, ordering, and output shape
against a fully stubbed subprocess boundary (mod._run) plus a fake tree
tree. No live xcodegen, xcodebuild, swift build, codesign, security, git,
mdfind, or pluginkit calls.

The `TestGoldenCharacterization` class replays the exact marker sequence
captured from a real `bash scripts/bundle.sh --install` run on this
machine BEFORE the migration (S171, 2026-08-13, MarkView v1.7.1 build 344,
exit 0, 36 files in MarkView.app) — the port's output shape is checked
against actual prior behavior, not just intent.

Usage:
    python3 scripts/test-bundle.py
"""

from __future__ import annotations

import importlib.util
import plistlib
import stat
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


def _write_plist(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        plistlib.dump(data, f)


def _write_exec(path: Path, content: str = "#!/bin/sh\n") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


DEV_ID_IDENTITY_OUTPUT = (
    '  1) ABCDEF1234 "Developer ID Application: Paul Kang (TEAMID)"\n'
    "     1 valid identities found\n"
)
AD_HOC_IDENTITY_OUTPUT = "     0 valid identities found\n"


# ── Small helpers ────────────────────────────────────────────────────────────


class TestHelpers(unittest.TestCase):
    def test_parse_args_defaults(self):
        mod = _load("bundle")
        self.assertEqual(mod.parse_args([]), (False, False))

    def test_parse_args_install_and_notarize(self):
        mod = _load("bundle")
        self.assertEqual(mod.parse_args(["--install"]), (True, False))
        self.assertEqual(mod.parse_args(["--notarize"]), (False, True))
        self.assertEqual(mod.parse_args(["--install", "--notarize"]), (True, True))

    def test_parse_args_unknown_option_raises(self):
        mod = _load("bundle")
        with self.assertRaises(mod.BundleError) as cm:
            mod.parse_args(["--bogus"])
        self.assertIn("Unknown option: --bogus", str(cm.exception))
        self.assertIn("Usage: bash scripts/bundle.sh", str(cm.exception))

    def test_detect_signing_identity_developer_id(self):
        mod = _load("bundle")
        mod._run = lambda cmd, cwd=None: (0, DEV_ID_IDENTITY_OUTPUT, "")
        out = []
        identity, flags = mod.detect_signing_identity(out.append)
        self.assertEqual(identity, "Developer ID Application")
        self.assertEqual(flags, ["--timestamp", "--options", "runtime"])
        self.assertIn("Signing identity: Developer ID Application", out)

    def test_detect_signing_identity_ad_hoc_fallback(self):
        mod = _load("bundle")
        mod._run = lambda cmd, cwd=None: (0, AD_HOC_IDENTITY_OUTPUT, "")
        out = []
        identity, flags = mod.detect_signing_identity(out.append)
        self.assertEqual(identity, "-")
        self.assertEqual(flags, [])
        self.assertIn("Signing identity: ad-hoc (Developer ID not found)", out)

    def test_read_version_success_and_failure(self):
        mod = _load("bundle")
        mod._run = lambda cmd, cwd=None: (0, "1.7.1\n", "")
        self.assertEqual(mod.read_version(Path("x.plist")), "1.7.1")
        mod._run = lambda cmd, cwd=None: (1, "", "no such key")
        self.assertEqual(mod.read_version(Path("x.plist")), "unknown")

    def test_grep_errors_matches_error_lines(self):
        mod = _load("bundle")
        log = "note: building\nfoo.swift:12: error: cannot find X\n** BUILD FAILED **\n"
        lines = mod._grep_errors(log)
        self.assertIn("foo.swift:12: error: cannot find X", lines)
        self.assertIn("** BUILD FAILED **", lines)
        self.assertNotIn("note: building", lines)

    def test_grep_errors_falls_back_to_tail(self):
        mod = _load("bundle")
        log = "\n".join(f"line {i}" for i in range(30))
        lines = mod._grep_errors(log)
        self.assertEqual(lines, log.splitlines()[-20:])

    def test_find_maxdepth1_only_top_level(self):
        mod = _load("bundle")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            (tmp / "A.framework").mkdir()
            (tmp / "B.framework").mkdir()
            (tmp / "nested").mkdir()
            (tmp / "nested/C.framework").mkdir()
            (tmp / "D.bundle").mkdir()
            found = mod._find_maxdepth1(tmp, ".framework")
        self.assertEqual([p.name for p in found], ["A.framework", "B.framework"])

    def test_find_frameworks_signables_dylib_needs_exec_bit(self):
        mod = _load("bundle")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            exec_dylib = tmp / "libExec.dylib"
            exec_dylib.write_text("x")
            exec_dylib.chmod(exec_dylib.stat().st_mode | stat.S_IEXEC)
            non_exec_dylib = tmp / "libPlain.dylib"
            non_exec_dylib.write_text("x")
            non_exec_dylib.chmod(0o644)
            found = mod._find_frameworks_signables(tmp)
        names = [p.name for p in found]
        self.assertIn("libExec.dylib", names)
        self.assertNotIn("libPlain.dylib", names)

    def test_find_frameworks_signables_sentry_matches_any_type(self):
        # The bash `-type f -perm +111 -name "*.dylib" -o -name "Sentry"` binds
        # `-o` to the whole first clause: any entry literally named "Sentry"
        # matches regardless of type/exec-bit. Preserved as-is (not a fix).
        mod = _load("bundle")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            sentry_dir = tmp / "Sentry.framework/Versions/A"
            sentry_dir.mkdir(parents=True)
            (sentry_dir / "Sentry").write_text("not executable, not a dylib")
            found = mod._find_frameworks_signables(tmp)
        self.assertIn(sentry_dir / "Sentry", found)


# ── bump_build_number ─────────────────────────────────────────────────────────


class TestBumpBuildNumber(unittest.TestCase):
    def test_bumps_both_plists_when_ql_present(self):
        mod = _load("bundle")
        calls = []

        def fake_run(cmd, cwd=None):
            calls.append(cmd)
            if cmd[0] == "git":
                return 0, "42\n", ""
            return 0, "", ""

        mod._run = fake_run
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            _write_plist(tmp / "Sources/MarkView/Info.plist", {"CFBundleVersion": "1"})
            _write_plist(
                tmp / "Sources/MarkViewQuickLook/Info.plist", {"CFBundleVersion": "1"}
            )
            build = mod.bump_build_number(tmp)
        self.assertEqual(build, "42")
        plutil_calls = [c for c in calls if c[0] == "plutil"]
        self.assertEqual(len(plutil_calls), 2)

    def test_skips_ql_plist_when_absent(self):
        mod = _load("bundle")
        calls = []

        def fake_run(cmd, cwd=None):
            calls.append(cmd)
            if cmd[0] == "git":
                return 0, "7\n", ""
            return 0, "", ""

        mod._run = fake_run
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            _write_plist(tmp / "Sources/MarkView/Info.plist", {"CFBundleVersion": "1"})
            mod.bump_build_number(tmp)
        plutil_calls = [c for c in calls if c[0] == "plutil"]
        self.assertEqual(len(plutil_calls), 1)

    def test_git_failure_falls_back_to_zero(self):
        mod = _load("bundle")
        mod._run = lambda cmd, cwd=None: (
            (1, "", "not a git repo") if cmd[0] == "git" else (0, "", "")
        )
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            _write_plist(tmp / "Sources/MarkView/Info.plist", {"CFBundleVersion": "1"})
            build = mod.bump_build_number(tmp)
        self.assertEqual(build, "0")

    def test_plutil_replace_failure_aborts(self):
        mod = _load("bundle")

        def fake_run(cmd, cwd=None):
            if cmd[0] == "git":
                return 0, "42\n", ""
            if cmd[0] == "plutil":
                return 1, "", "cannot replace key"
            return 0, "", ""

        mod._run = fake_run
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            _write_plist(tmp / "Sources/MarkView/Info.plist", {"CFBundleVersion": "1"})
            with self.assertRaises(mod.BundleError):
                mod.bump_build_number(tmp)


# ── verify_bundle_structure ───────────────────────────────────────────────────


class TestVerifyBundleStructure(unittest.TestCase):
    def _make_app(
        self, tmp: Path, *, with_doctypes: bool = True, with_ql: bool = True
    ) -> Path:
        app_dir = tmp / "MarkView.app"
        _write_exec(app_dir / "Contents/MacOS/MarkView")
        plist_data = {"CFBundleShortVersionString": "9.9.9"}
        if with_doctypes:
            plist_data["CFBundleDocumentTypes"] = [{"CFBundleTypeName": "Markdown"}]
        _write_plist(app_dir / "Contents/Info.plist", plist_data)
        (app_dir / "Contents/PkgInfo").write_text("APPL????")
        if with_ql:
            _write_exec(
                app_dir
                / "Contents/PlugIns/MarkViewQuickLook.appex/Contents/MacOS/MarkViewQuickLook"
            )
        return app_dir

    def test_all_pass_developer_id(self):
        mod = _load("bundle")
        mod._run = lambda cmd, cwd=None: (
            (0, "", "") if cmd[0] in ("plutil", "codesign") else (0, "", "")
        )
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            app_dir = self._make_app(tmp)
            out = []
            valid = mod.verify_bundle_structure(
                app_dir, "Developer ID Application", out.append
            )
        self.assertTrue(valid)
        self.assertIn("=== Bundle verification passed ===", out)
        self.assertIn("  ✓ Quick Look extension exists", out)

    def test_missing_doctypes_fails(self):
        mod = _load("bundle")
        mod._run = lambda cmd, cwd=None: (0, "", "")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            app_dir = self._make_app(tmp, with_doctypes=False)
            out = []
            valid = mod.verify_bundle_structure(app_dir, "-", out.append)
        self.assertFalse(valid)
        self.assertIn("  ✗ Missing document types", out)
        self.assertIn("=== Bundle verification FAILED ===", out)

    def test_missing_ql_extension_is_nonfatal(self):
        mod = _load("bundle")
        mod._run = lambda cmd, cwd=None: (0, "", "")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            app_dir = self._make_app(tmp, with_ql=False)
            out = []
            valid = mod.verify_bundle_structure(app_dir, "-", out.append)
        self.assertTrue(valid)
        self.assertIn("  ⚠ Quick Look extension missing (non-fatal)", out)

    def test_invalid_codesign_developer_id_fails(self):
        mod = _load("bundle")

        def fake_run(cmd, cwd=None):
            if cmd[0] == "codesign":
                return 1, "", "invalid signature"
            return 0, "", ""

        mod._run = fake_run
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            app_dir = self._make_app(tmp)
            out = []
            valid = mod.verify_bundle_structure(
                app_dir, "Developer ID Application", out.append
            )
        self.assertFalse(valid)
        self.assertIn(
            "  ✗ Code signature invalid with Developer ID — bundle will be rejected by Gatekeeper",
            out,
        )

    def test_invalid_codesign_adhoc_is_warning_not_failure(self):
        mod = _load("bundle")

        def fake_run(cmd, cwd=None):
            if cmd[0] == "codesign":
                return 1, "", "ad-hoc, no verify"
            return 0, "", ""

        mod._run = fake_run
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            app_dir = self._make_app(tmp)
            out = []
            valid = mod.verify_bundle_structure(app_dir, "-", out.append)
        self.assertTrue(valid)
        self.assertIn(
            "  ⚠ Ad-hoc signature (expected — no Developer ID cert found)", out
        )


# ── install_bundle ────────────────────────────────────────────────────────────


class TestInstallBundle(unittest.TestCase):
    def test_unregisters_stale_copies_skips_self_and_missing(self):
        mod = _load("bundle")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            app_dir = tmp / "MarkView.app"
            _write_exec(app_dir / "Contents/MacOS/MarkView")
            install_dir = tmp / "Applications/MarkView.app"
            stale = tmp / "stale-copy/MarkView.app"
            stale.mkdir(parents=True)
            missing = tmp / "gone/MarkView.app"  # never created

            calls = []

            def fake_run(cmd, cwd=None):
                prog = Path(str(cmd[0])).name
                calls.append(cmd)
                if prog == "mdfind":
                    body = f"{install_dir}\n{stale}\n{missing}\n"
                    return 0, body, ""
                if prog == "lsregister":
                    return 0, "", ""
                return 0, "", ""

            mod._run = fake_run
            mod.LSREGISTER = Path(__file__)  # any real file, so `.is_file()` is True
            out = []
            mod.install_bundle(app_dir, install_dir, out.append)

            # `LSREGISTER` is stubbed to this test file's own path (just needs
            # `.is_file()` to be True) — match on the "-u" unregister flag
            # rather than the program basename.
            unregister_calls = [c for c in calls if "-u" in c]
            unregistered_paths = [c[-1] for c in unregister_calls]
            self.assertEqual(unregistered_paths, [str(stale)])
            self.assertIn(f"✓ Unregistered stale copy: {stale}", out)
            self.assertTrue(install_dir.is_dir())
            self.assertTrue((install_dir / "Contents/MacOS/MarkView").is_file())

    def test_ql_registration_failure_is_nonfatal_warning(self):
        mod = _load("bundle")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            app_dir = tmp / "MarkView.app"
            _write_exec(
                app_dir
                / "Contents/PlugIns/MarkViewQuickLook.appex/Contents/MacOS/MarkViewQuickLook"
            )
            install_dir = tmp / "Applications/MarkView.app"

            def fake_run(cmd, cwd=None):
                prog = Path(str(cmd[0])).name
                if prog == "pluginkit":
                    return 1, "", "needs Developer ID"
                if prog == "mdfind":
                    return 0, "", ""
                return 0, "", ""

            mod._run = fake_run
            mod.LSREGISTER = Path("/nonexistent/lsregister")
            out = []
            mod.install_bundle(app_dir, install_dir, out.append)
        self.assertIn(
            "⚠ Quick Look extension registration failed "
            "(needs Developer ID for Finder spacebar — use qlmanage -p to test)",
            out,
        )
        self.assertNotIn("✓ Registered with Launch Services", out)


# ── Golden characterization: full run_bundle happy path ─────────────────────

# Captured from a real `bash scripts/bundle.sh --install` run on this machine
# BEFORE the mar-045 migration (S171, 2026-08-13): MarkView v1.7.1 build 344,
# Developer ID signed, exit 0, 36 files under MarkView.app. Ordered subset of
# markers that must still appear, in the same relative order, from the ported
# bundle.py — proves the port matches OBSERVED bash behavior, not just intent.
GOLDEN_MARKERS = [
    "Signing identity: Developer ID Application",
    "=== Building MarkView.app v9.9.9 (build 42) ===",
    "--- Generating Xcode project ---",
    "✓ Xcode project generated",
    "--- Building with xcodebuild ---",
    "✓ xcodebuild complete",
    "✓ App bundle copied to",
    "--- Building MCP server (SPM) ---",
    "✓ MCP server embedded and signed",
    "--- Re-signing nested code for notarization ---",
    "✓ App bundle re-signed",
    "✓ Bundle created at:",
    "--- Verifying bundle structure ---",
    "  ✓ Executable exists",
    "  ✓ Info.plist exists",
    "  ✓ PkgInfo exists",
    "  ✓ Info.plist is valid",
    "  ✓ Document types registered",
    "  ✓ Quick Look extension exists",
    "  ✓ Code signature valid",
    "=== Bundle verification passed ===",
    "--- Installing to /Applications ---",
    "✓ Registered with Launch Services",
    "✓ Quick Look extension registered",
    "✓ Installed to",
]


def _build_fake_release_app(build_products: Path) -> None:
    """Simulates what a real `xcodebuild ... -configuration Release` leaves
    behind, so downstream steps (copy, resign, verify) have real files to
    operate on."""
    _write_exec(build_products / "Contents/MacOS/MarkView")
    _write_plist(
        build_products / "Contents/Info.plist",
        {
            "CFBundleShortVersionString": "9.9.9",
            "CFBundleDocumentTypes": [{"CFBundleTypeName": "Markdown"}],
        },
    )
    (build_products / "Contents/PkgInfo").write_text("APPL????")
    _write_exec(
        build_products
        / "Contents/PlugIns/MarkViewQuickLook.appex/Contents/MacOS/MarkViewQuickLook"
    )
    _write_plist(
        build_products / "Contents/PlugIns/MarkViewQuickLook.appex/Contents/Info.plist",
        {"CFBundleShortVersionString": "9.9.9"},
    )
    sentry_bin = (
        build_products / "Contents/Frameworks/Sentry.framework/Versions/A/Sentry"
    )
    _write_exec(sentry_bin)
    (build_products / "Contents/Resources/MarkView_MarkViewCore.bundle").mkdir(
        parents=True, exist_ok=True
    )


class TestGoldenCharacterization(unittest.TestCase):
    def _make_project(self, tmp: Path) -> None:
        _write_plist(tmp / "Sources/MarkView/Info.plist", {"CFBundleVersion": "1"})
        _write_plist(
            tmp / "Sources/MarkViewQuickLook/Info.plist", {"CFBundleVersion": "1"}
        )
        (tmp / "Sources/MarkView/MarkView.entitlements").parent.mkdir(
            parents=True, exist_ok=True
        )
        (tmp / "Sources/MarkView/MarkView.entitlements").write_text("<plist/>")
        (tmp / "Sources/MarkViewQuickLook/MarkViewQuickLook.entitlements").write_text(
            "<plist/>"
        )

    def _fake_run(self, tmp: Path, install_dir: Path):
        build_products = tmp / "build/Build/Products/Release/MarkView.app"

        def fake_run(cmd, cwd=None):
            prog = Path(str(cmd[0])).name
            if prog == "security":
                return 0, DEV_ID_IDENTITY_OUTPUT, ""
            if prog == "plutil":
                if cmd[1] == "-extract":
                    return 0, "9.9.9\n", ""
                return 0, "", ""
            if prog == "git":
                return 0, "42\n", ""
            if prog == "xcodegen":
                return 0, "⚙️  Generating project...\n", ""
            if prog == "xcodebuild":
                _build_fake_release_app(build_products)
                return 0, "\n** BUILD SUCCEEDED **\n", ""
            if prog == "swift":
                spm_bin = tmp / ".build/release/MarkViewMCPServer"
                _write_exec(spm_bin)
                return 0, "Build of product 'MarkViewMCPServer' complete!\n", ""
            if prog == "codesign":
                return 0, "", ""
            if prog == "mdfind":
                return 0, "", ""
            if prog in ("pkill", "xattr", "lsregister", "pluginkit"):
                return 0, "", ""
            return 0, "", ""

        return fake_run

    def test_run_bundle_install_matches_golden_marker_order(self):
        mod = _load("bundle")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            install_dir = tmp / "Applications/MarkView.app"
            mod._run = self._fake_run(tmp, install_dir)
            mod.LSREGISTER = Path(__file__)  # any real file → `.is_file()` True
            # Never depend on a real xcodegen install — the CI "Verify" job
            # (unlike "Bundle") doesn't install it, so this must be stubbed.
            mod._which = lambda name: "/opt/homebrew/bin/xcodegen"

            out = []
            rc = mod.run_bundle(
                ["--install"], project_dir=tmp, install_dir=install_dir, out=out.append
            )

            self.assertEqual(rc, 0)
            text = "\n".join(out)

            # Every golden marker present...
            for marker in GOLDEN_MARKERS:
                self.assertIn(marker, text, f"missing golden marker: {marker!r}")

            # ...in the same relative order as the real captured bash run.
            positions = [text.index(m) for m in GOLDEN_MARKERS]
            self.assertEqual(positions, sorted(positions))

            # Resulting bundle has the same key structure as the real bundle.
            app_dir = tmp / "MarkView.app"
            for rel in (
                "Contents/MacOS/MarkView",
                "Contents/Info.plist",
                "Contents/PkgInfo",
                "Contents/MacOS/markview-mcp-server",
                "Contents/PlugIns/MarkViewQuickLook.appex/Contents/MacOS/MarkViewQuickLook",
            ):
                self.assertTrue(
                    (app_dir / rel).exists(), f"missing in app bundle: {rel}"
                )
                self.assertTrue(
                    (install_dir / rel).exists(), f"missing in installed copy: {rel}"
                )

    def test_run_bundle_without_install_skips_install_dir(self):
        mod = _load("bundle")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            install_dir = tmp / "Applications/MarkView.app"
            mod._run = self._fake_run(tmp, install_dir)
            mod._which = lambda name: "/opt/homebrew/bin/xcodegen"

            out = []
            rc = mod.run_bundle(
                [], project_dir=tmp, install_dir=install_dir, out=out.append
            )

        self.assertEqual(rc, 0)
        self.assertFalse(install_dir.exists())
        self.assertNotIn("--- Installing to /Applications ---", "\n".join(out))


# ── Failure paths ──────────────────────────────────────────────────────────────


class TestFailurePaths(unittest.TestCase):
    def _make_project(self, tmp: Path) -> None:
        _write_plist(tmp / "Sources/MarkView/Info.plist", {"CFBundleVersion": "1"})

    def test_unknown_argument_raises_before_any_work(self):
        mod = _load("bundle")
        calls = []
        mod._run = lambda cmd, cwd=None: (calls.append(cmd), (0, "", ""))[1]
        with self.assertRaises(mod.BundleError):
            mod.run_bundle(["--bogus"], project_dir=Path("/nonexistent"))
        self.assertEqual(calls, [])  # no subprocess ran — args parsed first

    def test_notarize_without_developer_id_aborts(self):
        mod = _load("bundle")
        mod._run = lambda cmd, cwd=None: (
            (0, AD_HOC_IDENTITY_OUTPUT, "") if cmd[0] == "security" else (0, "", "")
        )
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            with self.assertRaises(mod.BundleError) as cm:
                mod.run_bundle(["--notarize"], project_dir=tmp)
        self.assertIn("--notarize requires Developer ID signing", str(cm.exception))

    def test_xcodegen_missing_aborts(self):
        mod = _load("bundle")
        mod._run = lambda cmd, cwd=None: (
            (0, AD_HOC_IDENTITY_OUTPUT, "") if cmd[0] == "security" else (0, "42\n", "")
        )
        mod._which = lambda name: None
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            with self.assertRaises(mod.BundleError) as cm:
                mod.run_bundle([], project_dir=tmp)
        self.assertIn("xcodegen not found", str(cm.exception))

    def test_xcodebuild_failure_surfaces_error_lines_not_masked(self):
        # The mar-026 fix this port preserves: a masked `| tail -5` pipe used
        # to hide the actual compile error. Assert the real error line reaches
        # the caller via BundleError, not just "BUILD FAILED".
        mod = _load("bundle")

        def fake_run(cmd, cwd=None):
            prog = Path(str(cmd[0])).name
            if prog == "security":
                return 0, AD_HOC_IDENTITY_OUTPUT, ""
            if prog == "git":
                return 0, "42\n", ""
            if prog == "xcodegen":
                return 0, "", ""
            if prog == "xcodebuild":
                return (
                    1,
                    "",
                    "MarkdownRenderer.swift:88: error: cannot find 'Foo'\n** BUILD FAILED **\n",
                )
            return 0, "", ""

        mod._run = fake_run
        mod._which = lambda name: "/opt/homebrew/bin/xcodegen"
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            out = []
            with self.assertRaises(mod.BundleError):
                mod.run_bundle([], project_dir=tmp, out=out.append)
        text = "\n".join(out)
        self.assertIn("MarkdownRenderer.swift:88: error: cannot find 'Foo'", text)
        self.assertIn("** BUILD FAILED **", text)

    def test_verify_failure_blocks_install(self):
        mod = _load("bundle")

        def fake_run(cmd, cwd=None):
            prog = Path(str(cmd[0])).name
            if prog == "security":
                return 0, AD_HOC_IDENTITY_OUTPUT, ""
            if prog == "git":
                return 0, "1\n", ""
            if prog == "plutil" and cmd[1] == "-extract":
                return 0, "9.9.9\n", ""
            if prog == "xcodegen":
                return 0, "", ""
            if prog == "xcodebuild":
                build_products = tmp / "build/Build/Products/Release/MarkView.app"
                _write_exec(build_products / "Contents/MacOS/MarkView")
                # No Info.plist / PkgInfo / doc types → verification fails.
                return 0, "** BUILD SUCCEEDED **\n", ""
            if prog == "swift":
                return 0, "complete\n", ""
            return 0, "", ""

        mod._run = fake_run
        mod._which = lambda name: "/opt/homebrew/bin/xcodegen"
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            self._make_project(tmp)
            install_dir = tmp / "Applications/MarkView.app"
            out = []
            rc = mod.run_bundle(
                ["--install"], project_dir=tmp, install_dir=install_dir, out=out.append
            )
        self.assertEqual(rc, 1)
        self.assertIn("=== Bundle verification FAILED ===", "\n".join(out))
        self.assertFalse(install_dir.exists())  # install never attempted


# ── main() exit-code plumbing ───────────────────────────────────────────────


class TestMain(unittest.TestCase):
    def test_main_exits_with_bundle_error_code(self):
        mod = _load("bundle")
        mod.run_bundle = lambda argv, **kw: (_ for _ in ()).throw(
            mod.BundleError("boom", code=3)
        )
        with (
            patch.object(sys, "argv", ["bundle.py"]),
            patch("sys.stderr", new_callable=StringIO) as err,
        ):
            with self.assertRaises(SystemExit) as cm:
                mod.main()
        self.assertEqual(cm.exception.code, 3)
        self.assertIn("boom", err.getvalue())


# ── Thin wrapper + wiring ────────────────────────────────────────────────────


class TestThinWrapper(unittest.TestCase):
    def test_wrapper_delegates_to_python(self):
        wrapper = (SCRIPTS / "bundle.sh").read_text()
        self.assertIn("bundle.py", wrapper)
        self.assertIn("exec python3", wrapper)
        self.assertIn("bash-justified", wrapper)
        self.assertIn('"$@"', wrapper)


class TestVerifyWiring(unittest.TestCase):
    def test_verify_py_runs_this_suite(self):
        verify_source = (SCRIPTS / "verify.py").read_text()
        self.assertIn("test-bundle.py", verify_source)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(__import__("__main__"))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
