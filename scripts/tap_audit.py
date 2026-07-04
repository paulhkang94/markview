#!/usr/bin/env python3
"""
tap_audit.py — compare latest GitHub release version with Homebrew tap version.

Usage:
    python3 scripts/tap_audit.py
    bash scripts/tap-audit.sh   (thin wrapper)

Exit 0 = match, exit 1 = mismatch (prints fix command).

Invoked post-release by the markview-release skill (exit code only) and
manually. Probes the tap repo's cask `version` line against the newest
GitHub release tag.
"""

from __future__ import annotations

import re
import subprocess
import sys
import urllib.request

REPO = "paulhkang94/markview"
TAP_CASK_URL = (
    "https://raw.githubusercontent.com/paulhkang94/homebrew-markview/"
    "main/Casks/markview.rb"
)

CASK_VERSION_RE = re.compile(r'version "([0-9]+\.[0-9]+\.[0-9]+)"')


# ── Data sources (module-level so tests can stub — no live gh / network) ──────


def latest_release_tag() -> str:
    """Newest release tag via gh, leading 'v' stripped. Exits if gh fails."""
    cmd = [
        "gh",
        "release",
        "list",
        "--repo",
        REPO,
        "--limit",
        "1",
        "--json",
        "tagName",
        "--jq",
        ".[0].tagName",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError as exc:
        sys.stderr.write(f"{exc}\n")
        sys.exit(127)
    if result.returncode != 0:
        # Mirrors set -euo pipefail: propagate gh's failure immediately.
        sys.stderr.write(result.stderr)
        sys.exit(result.returncode or 1)
    tag = result.stdout.strip()
    return tag[1:] if tag.startswith("v") else tag


def fetch_cask() -> str:
    """Fetch the tap cask source; '' on any failure (mirrors curl -fsSL || '')."""
    try:
        request = urllib.request.Request(
            TAP_CASK_URL, headers={"User-Agent": "markview-tap-audit/1.0"}
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.read().decode()
    except Exception:
        return ""


def extract_tap_version(cask: str) -> str:
    """First X.Y.Z from the cask's `version "X.Y.Z"` line; '' if absent."""
    match = CASK_VERSION_RE.search(cask)
    return match.group(1) if match else ""


# ── Main ──────────────────────────────────────────────────────────────────────


def main() -> None:
    latest = latest_release_tag()
    tap_version = extract_tap_version(fetch_cask())

    if not tap_version:
        print(f"ERROR: could not fetch tap cask from {TAP_CASK_URL}")
        sys.exit(1)

    if tap_version == latest:
        print(f"✓ Homebrew tap v{tap_version} matches latest release v{latest}")
        sys.exit(0)

    print(f"MISMATCH: Homebrew tap v{tap_version} ≠ latest release v{latest}")
    print()
    print("To fix:")
    print(f"  gh workflow run tap-update.yml --repo {REPO} --field tag_name=v{latest}")
    sys.exit(1)


if __name__ == "__main__":
    main()
