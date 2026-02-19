#!/bin/bash
set -euo pipefail

# Self-test for scripts/bootstrap-swiftpm.sh using a mocked `swift` binary.
# This validates retry and failure behavior without network access.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP_SCRIPT="$PROJECT_DIR/scripts/bootstrap-swiftpm.sh"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

run_case() {
  local name="$1"
  local failures_before_success="$2"
  local max_attempts="$3"
  local expect_exit="$4"

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/bin" "$tmp/.build/repositories" "$tmp/.build/checkouts"
  printf '// fixture\n' > "$tmp/Package.swift"

  cat > "$tmp/bin/swift" <<'SWIFT_MOCK'
#!/bin/bash
set -euo pipefail
STATE_FILE="${BOOTSTRAP_STATE_FILE:?}"
FAILURES_BEFORE_SUCCESS="${BOOTSTRAP_FAILS_BEFORE_SUCCESS:?}"
ATTEMPTS=0
if [ -f "$STATE_FILE" ]; then
  ATTEMPTS="$(cat "$STATE_FILE")"
fi
ATTEMPTS=$((ATTEMPTS + 1))
echo "$ATTEMPTS" > "$STATE_FILE"

if [ "$ATTEMPTS" -le "$FAILURES_BEFORE_SUCCESS" ]; then
  echo "mock swift resolve failure on attempt $ATTEMPTS" >&2
  exit 1
fi

echo "mock swift resolve success on attempt $ATTEMPTS" >&2
exit 0
SWIFT_MOCK
  chmod +x "$tmp/bin/swift"

  local state_file="$tmp/state"
  local output_file="$tmp/output.txt"

  set +e
  (
    cd "$tmp"
    PATH="$tmp/bin:$PATH" \
    BOOTSTRAP_STATE_FILE="$state_file" \
    BOOTSTRAP_FAILS_BEFORE_SUCCESS="$failures_before_success" \
    SWIFTPM_BOOTSTRAP_ATTEMPTS="$max_attempts" \
    bash "$BOOTSTRAP_SCRIPT"
  ) >"$output_file" 2>&1
  local status=$?
  set -e

  if [ "$status" -eq "$expect_exit" ]; then
    pass "$name: exit status $status"
  else
    fail "$name: expected exit $expect_exit, got $status"
    sed -n '1,120p' "$output_file"
  fi

  if [ -f "$state_file" ]; then
    local attempts
    attempts="$(cat "$state_file")"
    echo "    attempts: $attempts"
  fi

  # If we expect success after retries, output should include retry notice.
  if [ "$expect_exit" -eq 0 ] && [ "$failures_before_success" -gt 0 ]; then
    if grep -q "cleaning potentially corrupt checkouts" "$output_file"; then
      pass "$name: retry cleanup message present"
    else
      fail "$name: missing retry cleanup message"
      sed -n '1,120p' "$output_file"
    fi
  fi

  # If we expect full failure, output should include terminal error message.
  if [ "$expect_exit" -ne 0 ]; then
    if grep -q "Failed to resolve SwiftPM dependencies" "$output_file"; then
      pass "$name: terminal failure message present"
    else
      fail "$name: missing terminal failure message"
      sed -n '1,120p' "$output_file"
    fi
  fi

  rm -rf "$tmp"
  trap - RETURN
}

echo "--- bootstrap-swiftpm self-test ---"
run_case "immediate success" 0 3 0
run_case "retry then success" 2 3 0
run_case "exhaust retries" 9 3 1

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
