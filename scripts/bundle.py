#!/usr/bin/env python3
"""
bundle.py — Build .app bundle using xcodebuild (XcodeGen project).

Usage:
    python3 scripts/bundle.py [--install] [--notarize] [--force]
    bash scripts/bundle.sh [--install] [--notarize] [--force]   (thin exec wrapper)

Prerequisites: brew install xcodegen && xcodegen generate

mar-045: ported from scripts/bundle.sh (293 lines, 28 conditionals) —
maintainability migration, not a behavior change. Golden characterization
of the bash script's real output (log, exit code, resulting bundle file
tree, build number, codesign identity) was captured before porting; see
scripts/test-bundle.py for the behavioral + regression tests replaying
those fixtures, and the mar-026 log-to-file fix (surface xcodebuild/
swift-build root causes instead of a masked `| tail -5` pipe) that this
port preserves.

mar-048: `--install` refuses (unless `--force`) when a Dock tile is pinned
to an ephemeral output path (the `build/` tree or the repo-root
`MarkView.app` — both deleted by dev_cleanup.py), so a Dock tile pointing
into either silently breaks. The check is read-only (`defaults export`,
never `defaults write`) — it never mutates the Dock. The matched roots
come from dev_cleanup.static_targets() so the two scripts cannot drift
out of sync about what counts as ephemeral.

Every external command runs through `_run()` so tests can stub the
subprocess boundary without invoking a real xcodebuild/swift/codesign.
"""

from __future__ import annotations

import plistlib
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dev_cleanup import static_targets  # noqa: E402

PROJECT_DIR = Path(__file__).resolve().parent.parent

APP_NAME = "MarkView"
BUNDLE_ID = "com.markview.app"
MCP_NAME = "MarkViewMCPServer"
MCP_BIN_NAME = "markview-mcp-server"
QL_NAME = "MarkViewQuickLook"

LSREGISTER = Path(
    "/System/Library/Frameworks/CoreServices.framework"
    "/Frameworks/LaunchServices.framework/Support/lsregister"
)


class BundleError(Exception):
    """Raised to abort the bundle — mirrors bash `set -e` aborting on an
    unguarded command failure. `code` is the process exit code to use."""

    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code


# ── Subprocess boundary (module-level so tests can stub — never call real
#    xcodebuild/swift/codesign/git/plutil/security/mdfind/pluginkit) ──────────


def _run(cmd: list[str], cwd: Path | None = None) -> tuple[int, str, str]:
    """Run a command; return (returncode, stdout, stderr). Never raises."""
    try:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    except FileNotFoundError as exc:
        return 127, "", str(exc)
    return result.returncode, result.stdout, result.stderr


def _which(name: str) -> str | None:
    return shutil.which(name)


def _run_or_abort(cmd: list[str], cwd: Path | None = None) -> tuple[str, str]:
    """Run cmd; abort (BundleError) on nonzero exit — mirrors an unguarded
    bash statement under `set -e`."""
    rc, out, err = _run(cmd, cwd=cwd)
    if rc != 0:
        raise BundleError((out + err).strip() or f"command failed: {cmd}", code=rc or 1)
    return out, err


def _copy_tree(src: Path, dst: Path) -> None:
    """Mirrors `cp -R src dst`; aborts (BundleError) on failure like an
    unguarded bash statement under `set -e`."""
    try:
        shutil.copytree(src, dst, symlinks=True)
    except OSError as exc:
        raise BundleError(f"cp -R {src} {dst} failed: {exc}") from exc


def _remove_tree(path: Path) -> None:
    """Mirrors `rm -rf path` (no-op if missing, matching -f)."""
    try:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        elif path.exists() or path.is_symlink():
            path.unlink()
    except OSError as exc:
        raise BundleError(f"rm -rf {path} failed: {exc}") from exc


def _copy_file(src: Path, dst: Path) -> None:
    """Mirrors `cp src dst`; aborts (BundleError) on failure."""
    try:
        shutil.copy2(src, dst)
    except OSError as exc:
        raise BundleError(f"cp {src} {dst} failed: {exc}") from exc


# ── Small helpers ───────────────────────────────────────────────────────────


