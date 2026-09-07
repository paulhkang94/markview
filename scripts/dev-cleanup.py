#!/usr/bin/env python3
"""
dev-cleanup.py — Reclaim local dev-build disk space for MarkView (mar-048).

Removes three classes of ephemeral build output that accumulate across dev
iterations and are never the record source (the record source is /Applications,
installed by scripts/bundle.py --install):

  - <repo>/build/                                     (xcodebuild -derivedDataPath
                                                         output; scripts/bundle.py)
  - <repo>/MarkView.app                                (repo-root bundle produced
                                                         by scripts/bundle.py)
  - ~/Library/Developer/Xcode/DerivedData/MarkView-*   (Xcode.app GUI DerivedData
                                                         for this project)

Dry-run by default: lists every target with its size and deletes nothing.
Pass --apply to actually delete. Every path is printed with its size before
deletion in both modes, so a dry run tells you exactly what --apply will do.

Usage:
    python3 scripts/dev-cleanup.py            # dry run (default)
    python3 scripts/dev-cleanup.py --apply     # actually delete

No subprocess calls — pure filesystem walk/delete, so tests exercise real
temp directories (project_dir/home are injectable) rather than stubbing a
command boundary.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
APP_NAME = "MarkView"


class CleanupError(Exception):
    """Raised to abort before any filesystem work. `code` is the process
    exit code to use."""

    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code


# ── Argument parsing ─────────────────────────────────────────────────────────


def parse_args(argv: list[str]) -> bool:
    """Returns do_apply. Raises CleanupError on an unknown option."""
    do_apply = False
    for arg in argv:
        if arg == "--apply":
            do_apply = True
        else:
            raise CleanupError(
                f"Unknown option: {arg}\nUsage: python3 scripts/dev-cleanup.py [--apply]"
            )
    return do_apply


# ── Size helpers ─────────────────────────────────────────────────────────────


def human_size(num_bytes: int) -> str:
    """Format bytes as e.g. `1.2 GB` (binary/1024 units, whole bytes have no
    decimal — mirrors macOS Finder-style sizing closely enough for a CLI
    report, not byte-exact `du -h`)."""
    if num_bytes < 1024:
        return f"{num_bytes} B"
    value = float(num_bytes)
    for unit in ("KB", "MB", "GB"):
        value /= 1024
        if value < 1024:
            return f"{value:.1f} {unit}"
    return f"{value:.1f} TB"


def _dir_size(path: Path) -> int:
    """Recursive size in bytes. Does not follow directory symlinks (mirrors
    `du` without `-L`) to avoid double-counting or infinite loops through a
    symlinked tree; a symlink itself is counted at its own (tiny) size."""
    try:
        if path.is_symlink():
            return path.lstat().st_size
        if path.is_file():
            return path.stat().st_size
        if not path.is_dir():
            return 0
    except OSError:
        return 0
    total = 0
    try:
        children = list(path.iterdir())
    except OSError:
        return 0
    for child in children:
        total += _dir_size(child)
    return total


def _remove(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()


# ── Targets ──────────────────────────────────────────────────────────────────


def find_targets(project_dir: Path, home: Path) -> list[Path]:
    """Existing cleanup targets for this project: the repo-local build/
    output, the repo-root .app bundle, and any DerivedData products under
    Xcode's global cache for this project. Only paths that currently exist
    are returned, in a stable (build, app, DerivedData...) order."""
    targets = [project_dir / "build", project_dir / f"{APP_NAME}.app"]
    derived_data = home / "Library/Developer/Xcode/DerivedData"
    if derived_data.is_dir():
        targets.extend(sorted(derived_data.glob(f"{APP_NAME}-*")))
    return [t for t in targets if t.is_symlink() or t.exists()]


# ── Orchestration ────────────────────────────────────────────────────────────


def run_cleanup(
    argv: list[str],
    project_dir: Path = PROJECT_DIR,
    home: Path | None = None,
    out=print,
) -> int:
    do_apply = parse_args(argv)
    if home is None:
        home = Path.home()

    targets = find_targets(project_dir, home)
    if not targets:
        out("Nothing to clean — no build/, MarkView.app, or DerivedData products found.")
        return 0

    sizes = [(t, _dir_size(t)) for t in targets]
    total = sum(size for _, size in sizes)

    if do_apply:
        out("=== Dev cleanup (deleting) ===")
        for target, size in sizes:
            _remove(target)
            out(f"  ✓ Removed {target} ({human_size(size)})")
        out("")
        out(f"✓ Freed {human_size(total)} ({len(sizes)} items)")
    else:
        out("=== Dev cleanup (dry run) ===")
        for target, size in sizes:
            out(f"  {target}  {human_size(size)}")
        out("")
        out(f"Total: {len(sizes)} items, {human_size(total)}")
        out("Dry run only — nothing deleted. Re-run with --apply to delete.")

    return 0


def main() -> None:
    try:
        sys.exit(run_cleanup(sys.argv[1:]))
    except CleanupError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(exc.code)


if __name__ == "__main__":
    main()
