#!/usr/bin/env python3
"""
release_preflight.py — validate all release prerequisites BEFORE pushing a tag.

Usage:
    python3 scripts/release_preflight.py
    bash scripts/release-preflight.sh   (thin wrapper)

Pass: prints "Pre-flight passed. Safe to tag.", writes the sentinel
      .release-preflight-passed-<version> at the repo root, and exits 0.
Fail: exits 1 with specific failure messages.

Catches the 4-tag-push class of CI failures (missing secrets, wrong
permissions, stale SPM cache) before any CI runner time is spent, plus the
1.6.0 class of version drift BEFORE the tag exists: strict version sync
(check_version_sync.py --expect-tag — BINARY_VERSION included, FAIL not
WARN), clean working tree, branch == main, tag non-existence (local and
remote), a CHANGELOG entry for the release, and no npm version collision
(a version already on the registry makes npm-publish.yml skip, leaving npm
users pinned to the previous binary).

Contract: the pre-push hook blocks `git push origin vX.Y.Z` unless the
sentinel .release-preflight-passed-X.Y.Z exists at the repo root, and
deletes it on push — each release requires a fresh preflight run. Keep the
sentinel filename byte-identical.
"""

from __future__ import annotations

import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent

# Stale binary artifacts here cause exit code 74 on release CI.
# Module-level so tests can point it at a temp directory.
SPM_ARTIFACTS = Path.home() / "Library/Caches/org.swift.swiftpm/artifacts"

REQUIRED_SECRETS = [
    "NOTARIZE_KEY_ID",
    "NOTARIZE_ISSUER_ID",
    "NOTARIZE_API_KEY",
    "DEVELOPER_ID_CERT_BASE64",
    "DEVELOPER_ID_CERT_PASSWORD",
    "APP_PRIVATE_KEY",
]


# ── Subprocess boundary (module-level so tests can stub — never call real gh) ─


def _run(cmd: list[str], cwd: Path | None = None) -> tuple[int, str, str]:
    """Run a command; return (returncode, stdout, stderr). Never raises."""
    try:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    except FileNotFoundError as exc:
        return 127, "", str(exc)
    return result.returncode, result.stdout, result.stderr


def _which(name: str) -> str | None:
    return shutil.which(name)


# ── Small helpers ─────────────────────────────────────────────────────────────


def _colors() -> tuple[str, str, str, str]:
    """(green, red, yellow, reset) — empty when stdout is not a TTY."""
    if sys.stdout.isatty():
        return "\033[0;32m", "\033[0;31m", "\033[0;33m", "\033[0m"
    return "", "", "", ""


def _first_column(text: str) -> set[str]:
    """First whitespace-delimited field of each line (mirrors awk '{print $1}')."""
    names: set[str] = set()
    for line in text.splitlines():
        fields = line.split()
        if fields:
            names.add(fields[0])
    return names


def _lines_after_match(text: str, needle: str, after: int) -> list[str]:
    """Each line containing `needle` plus the following `after` lines
    (mirrors grep -A<after>)."""
    lines = text.splitlines()
    kept: list[str] = []
    for i, line in enumerate(lines):
        if needle in line:
            kept.extend(lines[i : i + after + 1])
    return kept


def _plist_version(path: Path) -> str:
    """CFBundleShortVersionString from a plist; '' on any failure."""
    try:
        with open(path, "rb") as f:
            return str(plistlib.load(f).get("CFBundleShortVersionString", ""))
    except Exception:
        return ""


# ── Pre-flight checks ─────────────────────────────────────────────────────────


