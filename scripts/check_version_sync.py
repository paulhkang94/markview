#!/usr/bin/env python3
"""
check_version_sync.py — verify all version strings across the project are in sync.

The canonical version is read from Sources/MarkView/Info.plist.

Usage:
    python3 scripts/check_version_sync.py
    python3 scripts/check_version_sync.py --expect-tag vX.Y.Z   (strict release mode)
    bash scripts/check-version-sync.sh   (thin wrapper)

Default mode (developer/PR guard): mid-release states are allowed (canonical
bumped but not yet tagged), npm may run ahead for JS-only patches, but any
*stale* version — a version-carrying file pointing at an older released
version than it should — is an error. In particular BINARY_VERSION must be
the highest released vX.Y.Z tag (the 1.6.0 incident shipped npm users the
v1.4.0 binary because only tag *existence* was checked, not currency).

--expect-tag mode (release gate): every version-carrying file must equal
X.Y.Z exactly — including npm/package.json and BINARY_VERSION. Used by
release.yml before building artifacts and by release_preflight.py before
tagging.

Exit 0: all versions in sync (warnings allowed).
Exit 1: one or more mismatches (or canonical version unreadable).
Exit 2: bad CLI usage.

Consumers — keep stdout shape and exit code stable:
    .github/workflows/guard.yml     exit code (CI gate, default mode)
    .github/workflows/release.yml   exit code (release gate, --expect-tag)
    scripts/verify.py               exit code (stdout re-printed)
    scripts/pre-commit-hook.sh      exit code only (output discarded)
    scripts/verify-release.sh       greps stdout for "✓ All versions in sync"
    scripts/release_preflight.py    exit code (strict --expect-tag mode)
"""

from __future__ import annotations

import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent

# Advisory-only check target. Module-level so tests can point it elsewhere.
INSTALLED_PLIST = Path("/Applications/MarkView.app/Contents/Info.plist")

# Mirrors the bash double-grep: outer pattern locates the assignment,
# inner pattern extracts the bare X.Y.Z version.
MCP_VERSION_PATTERN = r'version: "[0-9]+\.[0-9]+\.[0-9]+"'
BINARY_VERSION_PATTERN = r'const BINARY_VERSION = "[0-9]+\.[0-9]+\.[0-9]+"'
BARE_VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")


# ── Value readers ─────────────────────────────────────────────────────────────


def plist_value(path: Path, key: str) -> str:
    """Read a single plist key; '' on any failure (mirrors bash plist_value)."""
    try:
        with open(path, "rb") as f:
            return str(plistlib.load(f).get(key, ""))
    except Exception:
        return ""


def json_version(path: Path) -> str:
    """Read the top-level 'version' from a JSON file; '?' on any failure."""
    try:
        with open(path) as f:
            return str(json.load(f)["version"])
    except Exception:
        return "?"


def extract_versions(text: str, pattern: str) -> str:
    """All X.Y.Z versions inside substrings matching `pattern`, newline-joined.

    Mirrors `grep -oE '<pattern>' | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+'`:
    multiple matches produce a multi-line value that will fail an equality
    comparison, exactly as the bash did.
    """
    versions: list[str] = []
    for match in re.findall(pattern, text):
        bare = BARE_VERSION_RE.search(match)
        if bare:
            versions.append(bare.group(0))
    return "\n".join(versions)


# ── Git helpers (module-level so tests can stub them — no git dependency) ─────