def _grep_errors(log_text: str, limit: int = 20) -> list[str]:
    """Lines matching `(^|: )error:|BUILD FAILED` (mirrors grep -m20 -E),
    falling back to the last 20 lines (mirrors `|| tail -20`)."""
    import re

    pattern = re.compile(r"(^error:|: error:|BUILD FAILED)")
    matches = [line for line in log_text.splitlines() if pattern.search(line)]
    if matches:
        return matches[:limit]
    return log_text.splitlines()[-20:]


def _find_maxdepth1(directory: Path, suffix: str) -> list[Path]:
    """Entries directly under `directory` whose name ends with `suffix`
    (mirrors `find DIR -name "*SUFFIX" -maxdepth 1`), sorted for determinism."""
    if not directory.is_dir():
        return []
    return sorted(p for p in directory.iterdir() if p.name.endswith(suffix))


def _find_frameworks_signables(directory: Path) -> list[Path]:
    """Mirrors `find DIR -type f -perm +111 -name "*.dylib" -o -name "Sentry"`
    recursively: an entry matches if (file AND any-exec-bit AND *.dylib) OR
    (name == "Sentry", any type). The `-o` binds to the whole first clause,
    not just `-name "*.dylib"` — preserved as-is (faithful port, not a fix)."""
    if not directory.is_dir():
        return []
    matches = []
    for p in sorted(directory.rglob("*")):
        is_exec_dylib = p.is_file() and p.name.endswith(".dylib") and (p.stat().st_mode & 0o111)
        if is_exec_dylib or p.name == "Sentry":
            matches.append(p)
    return matches


# ── Argument parsing ────────────────────────────────────────────────────────


def parse_args(argv: list[str]) -> tuple[bool, bool, bool]:
    """Returns (do_install, do_notarize, do_force). Raises BundleError on an
    unknown option, matching bash's `Unknown option: X` + usage + exit 1."""
    do_install = False
    do_notarize = False
    do_force = False
    for arg in argv:
        if arg == "--install":
            do_install = True
        elif arg == "--notarize":
            do_notarize = True
        elif arg == "--force":
            do_force = True
        else:
            raise BundleError(
                f"Unknown option: {arg}\n"
                "Usage: bash scripts/bundle.sh [--install] [--notarize] [--force]"
            )
    return do_install, do_notarize, do_force


# ── Dock tile safety (mar-048) ──────────────────────────────────────────────


def _decode_dock_file_url(url: str) -> Path | None:
    """Decode a Dock tile's `file://` URL (mirrors
    `tile-data.file-data._CFURLString`) into a filesystem path."""
    if not url or not url.startswith("file://"):
        return None
    return Path(unquote(urlparse(url).path))


def read_dock_persistent_apps() -> list[dict]:
    """Read Dock app tiles via `defaults export com.apple.dock -`. Read-only —
    never calls `defaults write` or otherwise mutates the Dock. Returns []
    (never raises) if the export fails or doesn't parse, so callers degrade
    to "nothing to warn about" rather than aborting the whole bundle build."""
    rc, stdout, _ = _run(["defaults", "export", "com.apple.dock", "-"])
    if rc != 0 or not stdout:
        return []
    try:
        data = plistlib.loads(stdout.encode("utf-8"))
    except (ValueError, plistlib.InvalidFileException):
        return []
    apps = data.get("persistent-apps", [])
    return apps if isinstance(apps, list) else []


def find_dock_tiles_pointing_at_ephemeral_output(project_dir: Path) -> list[str]:
    """Return the file:// paths (decoded) of any pinned Dock tile that lives
    inside one of dev_cleanup.static_targets(project_dir) — the `build/`
    xcodebuild output tree and the repo-root `MarkView.app`, both ephemeral
    outputs that dev_cleanup.py deletes. A Dock tile pinned to either breaks
    (shows a generic icon) once cleaned; the installed app under
    /Applications is the stable target."""
    roots = [root.resolve() for root in static_targets(project_dir)]
    hits: list[str] = []
    for tile in read_dock_persistent_apps():
        file_data = tile.get("tile-data", {}).get("file-data", {})
        url = file_data.get("_CFURLString")
        path = _decode_dock_file_url(url) if isinstance(url, str) else None
        if path is None:
            continue
        resolved = path.resolve()
        if any(resolved == root or root in resolved.parents for root in roots):
            hits.append(str(path))
    return hits