def run_preflight() -> int:
    """Run every pre-flight check; print report; return exit code."""
    green, red, yellow, reset = _colors()
    failures = 0

    def ok(msg: str) -> None:
        print(f"  {green}[OK]{reset} {msg}")

    def warn(msg: str) -> None:
        print(f"  {yellow}[WARN]{reset} {msg}")

    def fail(msg: str) -> None:
        nonlocal failures
        print(f"  {red}[FAIL]{reset} {msg}")
        failures += 1

    # Derived at call time so tests can repoint PROJECT_DIR.
    info_plist = PROJECT_DIR / "Sources/MarkView/Info.plist"
    release_yml = PROJECT_DIR / ".github/workflows/release.yml"

    print("=== MarkView Release Pre-flight Check ===")
    print()

    # ── 0. Release state: version, tree, branch, tag, changelog, npm ─────────
    version = _plist_version(info_plist)
    if version:
        ok(f"Release version (Info.plist): {version}")
    else:
        fail("Cannot read CFBundleShortVersionString from Info.plist")

    # Clean working tree — an uncommitted fix would not be in the tag commit
    # (the 1.6.0 pin fix landed on main AFTER the tag was cut).
    rc, status_out, _ = _run(["git", "status", "--porcelain"], cwd=PROJECT_DIR)
    if rc == 0 and not status_out.strip():
        ok("Working tree clean")
    else:
        fail("Working tree dirty — commit or stash before tagging")

    rc, branch_out, _ = _run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=PROJECT_DIR
    )
    branch = branch_out.strip()
    if rc == 0 and branch == "main":
        ok("On branch main")
    else:
        fail(f"On branch '{branch}' — releases are tagged from main only")

    if version:
        _, local_tag, _ = _run(["git", "tag", "--list", f"v{version}"], cwd=PROJECT_DIR)
        _, remote_tag, _ = _run(
            ["git", "ls-remote", "--tags", "origin", f"refs/tags/v{version}"],
            cwd=PROJECT_DIR,
        )
        if local_tag.strip() or remote_tag.strip():
            fail(f"Tag v{version} already exists — bump the version first")
        else:
            ok(f"Tag v{version} does not exist yet (local + remote)")

        try:
            changelog_text = (PROJECT_DIR / "CHANGELOG.md").read_text()
        except OSError:
            changelog_text = ""
        if f"## v{version}" in changelog_text:
            ok(f"CHANGELOG.md documents v{version}")
        else:
            fail(
                f"CHANGELOG.md has no '## v{version}' entry — "
                "document the release before tagging"
            )

        # npm version collision: npm-publish.yml skips versions that are
        # already on the registry, so a collision would leave npm users
        # pinned to the previous binary forever.
        if _which("npm"):
            rc, npm_out, _ = _run(
                ["npm", "view", f"mcp-server-markview@{version}", "version"],
                cwd=PROJECT_DIR,
            )
            if rc == 0 and npm_out.strip() == version:
                fail(
                    f"mcp-server-markview@{version} is already published — "
                    "npm-publish.yml would skip it; bump to an unpublished version"
                )
            else:
                ok(f"npm version {version} is unpublished")
        else:
            warn("npm CLI not found — cannot verify npm version collision")

    # ── 1. GitHub CLI available ───────────────────────────────────────────────
    if _which("gh"):
        _, version_out, _ = _run(["gh", "--version"])
        first_line = version_out.splitlines()[0] if version_out.splitlines() else ""
        ok(f"gh CLI available ({first_line})")
    else:
        fail("gh CLI not found — install via: brew install gh")

    # ── 2. Authenticated to GitHub ────────────────────────────────────────────
    rc, _, _ = _run(["gh", "auth", "status"])
    if rc == 0:
        ok("GitHub authenticated")
    else:
        fail("Not authenticated to GitHub — run: gh auth login")

    # ── 3. Required release secrets set in repo ───────────────────────────────
    print()
    print("  Checking required secrets...")
    rc, secrets_out, _ = _run(["gh", "secret", "list"], cwd=PROJECT_DIR)
    secret_names = _first_column(secrets_out if rc == 0 else "")
    for secret in REQUIRED_SECRETS:
        if secret in secret_names:
            ok(f"Secret: {secret}")
        else:
            fail(f"Missing secret: {secret} (set via: gh secret set {secret})")

    # Tap update auth = GitHub App (homebrew bot), not HOMEBREW_TAP_TOKEN
    # (token deleted when tap-update.yml moved to create-github-app-token, 61776ee).
    rc, variables_out, _ = _run(["gh", "variable", "list"], cwd=PROJECT_DIR)
    variable_names = _first_column(variables_out if rc == 0 else "")
    if "APP_ID" in variable_names:
        ok("Variable: APP_ID (tap-update GitHub App)")
    else:
        fail("Missing repo variable: APP_ID (set via: gh variable set APP_ID)")

    # ── 4. release.yml has contents:write permission ──────────────────────────
    print()
    try:
        release_yml_text = release_yml.read_text()
    except OSError:
        release_yml_text = ""
    if "contents: write" in release_yml_text:
        ok("release.yml has contents:write permission")
    else:
        fail(
            "release.yml missing 'permissions: contents: write' — "
            "required for softprops/action-gh-release"
        )

    # ── 5. release.yml passes every required secret to build step ─────────────
    # NOTARIZE_KEY_ID must appear in the build step's env block, not just in
    # "Store notarization credentials" — GH Actions env scope is per-step.
    build_step = _lines_after_match(release_yml_text, "Build, sign, notarize", 5)
    if any("NOTARIZE_KEY_ID" in line for line in build_step):
        ok("NOTARIZE_KEY_ID passed to build step env")
    else:
        fail(
            "NOTARIZE_KEY_ID not in 'Build, sign, notarize' step env "
            "(per-step scope — not inherited)"
        )

    # ── 6. Stale SPM binary artifact cache cleared ────────────────────────────
    print()
    if SPM_ARTIFACTS.is_dir() and any(SPM_ARTIFACTS.iterdir()):
        warn(f"Stale SPM binary artifact cache found at {SPM_ARTIFACTS} — clearing...")
        shutil.rmtree(SPM_ARTIFACTS, ignore_errors=True)
        ok("SPM artifact cache cleared (prevents exit code 74 on release CI)")
    else:
        ok("SPM artifact cache clean (or already empty)")

    # ── 7. Local tests pass ───────────────────────────────────────────────────
    print()
    print("  Running local tests...")
    _, test_out, test_err = _run(
        ["swift", "run", "MarkViewTestRunner"], cwd=PROJECT_DIR
    )
    if "0 failed" in test_out + test_err:
        ok("Local tests pass (MarkViewTestRunner)")
    else:
        fail("Local tests failing — fix before tagging")

    # ── 8. Version consistency (STRICT — the 1.6.0 gate) ─────────────────────
    # WARN-level sync is what let 1.6.0 tag with a stale BINARY_VERSION.
    # Strict mode: every version-carrying file (both Info.plists, MCP
    # main.swift, npm/package.json, npm/server.json, BINARY_VERSION) must
    # equal the version about to be tagged.
    print()
    version_sync = PROJECT_DIR / "scripts/check_version_sync.py"
    if version_sync.is_file():
        rc, _, _ = _run(
            [sys.executable, str(version_sync), "--expect-tag", f"v{version}"],
            cwd=PROJECT_DIR,
        )
        if rc == 0:
            ok(f"Version numbers in sync (strict — all files equal {version})")
        else:
            fail(
                "Version sync FAILED — see: python3 scripts/check_version_sync.py "
                f"--expect-tag v{version} (BINARY_VERSION must match the release)"
            )

    # ── 9. Distribution path test ─────────────────────────────────────────────
    # Tests the user-facing install path, not the developer path (bundle.sh
    # --install strips quarantine and never hits Gatekeeper). This is the check
    # that catches signing failures before they reach users.
    print()
    print("  Running distribution path test (--local)...")
    _, dist_out, dist_err = _run(
        ["bash", str(PROJECT_DIR / "scripts/test-distribution.sh"), "--local"],
        cwd=PROJECT_DIR,
    )
    if "Distribution test passed" in dist_out + dist_err:
        ok(
            "Distribution path test passed (local install — quarantine + signature checks)"
        )
    else:
        fail("Distribution path test FAILED — fix signing/bundle before tagging")

    # ── Summary ───────────────────────────────────────────────────────────────
    print()
    print("==================================================")
    if failures == 0:
        # Write sentinel consumed by the pre-push hook — proves this check ran.
        version = version or "unknown"
        sentinel = PROJECT_DIR / f".release-preflight-passed-{version}"
        sentinel.touch()
        print(f"{green}Pre-flight passed. Safe to tag.{reset}")
        print()
        print(f"  Sentinel written: {sentinel.name}")
        print(f"  Next: git tag v{version} && git push origin v{version}")
        return 0

    print(f"{red}{failures} check(s) failed. Fix before tagging.{reset}")
    return 1


def main() -> None:
    sys.exit(run_preflight())


if __name__ == "__main__":
    main()
