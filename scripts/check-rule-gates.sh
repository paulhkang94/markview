#!/usr/bin/env bash
# check-rule-gates.sh — Verify every rule in rule-gates.json has its CI gate in place.
#
# Usage:
#   bash scripts/check-rule-gates.sh [--repo-root <path>]
#
# Exit codes:
#   0  All rule gates present
#   1  One or more gates missing, or manifest unreadable
#
# Requires: python3 (stdlib only — json, re, sys, pathlib — no pip deps)
# Runs on: ubuntu-latest, macos-latest

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Allow --repo-root override (used by test suite to point at synthetic repos)
if [[ "${1:-}" == "--repo-root" && -n "${2:-}" ]]; then
  REPO_ROOT="$2"
elif [[ -n "${1:-}" && "${1:-}" != "--"* ]]; then
  REPO_ROOT="$1"
fi

MANIFEST="$REPO_ROOT/scripts/rule-gates.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "check-rule-gates: manifest not found: $MANIFEST" >&2
  exit 1
fi

python3 - "$REPO_ROOT" "$MANIFEST" <<'PYEOF'
import json
import re
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])

try:
    manifest = json.loads(manifest_path.read_text())
except json.JSONDecodeError as e:
    print(f"check-rule-gates: invalid JSON in {manifest_path}: {e}", file=sys.stderr)
    sys.exit(1)

rules = manifest.get("rules", [])
if not rules:
    print("check-rule-gates: no rules in manifest — nothing to check")
    sys.exit(0)

failures = []
passes = []

skipped = []

for rule in rules:
    rule_id    = rule.get("id", "<no-id>")
    ci_files   = rule.get("ci_files", [])
    pattern    = rule.get("ci_pattern", "")
    source     = rule.get("source", "?")
    gate_type  = rule.get("gate_type", "")

    # pre_push_only rules live in .git/hooks/ which is never committed or
    # checked out in CI. Skip verification — the gate exists locally.
    if gate_type == "pre_push_only":
        skipped.append(rule_id)
        continue

    if not ci_files:
        failures.append((rule_id, source, "no ci_files specified"))
        continue
    if not pattern:
        failures.append((rule_id, source, "no ci_pattern specified"))
        continue

    try:
        compiled = re.compile(pattern)
    except re.error as e:
        failures.append((rule_id, source, f"invalid ci_pattern regex: {e}"))
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
        failures.append((rule_id, source, f"ci_files not found: {', '.join(missing_files)}"))
    else:
        failures.append((rule_id, source,
            f"pattern '{pattern}' not found in: {', '.join(ci_files)}"))

checked = len(rules) - len(skipped)
print(f"\ncheck-rule-gates: {len(rules)} rules total, "
      f"{checked} checked, {len(passes)} passed, "
      f"{len(failures)} failed, {len(skipped)} skipped (pre_push_only)\n")

if failures:
    for rule_id, source, reason in failures:
        print(f"  FAIL  [{rule_id}]  source: {source}")
        print(f"        reason: {reason}")
    print()
    print("Each FAIL means a documented rule has no structural CI gate.")
    print("Fix: add the pattern to the referenced workflow/script,")
    print("     or update ci_pattern/ci_files in scripts/rule-gates.json")
    sys.exit(1)
else:
    for rule_id in passes:
        print(f"  OK    {rule_id}")
    sys.exit(0)
PYEOF