def check_dock_not_pointing_at_ephemeral_output(project_dir: Path, force: bool, out=print) -> None:
    """`--install` guard: refuse (unless `--force`) when a Dock tile is
    pinned to an ephemeral output path (`build/` or the repo-root
    `MarkView.app`). Read-only — never mutates the Dock."""
    hits = find_dock_tiles_pointing_at_ephemeral_output(project_dir)
    if not hits:
        return
    if force:
        out("⚠ Dock tile(s) pinned to an ephemeral output path (continuing: --force):")
        for hit in hits:
            out(f"  {hit}")
        return
    lines = [
        "ERROR: Dock has a tile pinned to an ephemeral output path (build/ or "
        f"{APP_NAME}.app) — it will break (show a generic icon) once cleaned:",
        *(f"  {hit}" for hit in hits),
        f"Re-pin the Dock tile to the installed app (/Applications/{APP_NAME}.app), "
        "or pass --force to skip this check.",
    ]
    raise BundleError("\n".join(lines))


# ── Signing identity ────────────────────────────────────────────────────────


def detect_signing_identity(out=print) -> tuple[str, list[str]]:
    """Returns (identity, codesign_extra_flags). Auto-detects Developer ID,
    falls back to ad-hoc."""
    rc, stdout, _ = _run(["security", "find-identity", "-v"])
    if rc == 0 and "Developer ID Application" in stdout:
        out("Signing identity: Developer ID Application")
        return "Developer ID Application", ["--timestamp", "--options", "runtime"]
    out("Signing identity: ad-hoc (Developer ID not found)")
    return "-", []


# ── Version / build number ──────────────────────────────────────────────────


def read_version(plist: Path) -> str:
    rc, stdout, _ = _run(["plutil", "-extract", "CFBundleShortVersionString", "raw", str(plist)])
    return stdout.strip() if rc == 0 else "unknown"


def bump_build_number(project_dir: Path) -> str:
    """Set CFBundleVersion to the git commit count on both app + QL plists.
    Always monotonically increasing — Tier 0 guardrail so the installed app
    always shows a unique build number per commit."""
    rc, stdout, _ = _run(["git", "rev-list", "--count", "HEAD"], cwd=project_dir)
    git_build = stdout.strip() if rc == 0 else "0"

    plist = project_dir / "Sources/MarkView/Info.plist"
    _run_or_abort(["plutil", "-replace", "CFBundleVersion", "-string", git_build, str(plist)])

    ql_plist = project_dir / "Sources/MarkViewQuickLook/Info.plist"
    if ql_plist.is_file():
        _run_or_abort(
            [
                "plutil",
                "-replace",
                "CFBundleVersion",
                "-string",
                git_build,
                str(ql_plist),
            ]
        )
    return git_build


# ── Step 1: xcodegen ─────────────────────────────────────────────────────────


def xcodegen_generate(project_dir: Path, out=print) -> None:
    """Always regenerate .xcodeproj from project.yml — xcodeproj references
    individual files, so skipping regeneration silently omits new resources
    (e.g. mermaid.min.js) from the build."""
    out("--- Generating Xcode project ---")
    if not _which("xcodegen"):
        raise BundleError("ERROR: xcodegen not found. Install with: brew install xcodegen")
    _run_or_abort(
        [
            "xcodegen",
            "generate",
            "--spec",
            str(project_dir / "project.yml"),
            "--project",
            str(project_dir),
        ]
    )
    out("✓ Xcode project generated")


# ── Step 2: xcodebuild ───────────────────────────────────────────────────────


def build_with_xcodebuild(project_dir: Path, app_name: str, out=print) -> Path:
    """Build the app + extension with xcodebuild. Logs to file instead of
    piping through `tail -5` (mar-026): the pipe showed only the last 5
    lines on failure, hiding the actual compile error. Returns the log path."""
    out("--- Building with xcodebuild ---")
    build_dir = project_dir / "build"
    build_dir.mkdir(parents=True, exist_ok=True)
    log_path = build_dir / "xcodebuild.log"

    rc, stdout, stderr = _run(
        [
            "xcodebuild",
            "-project",
            str(project_dir / f"{app_name}.xcodeproj"),
            "-scheme",
            app_name,
            "-configuration",
            "Release",
            "-derivedDataPath",
            str(build_dir),
            "CODE_SIGN_IDENTITY=-",
            "CODE_SIGN_STYLE=Manual",
            "ONLY_ACTIVE_ARCH=NO",
        ],
        cwd=project_dir,
    )
    log_text = stdout + stderr
    log_path.write_text(log_text)

    if rc != 0:
        out("ERROR: xcodebuild failed - error lines:")
        for line in _grep_errors(log_text):
            out(line)
        out(f"Full log: {log_path}")
        raise BundleError("xcodebuild failed", code=1)

    for line in log_text.splitlines()[-5:]:
        out(line)
    out("✓ xcodebuild complete")
    return log_path


