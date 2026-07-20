#!/usr/bin/env python3
"""
check_rule_gates.py — Verify every rule in rule-gates.json has its CI gate in place.

Usage:
    python3 scripts/check_rule_gates.py [--repo-root <path>] [<path>]
    bash scripts/check-rule-gates.sh [--repo-root <path>]   (thin wrapper)

Exit codes:
    0  All rule gates present
    1  One or more gates missing, or manifest unreadable

Requires: python3 (stdlib only — json, re, sys, pathlib — no pip deps)
Runs on: ubuntu-latest, macos-latest

Consumers — keep stdout shape and exit code stable:
    .github/workflows/guard.yml   exit code
    scripts/pre-commit-hook.sh    exit code only (output discarded)
    Tests/test-rule-gates.sh      exit code + stdout (rule-id substring match)
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import NamedTuple


class RuleResult(NamedTuple):
    rule_id: str
    source: str
    reason: str


def parse_repo_root(argv: list[str], default: Path) -> Path:
    """Mirror the original bash arg parsing: `--repo-root <path>` or a bare
    positional path. Anything else falls back to `default`."""
    if len(argv) >= 2 and argv[0] == "--repo-root" and argv[1]:
        return Path(argv[1])
    if argv and argv[0] and not argv[0].startswith("--"):
        return Path(argv[0])
    return default


def load_manifest(manifest_path: Path) -> dict | None:
    """Returns None (and prints to stderr) if the manifest is missing or invalid."""
    if not manifest_path.is_file():
        print(f"check-rule-gates: manifest not found: {manifest_path}", file=sys.stderr)
        return None
    try:
        return json.loads(manifest_path.read_text())
    except json.JSONDecodeError as e:
        print(
            f"check-rule-gates: invalid JSON in {manifest_path}: {e}", file=sys.stderr
        )
        return None


def check_rules(
    repo_root: Path, rules: list[dict]
) -> tuple[list[str], list[RuleResult], list[str]]:
    """Returns (passes, failures, skipped) — pure logic, no I/O side effects
    beyond reading the ci_files themselves."""
    passes: list[str] = []
    failures: list[RuleResult] = []
    skipped: list[str] = []

    for rule in rules:
        rule_id = rule.get("id", "<no-id>")
        ci_files = rule.get("ci_files", [])
        pattern = rule.get("ci_pattern", "")
        source = rule.get("source", "?")
        gate_type = rule.get("gate_type", "")

        # pre_push_only rules live in .git/hooks/ which is never committed or
        # checked out in CI. Skip verification — the gate exists locally.
        if gate_type == "pre_push_only":
            skipped.append(rule_id)
            continue

        if not ci_files:
            failures.append(RuleResult(rule_id, source, "no ci_files specified"))
            continue
        if not pattern:
            failures.append(RuleResult(rule_id, source, "no ci_pattern specified"))
            continue

        try:
            compiled = re.compile(pattern)
        except re.error as e:
            failures.append(
                RuleResult(rule_id, source, f"invalid ci_pattern regex: {e}")
            )
            continue

        found = False
        missing_files = []

        for rel_path in ci_files:
            target = repo_root / rel_path
            if not target.exists():
                missing_files.append(rel_path)
                continue
            content = target.read_text(errors="replace")
            if compiled.search(content):
                found = True
                break

        if found:
            passes.append(rule_id)
        elif missing_files and len(missing_files) == len(ci_files):
            failures.append(
                RuleResult(
                    rule_id, source, f"ci_files not found: {', '.join(missing_files)}"
                )
            )
        else:
            failures.append(
                RuleResult(
                    rule_id,
                    source,
                    f"pattern '{pattern}' not found in: {', '.join(ci_files)}",
                )
            )

    return passes, failures, skipped


def print_report(
    rules_total: int, passes: list[str], failures: list[RuleResult], skipped: list[str]
) -> None:
    checked = rules_total - len(skipped)
    print(
        f"\ncheck-rule-gates: {rules_total} rules total, "
        f"{checked} checked, {len(passes)} passed, "
        f"{len(failures)} failed, {len(skipped)} skipped (pre_push_only)\n"
    )

    if failures:
        for rule_id, source, reason in failures:
            print(f"  FAIL  [{rule_id}]  source: {source}")
            print(f"        reason: {reason}")
        print()
        print("Each FAIL means a documented rule has no structural CI gate.")
        print("Fix: add the pattern to the referenced workflow/script,")
        print("     or update ci_pattern/ci_files in scripts/rule-gates.json")
    else:
        for rule_id in passes:
            print(f"  OK    {rule_id}")


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    script_dir = Path(__file__).resolve().parent
    default_repo_root = script_dir.parent

    repo_root = parse_repo_root(argv, default_repo_root)
    manifest_path = repo_root / "scripts" / "rule-gates.json"

    manifest = load_manifest(manifest_path)
    if manifest is None:
        return 1

    rules = manifest.get("rules", [])
    if not rules:
        print("check-rule-gates: no rules in manifest — nothing to check")
        return 0

    passes, failures, skipped = check_rules(repo_root, rules)
    print_report(len(rules), passes, failures, skipped)

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
