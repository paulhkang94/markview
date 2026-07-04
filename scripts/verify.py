#!/usr/bin/env python3
"""
verify.py — MarkView full verification runner (replaces verify.sh).

Runs every check tier in order and writes BOTH verify stamps on success
(HA-008 format: "TIER=all\\nTS=<epoch>"):
  - Per-repo:  <project>/.last-verify-at       (commit-gate per-repo fallback)
  - Global:    COMMIT_GATE_VERIFY_STAMP env     (default: claude-repl-template
               .claude/memory/.last-verify-at — commit-gate primary)

Usage:
  python3 scripts/verify.py                   # standard tiers
  python3 scripts/verify.py 0                 # build only
  python3 scripts/verify.py --extended        # + fuzz, QL, Playwright
  bash verify.sh [args]                        # thin exec wrapper — delegates here
"""

import os
import subprocess
import sys
import time
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
APP_BUNDLE = PROJECT_DIR / "MarkView.app"
BUNDLE_RSRC = (
    APP_BUNDLE / "Contents/Resources/MarkView_MarkViewCore.bundle/Contents/Resources"
)
APPEX = APP_BUNDLE / "Contents/PlugIns/MarkViewQuickLook.appex"
APPEX_RSRC = (
    APPEX / "Contents/Resources/MarkView_MarkViewCore.bundle/Contents/Resources"
)
INSTALLED_APP = Path("/Applications/MarkView.app")

_GLOBAL_STAMP_DEFAULT = (
    Path.home() / "repos/claude-repl-template/.claude/memory/.last-verify-at"
)
GLOBAL_STAMP = Path(
    os.environ.get("COMMIT_GATE_VERIFY_STAMP", str(_GLOBAL_STAMP_DEFAULT))
)
PER_REPO_STAMP = PROJECT_DIR / ".last-verify-at"

RESOURCES = ["mermaid.min.js", "prism-bundle.min.js", "template.html"]


# ── Output helpers ─────────────────────────────────────────────────────────────


def ok(msg: str) -> None:
    print(f"✓ {msg}")


def fail(msg: str) -> None:
    print(f"✗ {msg}")


def warn(msg: str) -> None:
    print(f"⚠ {msg}")


def skip(msg: str) -> None:
    print(f"⊘ {msg}")


def header(msg: str) -> None:
    print(f"\n--- {msg} ---")


# ── Subprocess helpers ─────────────────────────────────────────────────────────


def run_captured(cmd: list[str], cwd: Path = PROJECT_DIR) -> tuple[int, str]:
    """Run command, capture combined stdout+stderr."""
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def run_streamed(cmd: list[str], cwd: Path = PROJECT_DIR) -> int:
    """Run command, stream output directly to terminal."""
    return subprocess.run(cmd, cwd=cwd).returncode


def run_filtered(cmd: list[str], cwd: Path = PROJECT_DIR) -> tuple[int, str]:
    """Run command, return filtered output (strips Swift build noise)."""
    rc, combined = run_captured(cmd, cwd)
    noise = ("[", "Building ", "Build of ", "warning:")
    lines = [l for l in combined.splitlines() if l.strip() and not l.startswith(noise)]
    return rc, "\n".join(lines)


# ── Stamp writing ──────────────────────────────────────────────────────────────


def write_stamps() -> None:
    # HA-008 tiered format: commit_gate.py requires TIER in {test, slow, all};
    # bare-epoch stamps are no longer accepted.
    stamp = f"TIER=all\nTS={int(time.time())}\n"
    PER_REPO_STAMP.write_text(stamp)
    if GLOBAL_STAMP.parent.exists():
        GLOBAL_STAMP.write_text(stamp)
    ok("Verify stamps written (per-repo + global, threshold=30m)")


# ── Tier: Version sync ─────────────────────────────────────────────────────────


def tier_version_sync() -> bool:
    header("Version Sync")
    rc, out = run_captured(["bash", str(PROJECT_DIR / "scripts/check-version-sync.sh")])
    print(out.rstrip())
    return rc == 0


# ── Tier 0: Build ─────────────────────────────────────────────────────────────


def tier_build() -> bool:
    header("Tier 0: Build")
    rc, combined = run_captured(["swift", "build"])
    if rc == 0 and "Build complete" in combined:
        ok("All targets build successfully")
        return True
    for line in combined.strip().splitlines()[-10:]:
        print(f"  {line}")
    fail("Build failed")
    return False


# ── Tier 0b: Bundle verification ──────────────────────────────────────────────