# ── Step 3: copy built app ──────────────────────────────────────────────────


def copy_built_app(project_dir: Path, app_name: str, app_dir: Path, out=print) -> None:
    build_products = project_dir / "build/Build/Products/Release"
    built_app = build_products / f"{app_name}.app"
    if not built_app.is_dir():
        out(f"ERROR: Built app not found at {built_app}")
        out("Checking build directory...")
        for p in sorted((project_dir / "build").rglob("*.app")):
            out(str(p))
        raise BundleError(f"Built app not found at {built_app}")

    _remove_tree(app_dir)
    _copy_tree(built_app, app_dir)
    out(f"✓ App bundle copied to {app_dir}")


# ── Step 4: build + embed MCP server ────────────────────────────────────────


def build_and_embed_mcp(
    project_dir: Path,
    app_dir: Path,
    sign_identity: str,
    sign_flags: list[str],
    out=print,
) -> None:
    out("--- Building MCP server (SPM) ---")
    build_dir = project_dir / "build"
    build_dir.mkdir(parents=True, exist_ok=True)
    mcp_log = build_dir / "mcp-build.log"

    rc, stdout, stderr = _run(
        ["swift", "build", "-c", "release", "--product", MCP_NAME], cwd=project_dir
    )
    log_text = stdout + stderr
    mcp_log.write_text(log_text)

    if rc != 0:
        out(f"ERROR: swift build ({MCP_NAME}) failed - error lines:")
        for line in _grep_errors(log_text):
            out(line)
        out(f"Full log: {mcp_log}")
        raise BundleError(f"swift build ({MCP_NAME}) failed", code=1)

    for line in log_text.splitlines()[-3:]:
        out(line)

    spm_bin = project_dir / ".build/release" / MCP_NAME
    if spm_bin.is_file():
        dest = app_dir / "Contents/MacOS" / MCP_BIN_NAME
        _copy_file(spm_bin, dest)
        rc, _, _ = _run(_codesign_cmd(sign_identity, sign_flags, [], dest))
        if rc == 0:
            out("✓ MCP server embedded and signed")
        else:
            out("✓ MCP server embedded (unsigned)")
    else:
        out(
            "⚠ MCP server binary not found — skipping "
            f"(build with: swift build -c release --product {MCP_NAME})"
        )


# ── codesign helper ──────────────────────────────────────────────────────────


def _codesign_cmd(
    sign_identity: str,
    sign_flags: list[str],
    entitlements_flags: list[str],
    target: Path,
) -> list[str]:
    return [
        "codesign",
        "-s",
        sign_identity,
        "-f",
        *sign_flags,
        *entitlements_flags,
        str(target),
    ]


def _resign(sign_identity: str, sign_flags: list[str], target: Path, label: str, out=print) -> None:
    """Non-fatal re-sign (bash: `codesign ... 2>/dev/null && echo ok || true`)."""
    rc, _, _ = _run(_codesign_cmd(sign_identity, sign_flags, [], target))
    if rc == 0:
        out(f"  ✓ Re-signed: {label}")


# ── Step 5: re-sign nested code ─────────────────────────────────────────────


