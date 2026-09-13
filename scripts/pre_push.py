#!/usr/bin/env python3
"""Compose the shared publication guard with MarkView release/install gates.

The shared guard owns visibility, documentation policy, and commit selection.
This wrapper keeps release preflight sentinels and synchronous local installation
for native changes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

NATIVE_SUFFIXES = {".swift", ".yml", ".storyboard", ".xib", ".xcconfig"}
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?")
OID = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")


def pre_push(
    stdin: str, repo: Path | None = None, remote_args=(), runner=subprocess.run
) -> int:
    env = {
        key: value
        for key, value in os.environ.items()
        if key not in {"GIT_DIR", "GIT_INDEX_FILE", "GIT_WORK_TREE", "GIT_COMMON_DIR"}
    }
    if repo is None:
        found = runner(
            ["git", "-C", str(Path.cwd()), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            env=env,
        )
        if found.returncode or not found.stdout.strip():
            print(
                "ERROR: MarkView pre-push could not locate the Git worktree",
                file=sys.stderr,
            )
            return 1
        repo = Path(found.stdout.strip())
    result = runner(
        [
            sys.executable,
            str(repo / "scripts/public_repo_guard.py"),
            "--repo",
            str(repo),
            "--json",
            *remote_args,
        ],
        input=stdin,
        cwd=repo,
        capture_output=True,
        text=True,
        env=env,
    )
    if result.returncode:
        print(result.stdout, end="")
        print(result.stderr, end="", file=sys.stderr)
        return 1
    try:
        plan = json.loads(result.stdout)
        if not isinstance(plan, dict) or set(plan) != {"commits", "refs"}:
            raise ValueError("Invalid verified push plan")
        commits, refs = plan["commits"], plan["refs"]
        if (
            not isinstance(commits, list)
            or not isinstance(refs, list)
            or any(
                not isinstance(oid, str) or OID.fullmatch(oid) is None
                for oid in commits
            )
            or any(not isinstance(ref, str) for ref in refs)
        ):
            raise ValueError("Invalid verified commit/ref list")
        versions = set()
        for ref in refs:
            if ref.startswith("refs/tags/v"):
                version = ref.removeprefix("refs/tags/v")
                if VERSION.fullmatch(version) is None:
                    raise ValueError("Invalid release tag version")
                versions.add(version)
        sentinels = [
            repo / f".release-preflight-passed-{version}"
            for version in sorted(versions)
        ]
        for sentinel in sentinels:
            if not sentinel.is_file() or sentinel.is_symlink():
                raise ValueError(f"Release preflight required: {sentinel.name}")
        needs_build = False
        for commit in commits:
            changed = runner(
                [
                    "git",
                    "-C",
                    str(repo),
                    "diff-tree",
                    "--root",
                    "-m",
                    "--no-commit-id",
                    "--name-only",
                    "-r",
                    "-z",
                    commit,
                ],
                capture_output=True,
                text=True,
                env=env,
            )
            if changed.returncode:
                raise ValueError("Cannot determine native changes in the verified push")
            needs_build |= any(
                Path(path).suffix in NATIVE_SUFFIXES
                for path in changed.stdout.split("\0")
                if path
            )
        if needs_build:
            print(
                "Native source/configuration changed - rebuilding and installing locally before push...",
                flush=True,
            )
            built = runner(
                ["bash", str(repo / "scripts/bundle.sh"), "--install"],
                cwd=repo,
                env=env,
            )
            if built.returncode:
                raise ValueError("Local build or installation failed")
        # Consume only after every guard, sentinel, and build check succeeds.
        for sentinel in sentinels:
            sentinel.unlink()
    except (ValueError, OSError) as exc:
        print(f"ERROR: MarkView pre-push blocked: {exc}", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("remote_name", nargs="?")
    parser.add_argument("remote_url", nargs="?")
    args = parser.parse_args()
    remote_args = [
        value for value in (args.remote_name, args.remote_url) if value is not None
    ]
    try:
        return pre_push(sys.stdin.read(), remote_args=remote_args)
    except OSError as exc:
        print(
            f"ERROR: MarkView pre-push could not run a required gate: {exc}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