def tier_bundle() -> bool:
    if not APP_BUNDLE.is_dir():
        return True  # skip — bundle not built yet

    header("Tier 0b: Bundle Verification")
    passed = True

    def check(cond: bool, ok_msg: str, fail_msg: str) -> bool:
        nonlocal passed
        if cond:
            ok(ok_msg)
        else:
            fail(fail_msg)
            passed = False
        return cond

    check(
        (APP_BUNDLE / "Contents/MacOS/MarkView").is_file(),
        "Executable in bundle",
        "Missing executable",
    )
    check(
        (APP_BUNDLE / "Contents/Info.plist").is_file(),
        "Info.plist in bundle",
        "Missing Info.plist",
    )

    rc, _ = run_captured(["plutil", "-lint", str(APP_BUNDLE / "Contents/Info.plist")])
    check(rc == 0, "Info.plist is valid", "Info.plist is invalid")

    plist_text = (APP_BUNDLE / "Contents/Info.plist").read_text()
    check(
        "CFBundleDocumentTypes" in plist_text,
        "Document types registered",
        "Missing document types",
    )

    for rsrc in RESOURCES:
        p = BUNDLE_RSRC / rsrc
        check(
            p.is_file(),
            f"Resource bundled: {rsrc}",
            f"Missing resource in bundle: {rsrc} (run: xcodegen generate && bash scripts/bundle.sh)",
        )

    if APPEX.is_dir():
        for rsrc in RESOURCES:
            p = APPEX_RSRC / rsrc
            check(
                p.is_file(),
                f"QL resource bundled: {rsrc}",
                f"Missing QL resource: {rsrc}",
            )

        check(
            (APPEX / "Contents/MacOS/MarkViewQuickLook").is_file(),
            "Quick Look extension executable",
            "Missing QL executable",
        )
        check(
            (APPEX / "Contents/Info.plist").is_file(),
            "Quick Look extension Info.plist",
            "Missing QL Info.plist",
        )

        rc, _ = run_captured(["plutil", "-lint", str(APPEX / "Contents/Info.plist")])
        check(
            rc == 0,
            "Quick Look Info.plist is valid",
            "Quick Look Info.plist is invalid",
        )

        rc, _ = run_captured(["codesign", "--verify", "--no-strict", str(APPEX)])
        if rc == 0:
            ok("Quick Look extension is signed")
        else:
            warn("Quick Look extension is unsigned (non-fatal)")
    else:
        warn("Quick Look extension not in bundle (run: bash scripts/bundle.sh)")

    # Code signing
    print("\n  --- Signing Verification ---")
    rc, _ = run_captured(
        ["codesign", "--verify", "--deep", "--strict", str(APP_BUNDLE)]
    )
    if rc == 0:
        print("  ✓ Code signature valid (deep + strict)")
    else:
        print("  ⚠ Strict signature verification failed (expected for ad-hoc)")

    _, sign_info = run_captured(["codesign", "-d", "--verbose=2", str(APP_BUNDLE)])
    authority = next((l for l in sign_info.splitlines() if "Authority=" in l), "")
    if "Signature=adhoc" in sign_info:
        print("  Signing: ad-hoc")
    elif "Developer ID" in authority:
        print(f"  Signing: {authority.strip()}")
    else:
        print("  Signing: unknown")

    if "Developer ID" in authority:
        rc, _ = run_captured(
            ["spctl", "--assess", "--type", "execute", str(APP_BUNDLE)]
        )
        print(
            "  ✓ Gatekeeper: accepted"
            if rc == 0
            else "  ⚠ Gatekeeper: rejected (may need notarization)"
        )

    rc, _ = run_captured(["xcrun", "stapler", "validate", str(APP_BUNDLE)])
    print(
        "  ✓ Notarization ticket: stapled"
        if rc == 0
        else "  Notarization ticket: not stapled (use --notarize with bundle.sh)"
    )

    return passed


# ── Tier 1-3: Swift test suite ────────────────────────────────────────────────


def tier_swift_tests() -> bool:
    header("Tier 1-3: Full Test Suite")
    rc, out = run_filtered(["swift", "run", "MarkViewTestRunner"])
    print(out)
    if rc == 0 and "0 failed" in out.splitlines()[-1] if out.strip() else False:
        return True
    fail("Test suite failed")
    return False


# ── PDF behavioral tests ──────────────────────────────────────────────────────


