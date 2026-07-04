#!/usr/bin/env python3
"""
check_release_destinations.py — enforce one owner per publish destination.

The 1.6.0 incident had TWO npm publishers: release.yml published from the
tag commit (before the BINARY_VERSION pin fix landed on main) while
npm-publish.yml published from main. Two writers to one immutable registry
guarantee that one of them eventually ships the wrong content. 744c8a7
removed release.yml's publish step; this lint makes reintroducing it — in
any workflow or in scripts/release.sh — a CI failure instead of a code
review hope.

Contract (comment lines are ignored):
- `npm publish` may appear ONLY in .github/workflows/npm-publish.yml
- `mcp-publisher publish` may appear ONLY in npm-publish.yml
- NPM_TOKEN may appear NOWHERE (npm auth is OIDC trusted publishing)
- npm-publish.yml itself must still contain `npm publish` and
  `id-token: write` — if the single owner loses its publish step or its
  OIDC grant, that is drift too.

Usage:
    python3 scripts/check_release_destinations.py

Exit 0: destinations single-owned.  Exit 1: violation(s).

Consumers:
    .github/workflows/guard.yml   (CI gate; registered in rule-gates.json
                                   as npm-publish-single-owner)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent

OWNER = ".github/workflows/npm-publish.yml"

PUBLISH_PATTERNS = {
    "npm publish": re.compile(r"\bnpm\s+publish\b"),
    "mcp-publisher publish": re.compile(r"\bmcp-publisher\s+publish\b"),
}
NPM_TOKEN_RE = re.compile(r"\bNPM_TOKEN\b")


def significant_text(path: Path) -> str:
    """File content with comment lines removed (first non-space char '#').

    Covers YAML comments and comment lines inside `run: |` shell blocks —
    prose ABOUT publishing stays legal; code that publishes does not.
    """
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return ""
    return "\n".join(l for l in lines if not l.lstrip().startswith("#"))


def run(project_dir: Path) -> int:
    """Scan workflows + release.sh; print report; return exit code."""
    workflows_dir = project_dir / ".github/workflows"
    scanned = sorted(workflows_dir.glob("*.yml")) + sorted(workflows_dir.glob("*.yaml"))
    release_sh = project_dir / "scripts/release.sh"
    if release_sh.is_file():
        scanned.append(release_sh)

    errors = 0
    owner_seen = False

    for path in scanned:
        rel = path.relative_to(project_dir).as_posix()
        text = significant_text(path)
        is_owner = rel == OWNER
        owner_seen = owner_seen or is_owner

        for label, pattern in PUBLISH_PATTERNS.items():
            if pattern.search(text) and not is_owner:
                print(
                    f"  ✗ {rel} contains '{label}' — publishing is owned "
                    f"exclusively by {OWNER} (one owner per destination; "
                    f"the 1.6.0 dual-publish incident)"
                )
                errors += 1

        if NPM_TOKEN_RE.search(text):
            print(
                f"  ✗ {rel} references NPM_TOKEN — npm auth is OIDC trusted "
                f"publishing only (tokens expire; 1.6.0 was blocked by one)"
            )
            errors += 1

    # The single owner must still be doing its job.
    owner_path = project_dir / OWNER
    owner_text = significant_text(owner_path)
    if not owner_seen or not owner_path.is_file():
        print(f"  ✗ {OWNER} not found — npm publishing has no owner")
        errors += 1
    else:
        if PUBLISH_PATTERNS["npm publish"].search(owner_text):
            print(f"  ✓ {OWNER} owns 'npm publish'")
        else:
            print(f"  ✗ {OWNER} no longer contains 'npm publish' — owner lost")
            errors += 1
        if "id-token: write" in owner_text:
            print(f"  ✓ {OWNER} keeps OIDC (id-token: write)")
        else:
            print(
                f"  ✗ {OWNER} missing 'id-token: write' — OIDC trusted "
                f"publishing requires it"
            )
            errors += 1

    if errors:
        print()
        print(f"✗ Release destination check failed: {errors} violation(s)")
        return 1

    print(f"  ✓ No stray publishers in {len(scanned)} scanned file(s)")
    print("✓ Publish destinations single-owned")
    return 0


def main() -> None:
    sys.exit(run(PROJECT_DIR))


if __name__ == "__main__":
    main()
