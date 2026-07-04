#!/usr/bin/env python3
"""
npm_publish_gate.py — hard gate run by npm-publish.yml BEFORE `npm publish`.

The 1.6.0 incident: npm published with postinstall.js pinned to the v1.4.0
binary while the app released v1.6.0 — npm installs silently downloaded a
3-month-old binary. npm publishes are immutable, so the pin must be proven
current and downloadable before the package leaves the building.

Invariants enforced (exit 1 on any violation):
1. If a git tag v<npm version> exists, this is a coordinated app+npm
   release: BINARY_VERSION must equal the npm version. Because the push to
   main (which triggers npm-publish.yml) can land moments before the tag
   push, the gate waits up to --tag-wait seconds for the tag to appear
   before concluding the publish is JS-only.
2. If no such tag exists (JS-only npm patch): BINARY_VERSION must equal the
   latest published GitHub release tag — never an older one.
3. Always: the GitHub release v<BINARY_VERSION> must exist and carry the
   MarkView-<BINARY_VERSION>.tar.gz asset that postinstall.js downloads.
   During a coordinated release this fails while release.yml is still
   building — npm-publish.yml re-runs automatically via its workflow_run
   trigger once the Release workflow succeeds.

Usage:
    python3 scripts/npm_publish_gate.py [--tag-wait SECONDS]

Requires gh (authenticated; in Actions set GH_TOKEN on the step).
Repo slug from $GITHUB_REPOSITORY, defaulting to paulhkang94/markview.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_REPO = "paulhkang94/markview"
DEFAULT_TAG_WAIT_SECONDS = 180
POLL_INTERVAL_SECONDS = 15

# Same extraction contract as check_version_sync.py (scripts stay
# self-contained — they deploy and run as single files).
BINARY_VERSION_RE = re.compile(r'const BINARY_VERSION = "([0-9]+\.[0-9]+\.[0-9]+)"')


# ── Subprocess boundary (module-level so tests can stub — never call real gh) ─


def _run(cmd: list[str]) -> tuple[int, str, str]:
    """Run a command; return (returncode, stdout, stderr). Never raises."""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError as exc:
        return 127, "", str(exc)
    return result.returncode, result.stdout, result.stderr


def _sleep(seconds: float) -> None:
    time.sleep(seconds)


# ── GitHub readers (module-level so tests can stub) ───────────────────────────


def remote_tag_exists(repo: str, tag: str) -> bool:
    """True if refs/tags/<tag> exists on GitHub."""
    rc, _, _ = _run(["gh", "api", f"repos/{repo}/git/ref/tags/{tag}"])
    return rc == 0


def release_assets(repo: str, tag: str) -> list[str] | None:
    """Asset names of release <tag>; None if the release does not exist."""
    rc, out, _ = _run(
        ["gh", "api", f"repos/{repo}/releases/tags/{tag}", "--jq", ".assets[].name"]
    )
    if rc != 0:
        return None
    return [line for line in out.splitlines() if line.strip()]


def latest_release_tag(repo: str) -> str:
    """Tag name of the latest published release (e.g. 'v1.6.0'); '' if none."""
    rc, out, _ = _run(
        ["gh", "api", f"repos/{repo}/releases/latest", "--jq", ".tag_name"]
    )
    return out.strip() if rc == 0 else ""


# ── File readers ──────────────────────────────────────────────────────────────


def read_npm_version(project_dir: Path) -> str:
    try:
        with open(project_dir / "npm/package.json") as f:
            return str(json.load(f)["version"])
    except Exception:
        return ""


def read_binary_version(project_dir: Path) -> str:
    try:
        text = (project_dir / "npm/scripts/postinstall.js").read_text()
    except OSError:
        return ""
    match = BINARY_VERSION_RE.search(text)
    return match.group(1) if match else ""


# ── Gate ──────────────────────────────────────────────────────────────────────


def run_gate(
    project_dir: Path,
    repo: str,
    tag_wait_seconds: int = DEFAULT_TAG_WAIT_SECONDS,
) -> int:
    """Run every publish-gate check; print report; return exit code."""
    npm_ver = read_npm_version(project_dir)
    pin = read_binary_version(project_dir)
    if not npm_ver:
        print("✗ Cannot read version from npm/package.json")
        return 1
    if not pin:
        print("✗ Cannot read BINARY_VERSION from npm/scripts/postinstall.js")
        return 1

    print(f"npm package version:      {npm_ver}")
    print(f"postinstall BINARY_VERSION: {pin}")

    if pin == npm_ver:
        # Coordinated release shape — correctness reduces to the asset check.
        print(f"  ✓ BINARY_VERSION matches the npm version ({pin})")
    else:
        # Is an app tag for this npm version present (or about to be)?
        npm_tag = f"v{npm_ver}"
        strict = remote_tag_exists(repo, npm_tag)
        if not strict:
            # A coordinated release pushes main (triggering this workflow)
            # moments before the tag — wait so a stale pin can't slip
            # through that gap and get published immutably.
            waited = 0
            while waited < tag_wait_seconds:
                _sleep(POLL_INTERVAL_SECONDS)
                waited += POLL_INTERVAL_SECONDS
                if remote_tag_exists(repo, npm_tag):
                    strict = True
                    break
            if not strict:
                print(
                    f"  ✓ No app tag {npm_tag} after {waited}s — "
                    f"treating as a JS-only npm publish"
                )
        if strict:
            print(
                f"  ✗ STALE BINARY_VERSION: app tag {npm_tag} exists but "
                f"postinstall pins {pin} — npm users would get the wrong "
                f"binary (the 1.6.0 incident). Bump BINARY_VERSION to "
                f"{npm_ver} before publishing."
            )
            return 1
        latest = latest_release_tag(repo)
        if not latest:
            print("  ✗ No published GitHub release found — nothing to download")
            return 1
        if f"v{pin}" != latest:
            print(
                f"  ✗ STALE BINARY_VERSION: {pin} but the latest published "
                f"release is {latest} — JS-only publishes must pin the "
                f"current binary"
            )
            return 1
        print(f"  ✓ BINARY_VERSION {pin} is the latest published release")

    # The exact artifact postinstall.js downloads must already be public.
    assets = release_assets(repo, f"v{pin}")
    if assets is None:
        print(
            f"  ✗ GitHub release v{pin} does not exist (yet). If the Release "
            f"workflow is still running, this workflow re-runs automatically "
            f"via workflow_run when it succeeds."
        )
        return 1
    archive = f"MarkView-{pin}.tar.gz"
    if archive not in assets:
        print(
            f"  ✗ Release v{pin} exists but has no {archive} asset — "
            f"postinstall would fail for every npm install"
        )
        return 1
    print(f"  ✓ Release v{pin} carries {archive}")

    print("✓ npm publish gate passed")
    return 0


def main() -> None:
    tag_wait = DEFAULT_TAG_WAIT_SECONDS
    args = sys.argv[1:]
    if args:
        if args[0] == "--tag-wait" and len(args) == 2 and args[1].isdigit():
            tag_wait = int(args[1])
        else:
            print("Usage: npm_publish_gate.py [--tag-wait SECONDS]")
            sys.exit(2)
    repo = os.environ.get("GITHUB_REPOSITORY", DEFAULT_REPO)
    sys.exit(run_gate(PROJECT_DIR, repo, tag_wait))


if __name__ == "__main__":
    main()