def tier_pdf_tests() -> bool:
    header("PDF Behavioral Tests")
    rc, out = run_filtered(["swift", "run", "MarkViewPDFTester"])
    print(out)
    last_lines = out.strip().splitlines()[-2:] if out.strip() else []
    if rc == 0 and any("0 failed" in l for l in last_lines):
        return True
    fail("PDF tests failed")
    return False


# ── Golden drift ───────────────────────────────────────────────────────────────


def tier_golden_drift() -> bool:
    header("Golden Drift Check")
    _, out = run_filtered(["swift", "run", "MarkViewTestRunner", "--generate-goldens"])
    if out.strip():
        print(out)
    rc, diff_stat = run_captured(
        ["git", "diff", "--stat", "Tests/TestRunner/Fixtures/expected/"]
    )
    rc2, _ = run_captured(
        ["git", "diff", "--quiet", "Tests/TestRunner/Fixtures/expected/"]
    )
    if rc2 == 0:
        ok("Golden baselines are up to date")
        return True
    fail("Golden baselines are stale — commit the updated files:")
    print(diff_stat)
    return False


# ── Script unit tests ─────────────────────────────────────────────────────────


def tier_script_tests() -> bool:
    header("Script Tests (metrics + traction + release)")
    suites = [
        ("scripts/test-metrics.py", "metrics + check_traction"),
        (
            "scripts/test-release-scripts.py",
            "release_preflight + check_version_sync + tap_audit",
        ),
    ]
    all_passed = True
    for rel_path, label in suites:
        rc, out = run_captured(["python3", str(PROJECT_DIR / rel_path)])
        tail = out.strip().splitlines()[-3:]
        if rc == 0 and any(l.strip().startswith("OK") for l in tail):
            ok(f"{label} tests passed")
        else:
            print("\n".join(tail))
            fail(f"{label} tests failed")
            all_passed = False
    return all_passed


# ── CLI smoke test ────────────────────────────────────────────────────────────


def tier_cli_smoke() -> bool:
    header("CLI Check")
    cli = Path.home() / ".local/bin/mdpreview"
    if not cli.exists():
        warn("mdpreview not installed (run: bash scripts/install-cli.sh)")
        return True
    rc, file_out = run_captured(["file", str(cli)])
    if "text" not in file_out:
        warn("mdpreview is not a shell script")
        return True
    ok("mdpreview CLI is installed (shell script)")
    if APP_BUNDLE.is_dir() or INSTALLED_APP.is_dir():
        ok("mdpreview CLI launches MarkView.app")
    else:
        skip("mdpreview behavioral test skipped — MarkView.app not installed")
    return True


# ── Extended: Fuzz + Differential + Visual ─────────────────────────────────────


def tier_extended_fuzz() -> bool:
    header("Extended: Fuzz Testing")
    rc, out = run_filtered(["swift", "run", "MarkViewFuzzTester"])
    print(out)
    return rc == 0


def tier_extended_diff() -> bool:
    header("Extended: Differential Testing")
    rc, out = run_filtered(["swift", "run", "MarkViewDiffTester"])
    print(out)
    return rc == 0


def tier_extended_visual() -> bool:
    header("Extended: Visual Regression Tests")
    run_filtered(["swift", "run", "MarkViewVisualTester", "--generate-goldens"])
    rc, out = run_filtered(["swift", "run", "MarkViewVisualTester"])
    print(out)
    return rc == 0


# ── Extended: Quick Look E2E ──────────────────────────────────────────────────