def _git(args: list[str], project_dir: Path) -> str:
    """Run `git -C <project_dir> <args>`; stdout stripped, '' on failure."""
    try:
        result = subprocess.run(
            ["git", "-C", str(project_dir), *args],
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def latest_version_tag(project_dir: Path) -> str:
    """Most recent v* tag with the leading 'v' stripped; '' if none."""
    tag = _git(["describe", "--tags", "--abbrev=0", "--match", "v*"], project_dir)
    return tag[1:] if tag.startswith("v") else tag


VERSION_TAG_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")


def all_version_tags(project_dir: Path) -> list[str]:
    """Every vX.Y.Z tag in the repo (unsorted); [] if none."""
    out = _git(["tag", "--list", "v[0-9]*.[0-9]*.[0-9]*"], project_dir)
    return [t for t in out.splitlines() if VERSION_TAG_RE.match(t)]


def _version_key(version: str) -> tuple[int, int, int]:
    """Numeric sort key for 'X.Y.Z' or 'vX.Y.Z'; raises ValueError if malformed."""
    major, minor, patch = version.removeprefix("v").split(".")
    return (int(major), int(minor), int(patch))


def highest_version_tag(tags: list[str]) -> str:
    """Highest vX.Y.Z tag by numeric version order; '' if none.

    Numeric, not lexicographic — 'v1.10.0' must beat 'v1.9.0'.
    """
    return max(tags, key=_version_key, default="")


def _is_js_only_ahead(npm_ver: str, canonical: str, project_dir: Path) -> bool:
    """True when npm_ver is a legitimate JS-only patch version: numerically
    ahead of the app's canonical version AND without a corresponding app tag
    (an app tag for it would mean the app moved on and npm was left behind)."""
    try:
        ahead = _version_key(npm_ver) > _version_key(canonical)
    except ValueError:
        return False  # malformed version — let the caller flag it
    return ahead and not tag_exists(project_dir, f"v{npm_ver}")


def tag_exists(project_dir: Path, tag: str) -> bool:
    """True if `git tag --list <tag>` returns output."""
    return bool(_git(["tag", "--list", tag], project_dir))


def commits_since(project_dir: Path, tag: str) -> int:
    """Commit count in <tag>..HEAD; 0 on any failure (mirrors `|| echo 0`)."""
    out = _git(["rev-list", f"{tag}..HEAD", "--count"], project_dir)
    try:
        return int(out)
    except ValueError:
        return 0


# ── Main check ────────────────────────────────────────────────────────────────


def run(project_dir: Path, expect: str | None = None) -> int:
    """Run every version-sync check; print report; return exit code.

    `expect` (bare X.Y.Z) enables strict release mode: every version-carrying
    file must equal it exactly — no mid-release allowances.
    """
    plist = project_dir / "Sources/MarkView/Info.plist"
    canonical = plist_value(plist, "CFBundleShortVersionString")
    if not canonical:
        print("✗ Cannot read version from Info.plist")
        return 1

    canonical_build = plist_value(plist, "CFBundleVersion")
    print(f"Canonical version: {canonical} (build {canonical_build})")

    errors = 0

    if expect is not None:
        print(f"Strict release mode: every version must equal {expect}")
        if canonical == expect:
            print(f"  ✓ Info.plist matches release version {expect}")
        else:
            print(f"  ✗ Info.plist is {canonical} but the release expects {expect}")
            errors += 1
    else:
        # Git tag ↔ plist version check (Tier 0: no AI, pure string comparison).
        # During a release the plist is bumped BEFORE the tag is created; if the
        # plist version has no tag yet (unreleased bump), warn instead of error.
        latest_tag = latest_version_tag(project_dir)
        canonical_tag_present = tag_exists(project_dir, f"v{canonical}")
        if not latest_tag:
            print("  ⚠ No version tags found — skipping tag sync check")
        elif latest_tag == canonical:
            print(f"  ✓ Git tag v{latest_tag} matches Info.plist {canonical}")
        elif not canonical_tag_present:
            # Plist was bumped but tag not yet created — expected mid-release.
            print(
                f"  ⚠ Info.plist is {canonical} but no tag v{canonical} exists yet "
                f"(unreleased bump — run: git tag v{canonical} && git push --tags)"
            )
        else:
            # Tag exists but doesn't match plist — genuine mismatch.
            print(f"  ✗ Git tag v{latest_tag} does not match Info.plist {canonical}")
            print("    Fix: bash scripts/release.sh --bump patch  (or major/minor)")
            errors += 1

        # Warn if commits exist since last tag (unreleased changes).
        since = commits_since(project_dir, f"v{latest_tag}")
        if since > 0:
            print(
                f"  ⚠ {since} commit(s) since v{latest_tag} — "
                "consider bumping version before release"
            )

    # Quick Look Info.plist
    ql_plist = project_dir / "Sources/MarkViewQuickLook/Info.plist"
    if ql_plist.is_file():
        ql_ver = plist_value(ql_plist, "CFBundleShortVersionString")
        if ql_ver == canonical:
            print(f"  ✓ QuickLook CFBundleShortVersionString: {ql_ver}")
        else:
            print(
                f"  ✗ QuickLook CFBundleShortVersionString: {ql_ver} "
                f"(expected {canonical})"
            )
            errors += 1
        ql_build = plist_value(ql_plist, "CFBundleVersion")
        if ql_build == canonical_build:
            print(f"  ✓ QuickLook CFBundleVersion: {ql_build}")
        else:
            print(
                f"  ✗ QuickLook CFBundleVersion: {ql_build} "
                f"(expected {canonical_build})"
            )
            errors += 1

    # MCP server version string
    mcp_main = project_dir / "Sources/MarkViewMCPServer/main.swift"
    if mcp_main.is_file():
        mcp_ver = extract_versions(mcp_main.read_text(), MCP_VERSION_PATTERN)
        if mcp_ver == canonical:
            print(f"  ✓ MCP server main.swift: {mcp_ver}")
        else:
            print(f"  ✗ MCP server main.swift: {mcp_ver} (expected {canonical})")
            errors += 1

    # npm/package.json and server.json: must match each other.
    # Default mode: npm may run AHEAD of the Swift canonical version for
    # JS-only patches (a version with no corresponding vX.Y.Z app tag).
    # It must never sit at an older released version, and in strict release
    # mode it must equal the release version exactly.
    npm_pkg = project_dir / "npm/package.json"
    npm_server = project_dir / "npm/server.json"
    npm_ver = ""
    if npm_pkg.is_file():
        npm_ver = json_version(npm_pkg)
        if expect is not None:
            if npm_ver == expect:
                print(f"  ✓ npm/package.json: {npm_ver}")
            else:
                print(f"  ✗ npm/package.json: {npm_ver} (expected {expect})")
                errors += 1
        elif npm_ver == canonical:
            print(f"  ✓ npm/package.json: {npm_ver}")
        elif _is_js_only_ahead(npm_ver, canonical, project_dir):
            print(
                f"  ✓ npm/package.json: {npm_ver} "
                f"(JS-only version ahead of app {canonical})"
            )
        else:
            print(
                f"  ✗ npm/package.json: {npm_ver} is stale "
                f"(app canonical is {canonical} — bump npm with the release)"
            )
            errors += 1
    if npm_server.is_file():
        server_ver = json_version(npm_server)
        if server_ver == npm_ver:
            print(f"  ✓ npm/server.json: {server_ver}")
        else:
            print(
                f"  ✗ npm/server.json: {server_ver} "
                f"(expected {npm_ver} — must match npm/package.json)"
            )
            errors += 1

    # postinstall.js BINARY_VERSION (the macOS release to download) is
    # decoupled from the npm package version — JS-only npm patches don't
    # require a new macOS binary release. But it must be CURRENT, not merely
    # existent: the 1.6.0 incident shipped npm users the v1.4.0 binary for
    # 3 months because only tag existence was checked.
    #   strict mode:  BINARY_VERSION == release version, no exceptions.
    #   default mode: if its tag exists it must be the highest vX.Y.Z tag;
    #                 if not, it must equal canonical (mid-release bump).
    postinstall = project_dir / "npm/scripts/postinstall.js"
    if postinstall.is_file():
        binary_ver = (
            extract_versions(postinstall.read_text(), BINARY_VERSION_PATTERN) or "?"
        )
        if expect is not None:
            if binary_ver == expect:
                print(f"  ✓ npm/scripts/postinstall.js BINARY_VERSION: {binary_ver}")
            else:
                print(
                    f"  ✗ npm/scripts/postinstall.js BINARY_VERSION: {binary_ver} "
                    f"(expected {expect} — releasing v{expect} publishes the "
                    f"MarkView-{expect}.tar.gz this pin must point at)"
                )
                errors += 1
        elif tag_exists(project_dir, f"v{binary_ver}"):
            highest = highest_version_tag(all_version_tags(project_dir))
            if highest and f"v{binary_ver}" != highest:
                print(
                    f"  ✗ npm/scripts/postinstall.js BINARY_VERSION: {binary_ver} "
                    f"is STALE — newer release tag {highest} exists "
                    f"(npm installs would get the old binary; the 1.6.0 incident)"
                )
                errors += 1
            else:
                print(
                    f"  ✓ npm/scripts/postinstall.js BINARY_VERSION: {binary_ver} "
                    f"(latest release tag)"
                )
        elif binary_ver == canonical:
            print(
                f"  ⚠ npm/scripts/postinstall.js BINARY_VERSION: {binary_ver} "
                f"has no tag yet (unreleased bump — tagging v{canonical} "
                f"will publish its binary)"
            )
        else:
            print(
                f"  ✗ npm/scripts/postinstall.js BINARY_VERSION: {binary_ver} "
                f"(no tag v{binary_ver} — binary download will fail)"
            )
            errors += 1

    # Installed app (advisory only — not an error if not installed or stale)
    if INSTALLED_PLIST.is_file():
        inst_ver = plist_value(INSTALLED_PLIST, "CFBundleShortVersionString")
        if inst_ver == canonical:
            print(f"  ✓ Installed app: {inst_ver}")
        else:
            print(
                f"  ⚠ Installed app: {inst_ver} "
                "(stale — run: bash scripts/bundle.sh --install)"
            )

    if errors > 0:
        print()
        print(f"✗ Version sync failed: {errors} mismatches")
        return 1

    print("✓ All versions in sync")
    return 0


def main() -> None:
    expect: str | None = None
    args = sys.argv[1:]
    if args:
        if args[0] == "--expect-tag" and len(args) == 2:
            expect = args[1].removeprefix("v")
            if not BARE_VERSION_RE.fullmatch(expect):
                print(f"✗ --expect-tag must be vX.Y.Z or X.Y.Z (got: {args[1]})")
                sys.exit(2)
        else:
            print("Usage: check_version_sync.py [--expect-tag vX.Y.Z]")
            sys.exit(2)
    sys.exit(run(PROJECT_DIR, expect))


if __name__ == "__main__":
    main()