def resign_nested_code(
    app_dir: Path,
    sign_identity: str,
    sign_flags: list[str],
    entitlements_ql: Path,
    out=print,
) -> None:
    """Apple rejects notarization if any nested binary lacks a secure
    timestamp. xcodebuild signs the QL extension but may not use
    --timestamp. SPM frameworks (Sentry) come pre-signed without our
    timestamp."""
    out("--- Re-signing nested code for notarization ---")
    frameworks_dir = app_dir / "Contents/Frameworks"

    for binary in _find_frameworks_signables(frameworks_dir):
        _resign(sign_identity, sign_flags, binary, binary.name, out)

    for fw in _find_maxdepth1(frameworks_dir, ".framework"):
        _resign(sign_identity, sign_flags, fw, fw.name, out)

    resources_dir = app_dir / "Contents/Resources"
    for bundle in _find_maxdepth1(resources_dir, ".bundle"):
        _resign(sign_identity, sign_flags, bundle, bundle.name, out)

    # Re-sign main executable — xcodebuild may sign it ad-hoc when
    # CODE_SIGN_STYLE=Manual even when CODE_SIGN_IDENTITY is Developer ID.
    # Gatekeeper rejects "Developer ID outer + ad-hoc inner main executable".
    main_bin = app_dir / "Contents/MacOS" / APP_NAME
    if main_bin.is_file():
        _resign(sign_identity, sign_flags, main_bin, f"{APP_NAME} (main executable)", out)

    # Re-sign Quick Look extension with entitlements + timestamp.
    ql_appex = app_dir / "Contents/PlugIns" / f"{QL_NAME}.appex"
    if ql_appex.is_dir():
        ql_pkginfo = ql_appex / "Contents/PkgInfo"
        if not ql_pkginfo.is_file():
            # macOS expects a PkgInfo for XPC/app-extension bundles
            # ("XPC!" package type) — xcodebuild omits it for app extensions.
            ql_pkginfo.write_bytes(b"XPC!????")
            out(f"  ✓ Generated PkgInfo for {QL_NAME}.appex")

        entitlements_flags = (
            ["--entitlements", str(entitlements_ql)] if entitlements_ql.is_file() else []
        )
        rc, _, _ = _run(_codesign_cmd(sign_identity, sign_flags, entitlements_flags, ql_appex))
        if rc == 0:
            out(f"  ✓ Re-signed: {QL_NAME}.appex")


# ── Step 6: re-sign outer app bundle ────────────────────────────────────────


def resign_outer_bundle(
    app_dir: Path,
    sign_identity: str,
    sign_flags: list[str],
    entitlements_app: Path,
    out=print,
) -> None:
    entitlements_flags = (
        ["--entitlements", str(entitlements_app)] if entitlements_app.is_file() else []
    )
    rc, _, _ = _run(_codesign_cmd(sign_identity, sign_flags, entitlements_flags, app_dir))
    if rc == 0:
        out("✓ App bundle re-signed")
    else:
        out("✓ App bundle (unsigned)")


# ── Step 6 (verification) ────────────────────────────────────────────────────


def verify_bundle_structure(app_dir: Path, sign_identity: str, out=print) -> bool:
    out("")
    out("--- Verifying bundle structure ---")
    valid = True

    def check(cond: bool, ok_msg: str, fail_msg: str) -> None:
        nonlocal valid
        if cond:
            out(f"  ✓ {ok_msg}")
        else:
            out(f"  ✗ {fail_msg}")
            valid = False

    check(
        (app_dir / "Contents/MacOS" / APP_NAME).is_file(),
        "Executable exists",
        "Missing executable",
    )
    check(
        (app_dir / "Contents/Info.plist").is_file(),
        "Info.plist exists",
        "Missing Info.plist",
    )
    check((app_dir / "Contents/PkgInfo").is_file(), "PkgInfo exists", "Missing PkgInfo")

    info_plist = app_dir / "Contents/Info.plist"
    rc, _, _ = _run(["plutil", "-lint", str(info_plist)])
    check(rc == 0, "Info.plist is valid", "Info.plist is invalid")

    try:
        plist_text = info_plist.read_text()
    except OSError:
        plist_text = ""
    check(
        "CFBundleDocumentTypes" in plist_text,
        "Document types registered",
        "Missing document types",
    )

    ql_appex_exe = app_dir / "Contents/PlugIns" / f"{QL_NAME}.appex/Contents/MacOS" / QL_NAME
    if ql_appex_exe.is_file():
        out("  ✓ Quick Look extension exists")
    else:
        out("  ⚠ Quick Look extension missing (non-fatal)")

    # Code signature — hard failure for Developer ID builds, warning for ad-hoc.
    rc, _, _ = _run(["codesign", "--verify", "--deep", "--strict", str(app_dir)])
    if rc == 0:
        out("  ✓ Code signature valid")
    elif sign_identity == "-":
        out("  ⚠ Ad-hoc signature (expected — no Developer ID cert found)")
    else:
        out("  ✗ Code signature invalid with Developer ID — bundle will be rejected by Gatekeeper")
        valid = False

    out("")
    if valid:
        out("=== Bundle verification passed ===")
    else:
        out("=== Bundle verification FAILED ===")
    return valid