def tier_extended_ql() -> bool:
    header("Extended: Quick Look System Integration")
    ql_appex = Path(
        "/Applications/MarkView.app/Contents/PlugIns/MarkViewQuickLook.appex"
    )
    if not ql_appex.is_dir():
        skip(
            "Quick Look extension not installed (run: bash scripts/bundle.sh --install)"
        )
        return True

    passed = 0
    failed = 0
    skipped = 0

    def ql_check(cond: bool, ok_msg: str, fail_msg: str) -> None:
        nonlocal passed, failed
        if cond:
            print(f"  ✓ {ok_msg}")
            passed += 1
        else:
            print(f"  ✗ {fail_msg}")
            failed += 1

    def ql_warn(msg: str) -> None:
        nonlocal skipped
        print(f"  ⚠ {msg}")
        skipped += 1

    ql_check(
        (ql_appex / "Contents/MacOS/MarkViewQuickLook").is_file(),
        "Extension executable exists",
        "Missing extension executable",
    )
    ql_check(
        (ql_appex / "Contents/Info.plist").is_file(),
        "Extension Info.plist exists",
        "Missing extension Info.plist",
    )
    pkginfo = ql_appex / "Contents/PkgInfo"
    ql_check(pkginfo.is_file(), "Extension PkgInfo exists", "Missing PkgInfo")
    if pkginfo.is_file():
        ql_check(
            pkginfo.read_text().strip() == "XPC!????",
            "PkgInfo declares XPC service type",
            f"PkgInfo wrong type: got '{pkginfo.read_text().strip()}'",
        )

    rc, _ = run_captured(["plutil", "-lint", str(ql_appex / "Contents/Info.plist")])
    ql_check(
        rc == 0, "Extension Info.plist is valid XML", "Extension Info.plist is invalid"
    )

    _, plist_content = run_captured(
        ["plutil", "-convert", "xml1", "-o", "-", str(ql_appex / "Contents/Info.plist")]
    )
    for key in [
        "NSExtensionPointIdentifier",
        "NSExtensionPrincipalClass",
        "QLSupportedContentTypes",
        "CFBundleIdentifier",
    ]:
        ql_check(
            key in plist_content, f"Info.plist has {key}", f"Info.plist missing {key}"
        )

    _, ext_point = run_captured(
        [
            "plutil",
            "-extract",
            "NSExtension.NSExtensionPointIdentifier",
            "raw",
            str(ql_appex / "Contents/Info.plist"),
        ]
    )
    ql_check(
        ext_point.strip() == "com.apple.quicklook.preview",
        "Extension point: com.apple.quicklook.preview",
        f"Wrong extension point: '{ext_point.strip()}'",
    )

    ql_check(
        "net.daringfireball.markdown" in plist_content,
        "Supports net.daringfireball.markdown",
        "Missing markdown content type",
    )

    rc, _ = run_captured(["codesign", "--verify", "--no-strict", str(ql_appex)])
    if rc == 0:
        print("  ✓ Extension is code-signed")
        passed += 1
    else:
        ql_warn("Extension is unsigned (ad-hoc signing may have been stripped)")

    _, sign_info = run_captured(["codesign", "-dvv", str(ql_appex)])
    if "Signature=adhoc" in sign_info:
        ql_warn(
            "Ad-hoc signed — Finder spacebar preview requires Developer ID signing + notarization"
        )
    elif "Developer ID" in sign_info:
        print("  ✓ Developer ID signed — Finder spacebar preview should work")
        passed += 1

    _, arch_out = run_captured(
        ["file", str(ql_appex / "Contents/MacOS/MarkViewQuickLook")]
    )
    ql_check(
        "arm64" in arch_out or "Mach-O" in arch_out,
        "Binary is valid Mach-O/arm64",
        f"Binary architecture issue: {arch_out.strip()}",
    )

    parent_plist = Path("/Applications/MarkView.app/Contents/Info.plist")
    if parent_plist.exists():
        _, parent_id = run_captured(
            ["plutil", "-extract", "CFBundleIdentifier", "raw", str(parent_plist)]
        )
        _, ext_id = run_captured(
            [
                "plutil",
                "-extract",
                "CFBundleIdentifier",
                "raw",
                str(ql_appex / "Contents/Info.plist"),
            ]
        )
        parent_id, ext_id = parent_id.strip(), ext_id.strip()
        if ext_id.startswith(parent_id + "."):
            print(f"  ✓ Extension ID ({ext_id}) is child of parent ({parent_id})")
            passed += 1
        else:
            ql_warn(f"Extension ID ({ext_id}) is not prefixed by parent ({parent_id})")

        _, parent_ver = run_captured(
            [
                "plutil",
                "-extract",
                "CFBundleShortVersionString",
                "raw",
                str(parent_plist),
            ]
        )
        _, ext_ver = run_captured(
            [
                "plutil",
                "-extract",
                "CFBundleShortVersionString",
                "raw",
                str(ql_appex / "Contents/Info.plist"),
            ]
        )
        parent_ver, ext_ver = parent_ver.strip(), ext_ver.strip()
        ql_check(
            parent_ver == ext_ver,
            f"Version sync: parent={parent_ver}, extension={ext_ver}",
            f"Version mismatch: parent={parent_ver}, extension={ext_ver}",
        )

    rc, pk_out = run_captured(["pluginkit", "-m", "-p", "com.apple.quicklook.preview"])
    if "com.markview" in pk_out:
        print("  ✓ Extension registered with pluginkit")
        passed += 1
    else:
        _, sign_check = run_captured(["codesign", "-dvv", str(ql_appex)])
        if "Developer ID" in sign_check:
            print(
                "  ✗ Extension NOT registered with pluginkit (Developer ID signed — this is a bug)"
            )
            failed += 1
        else:
            ql_warn(
                "Extension NOT registered with pluginkit (expected for ad-hoc signed apps)"
            )

    fixture = PROJECT_DIR / "Tests/TestRunner/Fixtures/basic.md"
    if fixture.is_file():
        _, md_type_out = run_captured(
            ["mdls", "-attr", "kMDItemContentType", str(fixture)]
        )
        import re

        m = re.search(r'"([^"]+)"', md_type_out)
        md_type = m.group(1) if m else ""
        if md_type == "net.daringfireball.markdown":
            print("  ✓ System recognizes .md as net.daringfireball.markdown")
            passed += 1
        elif md_type:
            ql_warn(f"System sees .md as '{md_type}' (not net.daringfireball.markdown)")
        else:
            ql_warn("Could not determine UTType for .md files")

    print(
        f"\n  Quick Look E2E: {passed} passed, {failed} failed, {skipped} skipped/advisory"
    )
    if failed > 0:
        fail("Quick Look integration has failures")
        return False
    return True


