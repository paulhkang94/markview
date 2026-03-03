#!/usr/bin/env bash
# test-rule-gates.sh — Self-tests for check-rule-gates.sh
#
# Usage: bash tests/test-rule-gates.sh
# Exit: 0 = all passed, 1 = any failure
#
# Tests use synthetic repo roots (temp dirs) so they never depend on
# the real rule-gates.json or actual CI files — they test the checker logic only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/../scripts/check-rule-gates.sh"
PASS=0
FAIL=0

assert_exit() {
  local label="$1" expected="$2"
  shift 2
  local actual=0
  "$@" > /dev/null 2>&1 || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    echo "  PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_stdout_contains() {
  local label="$1" needle="$2"
  shift 2
  local out
  out=$("$@" 2>&1 || true)
  if echo "$out" | grep -qF "$needle"; then
    echo "  PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label (expected '$needle' in output)"
    echo "        actual: $out"
    FAIL=$((FAIL + 1))
  fi
}

TMPBASE=$(mktemp -d)
cleanup() { rm -rf "$TMPBASE"; }
trap cleanup EXIT

setup() {
  local dir="$1"
  mkdir -p "$dir/scripts" "$dir/.github/workflows"
}

echo ""
echo "=== test-rule-gates (7 cases) ==="
echo ""

# T1: pattern exists in ci_file → exit 0
T="$TMPBASE/t1"; setup "$T"
cat > "$T/scripts/rule-gates.json" <<'EOF'
{"_schema":"1","rules":[{"id":"r1","source":"x","source_anchor":"x","description":"x",
  "ci_files":[".github/workflows/guard.yml"],"ci_pattern":"check-version-sync\\.sh",
  "gate_type":"script_run","tier":1}]}
EOF
echo "- run: bash scripts/check-version-sync.sh" > "$T/.github/workflows/guard.yml"
assert_exit "T1: gate present → exit 0" 0 bash "$CHECKER" --repo-root "$T"

# T2: pattern missing from ci_file → exit 1
T="$TMPBASE/t2"; setup "$T"
cat > "$T/scripts/rule-gates.json" <<'EOF'
{"_schema":"1","rules":[{"id":"r2","source":"x","source_anchor":"x","description":"x",
  "ci_files":[".github/workflows/guard.yml"],"ci_pattern":"check-rule-gates\\.sh",
  "gate_type":"script_run","tier":1}]}
EOF
echo "- run: echo nothing relevant" > "$T/.github/workflows/guard.yml"
assert_exit "T2: gate missing → exit 1" 1 bash "$CHECKER" --repo-root "$T"

# T3: ci_file itself missing → exit 1
T="$TMPBASE/t3"; setup "$T"
cat > "$T/scripts/rule-gates.json" <<'EOF'
{"_schema":"1","rules":[{"id":"r3","source":"x","source_anchor":"x","description":"x",
  "ci_files":[".github/workflows/nonexistent.yml"],"ci_pattern":"anything",
  "gate_type":"script_run","tier":1}]}
EOF
assert_exit "T3: ci_file not found → exit 1" 1 bash "$CHECKER" --repo-root "$T"

# T4: manifest itself missing → exit 1
T="$TMPBASE/t4"; setup "$T"
assert_exit "T4: manifest missing → exit 1" 1 bash "$CHECKER" --repo-root "$T"

# T5: empty rules array → exit 0
T="$TMPBASE/t5"; setup "$T"
echo '{"_schema":"1","rules":[]}' > "$T/scripts/rule-gates.json"
assert_exit "T5: empty rules → exit 0" 0 bash "$CHECKER" --repo-root "$T"

# T6: failure output contains the rule id
T="$TMPBASE/t6"; setup "$T"
cat > "$T/scripts/rule-gates.json" <<'EOF'
{"_schema":"1","rules":[{"id":"my-unique-rule-id","source":"x","source_anchor":"x",
  "description":"x","ci_files":[".github/workflows/guard.yml"],
  "ci_pattern":"pattern-not-in-file","gate_type":"script_run","tier":1}]}
EOF
echo "- run: echo nothing" > "$T/.github/workflows/guard.yml"
assert_stdout_contains "T6: failure output names the rule id" "my-unique-rule-id" \
  bash "$CHECKER" --repo-root "$T"

# T7: multiple rules — one passes, one fails → exit 1
T="$TMPBASE/t7"; setup "$T"
cat > "$T/scripts/rule-gates.json" <<'EOF'
{"_schema":"1","rules":[
  {"id":"passes","source":"x","source_anchor":"x","description":"x",
   "ci_files":[".github/workflows/guard.yml"],"ci_pattern":"pattern-exists",
   "gate_type":"script_run","tier":1},
  {"id":"fails","source":"x","source_anchor":"x","description":"x",
   "ci_files":[".github/workflows/guard.yml"],"ci_pattern":"pattern-missing",
   "gate_type":"script_run","tier":1}
]}
EOF
echo "- run: echo pattern-exists" > "$T/.github/workflows/guard.yml"
assert_exit "T7: mixed pass+fail → exit 1" 1 bash "$CHECKER" --repo-root "$T"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
