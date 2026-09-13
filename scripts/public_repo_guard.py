#!/usr/bin/env python3
"""public-repo-guard - shared document policy, ignore generator, and pre-push guard.

.public-docs.json is the reviewed research-path manifest. --docs-only audits
without network access; --write-ignore regenerates its .gitignore block.
--ref audits one committed snapshot. Plain invocation consumes Git's pre-push
stdin, checks public snapshots, and enforces the author email on new commits.
No document contents are read: only Git metadata, the manifest, and .gitignore.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath

REQUIRED_EMAIL = "contact@paulkang.dev"
MANIFEST = ".public-docs.json"
BEGIN = "# BEGIN GENERATED PUBLIC DOCS"
END = "# END GENERATED PUBLIC DOCS"
ROOT = Path.cwd()
GIT_PROCESS_ENV = {"GIT_DIR", "GIT_INDEX_FILE", "GIT_WORK_TREE", "GIT_COMMON_DIR"}
PRIVATE_NAMES = {
    "CLAUDE.md",
    "AGENTS.md",
    "AGENTS.override.md",
    "SESSION-RESUME.md",
    ".claude",
    ".codex",
    ".vscode",
}
PRIVATE_SIGNALS = re.compile(
    r"strategy|competitive|adoption|financial|revenue|investor|confidential|internal|"
    r"personal|launch|market|analysis|positioning|audit|metrics|roadmap|pricing",
    re.I,
)


class PolicyError(ValueError):
    """Invalid or unavailable evidence must block publication."""


def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(ROOT), *args],
        capture_output=True,
        text=True,
        timeout=30,
        env={key: value for key, value in os.environ.items() if key not in GIT_PROCESS_ENV},
    )


def _git_text(*args: str) -> str:
    result = _git(*args)
    if result.returncode:
        raise PolicyError(f"Git could not read policy evidence ({args[0]})")
    return result.stdout


def _resolve_commit(ref: str) -> str:
    return _git_text("rev-parse", "--verify", "--end-of-options", ref + "^{commit}").strip()


def _github_match(url: str):
    return re.fullmatch(
        r"(?:git@github\.com:|https://github\.com/|ssh://git@github\.com/)"
        r"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?",
        url,
    )


def _repo_is_private(remote_url: str | None = None) -> bool:
    if remote_url is None:
        remote = _git("remote", "get-url", "origin")
        remote_url = remote.stdout.strip() if remote.returncode == 0 else ""
    if not remote_url or not shutil.which("gh"):
        return False
    match = _github_match(remote_url)
    if not match:
        return False
    result = subprocess.run(
        ["gh", "api", f"repos/{match.group(1)}", "--jq", ".private"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.returncode == 0 and result.stdout.strip() == "true"


def _json_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise PolicyError(f"Duplicate manifest key: {key}")
        result[key] = value
    return result


def parse_manifest(content: str | None) -> tuple[str, ...]:
    if content is None:
        return ()
    try:
        data = json.loads(content, object_pairs_hook=_json_object)
    except json.JSONDecodeError as exc:
        raise PolicyError("Invalid public-doc manifest JSON") from exc
    if not isinstance(data, dict) or set(data) != {"version", "approved_research"}:
        raise PolicyError("Manifest requires only version and approved_research")
    if type(data["version"]) is not int or data["version"] != 1:
        raise PolicyError("Unsupported public-doc manifest version")
    approved = data["approved_research"]
    if not isinstance(approved, list) or any(not isinstance(p, str) for p in approved):
        raise PolicyError("approved_research must be a list of exact paths")
    if len(approved) != len(set(approved)):
        raise PolicyError("Duplicate approved research path")
    for path in approved:
        parts = path.split("/")
        if (
            not path.startswith("docs/research/")
            or not path.endswith(".md")
            or any(part in ("", ".", "..") for part in parts)
            or any(c in path for c in "\\*?[]!#")
            or any(c.isspace() or ord(c) < 32 for c in path)
            or any(part in PRIVATE_NAMES for part in parts)
        ):
            raise PolicyError(f"Unsafe approved research path: {path!r}")
    return tuple(sorted(approved))


def ignore_block(approved: tuple[str, ...]) -> str:
    lines = [
        BEGIN,
        "# Generated from .public-docs.json; edit the manifest, then use --write-ignore.",
        "CLAUDE.md",
        "AGENTS.md",
        "AGENTS.override.md",
        "SESSION-RESUME.md",
        ".claude/",
        ".codex/",
        "docs/personal/",
        "docs/research/*",
    ]
    directories = set()
    for path in approved:
        parent = PurePosixPath(path).parent
        while parent.as_posix() != "docs/research":
            directories.add(parent.as_posix())
            parent = parent.parent
    for directory in sorted(directories, key=lambda p: (p.count("/"), p)):
        lines.extend([f"!{directory}/", f"{directory}/*"])
    lines.extend(f"!{path}" for path in approved)
    return "\n".join([*lines, END]) + "\n"


def _ignore_parts(content: str) -> tuple[str, str, str]:
    lines = content.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.rstrip("\r\n") == BEGIN]
    ends = [i for i, line in enumerate(lines) if line.rstrip("\r\n") == END]
    if not starts and not ends:
        return content, "", ""
    if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
        raise PolicyError("Ambiguous generated .gitignore block")
    start, end = starts[0], ends[0] + 1
    return "".join(lines[:start]), "".join(lines[start:end]), "".join(lines[end:])


def _check_outside_ignore(before: str, after: str) -> None:
    if any(
        "docs/research" in line and not line.lstrip().startswith("#")
        for line in (before + after).splitlines()
    ):
        raise PolicyError("Research ignore rules must live in the generated block")


def _worktree_file(name: str) -> str | None:
    path = ROOT / name
    if path.is_symlink():
        raise PolicyError(f"Policy input must be a regular file: {name}")
    return path.read_text(encoding="utf-8") if path.exists() else None


def _snapshot(ref: str | None) -> tuple[dict[str, str], str | None, str | None]:
    if ref is None:
        # --stage exposes symlinks and unmerged entries without reading contents.
        rows = _git_text("ls-files", "--stage", "-z")
        files = {}
        for row in rows.split("\0"):
            if not row:
                continue
            metadata, path = row.split("\t", 1)
            mode, _oid, stage = metadata.split()
            if stage != "0":
                raise PolicyError("Resolve unmerged index entries before auditing")
            files[path] = mode
        return files, _worktree_file(MANIFEST), _worktree_file(".gitignore")
    ref = _resolve_commit(ref)
    files = {}
    for row in _git_text("ls-tree", "-r", "-z", ref).split("\0"):
        if row:
            metadata, path = row.split("\t", 1)
            files[path] = metadata.split()[0]

    def read(name):
        if name not in files:
            return None
        if files[name] not in {"100644", "100755"}:
            raise PolicyError(f"Policy input must be a regular file: {name}")
        return _git_text("show", f"{ref}:{name}")

    return files, read(MANIFEST), read(".gitignore")


def _protected(path: str) -> bool:
    parts = PurePosixPath(path).parts
    return (
        any(part in PRIVATE_NAMES or part.startswith(".env") for part in parts)
        or "hooks" in parts
        or any(parts[i : i + 2] == ("docs", "personal") for i in range(len(parts) - 1))
        or any(
            parts[i] == "scripts" and parts[i + 1].startswith(("claude-", "claude_"))
            for i in range(len(parts) - 1)
        )
    )


def audit_docs(ref: str | None = None) -> None:
    files, manifest, ignore = _snapshot(ref)
    approved = parse_manifest(manifest)
    blocked = []
    for path, mode in files.items():
        if _protected(path):
            blocked.append(path)
        elif path.startswith("docs/research/"):
            if path not in approved or mode not in {"100644", "100755"}:
                blocked.append(path)
        elif path.startswith("docs/") and PRIVATE_SIGNALS.search(PurePosixPath(path).stem):
            blocked.append(path)
    if blocked:
        raise PolicyError(
            "protected files or unapproved public docs: " + ", ".join(sorted(blocked))
        )
    if manifest is not None:
        before, block, after = _ignore_parts(ignore or "")
        _check_outside_ignore(before, after)
        if block != ignore_block(approved):
            raise PolicyError("Generated .gitignore policy drift; run --write-ignore")


def write_ignore() -> None:
    manifest = _worktree_file(MANIFEST)
    if manifest is None:
        raise PolicyError("Create and review .public-docs.json before generating ignore rules")
    approved = parse_manifest(manifest)
    original = _worktree_file(".gitignore") or ""
    before, block, after = _ignore_parts(original)
    _check_outside_ignore(before, after)
    if not block and before and not before.endswith("\n"):
        before += "\n"
    generated = before + ignore_block(approved) + after
    if generated == original:
        return
    path = ROOT / ".gitignore"
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=ROOT, delete=False
        ) as handle:
            temporary = Path(handle.name)
            handle.write(generated)
        temporary.chmod(mode)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _pushes(text: str) -> list[tuple[str, str, str]]:
    pushes = []
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.split()
        if len(parts) != 4:
            raise PolicyError("Malformed pre-push input")
        _local_ref, local_oid, remote_ref, remote_oid = parts
        if not all(
            re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", oid) for oid in (local_oid, remote_oid)
        ):
            raise PolicyError("Malformed pre-push object ID")
        if set(local_oid) != {"0"}:
            pushes.append((remote_ref, _resolve_commit(local_oid), remote_oid))
    return pushes


def _destination_tips(remote_name: str, remote_url: str | None) -> list[str]:
    # Tracking refs are publication evidence only for the same destination.
    # A private fetch remote or a different push URL must not hide new history.
    if remote_name not in _git_text("remote").splitlines():
        return []
    fetch_url = _git_text("remote", "get-url", remote_name).strip()
    push_url = remote_url or fetch_url
    fetch_match, push_match = _github_match(fetch_url), _github_match(push_url)
    same = fetch_url == push_url or (
        fetch_match is not None
        and push_match is not None
        and fetch_match.group(1).lower() == push_match.group(1).lower()
    )
    if not same:
        return []
    return _git_text(
        "for-each-ref", "--format=%(objectname)", f"refs/remotes/{remote_name}/"
    ).splitlines()


def _new_commits(local_oid: str, remote_oid: str, destination_tips: list[str]) -> list[str]:
    args = [local_oid, "--not", *destination_tips]
    if set(remote_oid) != {"0"}:
        args.append(remote_oid)
    return _git_text("rev-list", *args).splitlines()


def check_push(
    stdin: str, remote_url: str | None, remote_name: str = "origin"
) -> dict[str, list[str]]:
    pushes = _pushes(stdin)
    if not pushes:
        return {"commits": [], "refs": []}
    destination_tips = _destination_tips(remote_name, remote_url)
    commits = set()
    tips = set()
    for _remote_ref, local_oid, remote_oid in pushes:
        tips.add(local_oid)
        commits.update(_new_commits(local_oid, remote_oid, destination_tips))
    if not _repo_is_private(remote_url):
        for ref in sorted(commits | tips):
            audit_docs(ref)
    bad = set()
    for ref in sorted(commits):
        email = _git_text("show", "-s", "--format=%ae", ref).strip()
        if email != REQUIRED_EMAIL:
            bad.add(email)
    if bad:
        raise PolicyError(
            "commits use wrong author email; required "
            + REQUIRED_EMAIL
            + "; found "
            + ", ".join(sorted(bad))
        )

    return {"commits": sorted(commits), "refs": [ref for ref, _oid, _remote in pushes]}


def main(argv: list[str] | None = None) -> int:
    global ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--docs-only", action="store_true", help="Audit documentation offline")
    mode.add_argument(
        "--write-ignore", action="store_true", help="Generate the manifest's ignore block"
    )
    parser.add_argument(
        "--json", action="store_true", help="Emit verified destination refs and new commits"
    )
    parser.add_argument("--ref", help="Audit this committed revision with its own policy")
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("remote_name", nargs="?")
    parser.add_argument("remote_url", nargs="?")
    args = parser.parse_args(argv)
    if args.ref and not args.docs_only:
        parser.error("--ref requires --docs-only")
    if args.json and (args.docs_only or args.write_ignore):
        parser.error("--json is only supported for pre-push verification")
    if (args.remote_name is None) != (args.remote_url is None):
        parser.error("Git pre-push requires both remote name and URL")
    if args.remote_name is not None and (args.docs_only or args.write_ignore):
        parser.error("Remote arguments are only supported for pre-push verification")
    ROOT = args.repo.resolve()
    try:
        ROOT = Path(_git_text("rev-parse", "--show-toplevel").strip())
        if args.write_ignore:
            write_ignore()
        elif args.docs_only:
            audit_docs(args.ref)
        else:
            plan = check_push(sys.stdin.read(), args.remote_url, args.remote_name or "origin")
            if args.json:
                print(json.dumps(plan, sort_keys=True))
    except (PolicyError, OSError, UnicodeError, subprocess.TimeoutExpired) as exc:
        print(f"ERROR: Public repository guard blocked: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