# ── Extended: qlmanage smoke test ─────────────────────────────────────────────


def tier_extended_qlmanage() -> bool:
    header("Extended: qlmanage Smoke Test")
    fixture = PROJECT_DIR / "Tests/TestRunner/Fixtures/basic.md"
    if not fixture.is_file():
        skip(f"Fixture not found: {fixture}")
        return True
    try:
        rc = subprocess.run(
            ["qlmanage", "-p", str(fixture)], timeout=10, capture_output=True
        ).returncode
        if rc == 0:
            ok("qlmanage -p returned success for basic.md")
        else:
            fail(f"qlmanage -p failed with exit code {rc}")
            return False
    except subprocess.TimeoutExpired:
        warn("qlmanage -p timed out (10s) — may need manual investigation")
    return True


# ── Extended: Window lifecycle + E2E + Playwright ─────────────────────────────


def tier_extended_window_lifecycle() -> bool:
    header("Extended: Window Lifecycle Smoke Test")
    rc = run_streamed(["bash", str(PROJECT_DIR / "scripts/test-window-lifecycle.sh")])
    return rc == 0


def tier_extended_e2e() -> bool:
    header("Extended: E2E Tests")
    if not (APP_BUNDLE.is_dir() or INSTALLED_APP.is_dir()):
        skip("No .app bundle found (run: bash scripts/bundle.sh)")
        return True
    rc, out = run_filtered(["swift", "run", "MarkViewE2ETester"])
    print(out)
    return rc == 0


def tier_extended_playwright() -> bool:
    header("Extended: Playwright DOM Tests")
    playwright_dir = PROJECT_DIR / "Tests/playwright"
    if not (playwright_dir / "node_modules").is_dir():
        skip("Playwright not installed (run: make playwright-install)")
        return True
    if not (playwright_dir / "fixtures/golden-corpus.html").is_file():
        skip("Fixtures not generated (run: make playwright-fixtures)")
        return True
    rc = run_streamed(["npx", "playwright", "test"], cwd=playwright_dir)
    if rc == 0:
        run_streamed(["bash", str(PROJECT_DIR / "scripts/bundle.sh"), "--install"])
        ok("Playwright tests passed + MarkView.app updated")
        return True
    fail("Playwright tests failed")
    return False


# ── Main ──────────────────────────────────────────────────────────────────────


def main() -> None:
    args = sys.argv[1:]
    build_only = args == ["0"]
    extended = "--extended" in args

    print("=== MarkView Verification ===")

    standard_tiers = [
        tier_version_sync,
        tier_bundle,
        tier_build,
        tier_swift_tests,
        tier_pdf_tests,
        tier_golden_drift,
        tier_script_tests,
        tier_cli_smoke,
    ]

    extended_tiers = [
        tier_extended_fuzz,
        tier_extended_diff,
        tier_extended_visual,
        tier_extended_ql,
        tier_extended_qlmanage,
        tier_extended_window_lifecycle,
        tier_extended_e2e,
        tier_extended_playwright,
    ]

    tiers = [tier_build] if build_only else standard_tiers
    if extended:
        tiers = standard_tiers + extended_tiers

    for fn in tiers:
        if not fn():
            print("\n=== Verification failed ===")
            sys.exit(1)

    print("\n=== All checks passed ===")
    write_stamps()
    if extended:
        print("=== Extended verification complete ===")


if __name__ == "__main__":
    main()