# ── Step 7: install ──────────────────────────────────────────────────────────


def install_bundle(app_dir: Path, install_dir: Path, out=print) -> None:
    out("")
    out("--- Installing to /Applications ---")

    _run(["pkill", "-x", APP_NAME])
    import time

    time.sleep(1)

    if LSREGISTER.is_file():
        rc, stdout, _ = _run(["mdfind", f"kMDItemCFBundleIdentifier == '{BUNDLE_ID}'"])
        for stale_path in stdout.splitlines() if rc == 0 else []:
            if stale_path and stale_path != str(install_dir) and Path(stale_path).is_dir():
                _run([str(LSREGISTER), "-u", stale_path])
                out(f"✓ Unregistered stale copy: {stale_path}")

    _remove_tree(install_dir)
    _copy_tree(app_dir, install_dir)

    # Strip quarantine for all local installs — notarization only applies to
    # downloads (Homebrew, GitHub Releases). Local bundle.py --install is trusted.
    _run(["xattr", "-dr", "com.apple.quarantine", str(install_dir)])

    if LSREGISTER.is_file():
        _run_or_abort([str(LSREGISTER), "-f", str(install_dir)])
        out("✓ Registered with Launch Services")

    ql_installed = install_dir / "Contents/PlugIns" / f"{QL_NAME}.appex"
    if ql_installed.is_dir():
        rc, _, _ = _run(["pluginkit", "-a", str(ql_installed)])
        if rc == 0:
            out("✓ Quick Look extension registered")
        else:
            out(
                "⚠ Quick Look extension registration failed "
                "(needs Developer ID for Finder spacebar — use qlmanage -p to test)"
            )

    out("")
    out(f"✓ Installed to {install_dir}")
    out("Done! Right-click any .md file → Open With → MarkView")
    out("Test Quick Look: qlmanage -p /path/to/file.md")


# ── Step 8: notarize ─────────────────────────────────────────────────────────


def notarize_bundle(project_dir: Path, target_app: Path) -> None:
    _run_or_abort(["bash", str(project_dir / "scripts/notarize.sh"), str(target_app)])


# ── Orchestration ────────────────────────────────────────────────────────────


def run_bundle(
    argv: list[str],
    project_dir: Path = PROJECT_DIR,
    install_dir: Path | None = None,
    out=print,
) -> int:
    do_install, do_notarize, do_force = parse_args(argv)

    if do_install:
        check_dock_not_pointing_at_ephemeral_output(project_dir, do_force, out)

    app_dir = project_dir / f"{APP_NAME}.app"
    if install_dir is None:
        install_dir = Path(f"/Applications/{APP_NAME}.app")
    entitlements_app = project_dir / "Sources/MarkView/MarkView.entitlements"
    entitlements_ql = project_dir / "Sources/MarkViewQuickLook/MarkViewQuickLook.entitlements"

    sign_identity, sign_flags = detect_signing_identity(out)
    if do_notarize and sign_identity == "-":
        raise BundleError("ERROR: --notarize requires Developer ID signing")

    plist = project_dir / "Sources/MarkView/Info.plist"
    version = read_version(plist)
    build = bump_build_number(project_dir)
    out(f"=== Building {APP_NAME}.app v{version} (build {build}) ===")

    xcodegen_generate(project_dir, out)
    build_with_xcodebuild(project_dir, APP_NAME, out)
    copy_built_app(project_dir, APP_NAME, app_dir, out)
    build_and_embed_mcp(project_dir, app_dir, sign_identity, sign_flags, out)
    resign_nested_code(app_dir, sign_identity, sign_flags, entitlements_ql, out)
    resign_outer_bundle(app_dir, sign_identity, sign_flags, entitlements_app, out)

    out("")
    out(f"✓ Bundle created at: {app_dir}")

    if not verify_bundle_structure(app_dir, sign_identity, out):
        return 1

    if do_install:
        install_bundle(app_dir, install_dir, out)

    if do_notarize:
        target_app = install_dir if do_install else app_dir
        out("")
        notarize_bundle(project_dir, target_app)

    return 0


def main() -> None:
    try:
        sys.exit(run_bundle(sys.argv[1:]))
    except BundleError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(exc.code)


if __name__ == "__main__":
    main()
