#!/bin/bash
set -euo pipefail

# MarkView — Check that build dependencies used in scripts are also in CI
# Run as a pre-push or pre-commit check to catch missing CI tool installs.
#
# Usage: bash scripts/check-ci-deps.sh

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CI_FILE="$PROJECT_DIR/.github/workflows/ci.yml"

if [ ! -f "$CI_FILE" ]; then
    echo "⚠ No CI workflow found at $CI_FILE"
    exit 0
fi

PASS=0
FAIL=0

check_dep() {
    local tool="$1"
    local used_in="$2"

    # Check if the tool is used in any script that CI calls
    if grep -rq "$tool" "$PROJECT_DIR/scripts/"*.sh "$PROJECT_DIR/verify.sh" 2>/dev/null; then
        # Check if CI installs it or it's expected on the runner
        if grep -q "$tool" "$CI_FILE" 2>/dev/null; then
            PASS=$((PASS + 1))
        else
            # Check if it's a system tool (always on macOS runners)
            case "$tool" in
                swift|xcodebuild|codesign|plutil|security|spctl|xcrun|stapler|tar|xattr)
                    PASS=$((PASS + 1))  # System tools on macOS runners
                    ;;
                *)
                    echo "  ✗ '$tool' used in scripts but not installed in CI ($CI_FILE)"
                    FAIL=$((FAIL + 1))
                    ;;
            esac
        fi
    fi
}

echo "--- CI Dependency Check ---"

# Tools that bundle.sh / verify.sh / release.sh depend on
# Only check tools actually invoked (not just mentioned in comments/checks)
check_dep "xcodegen" "bundle.sh"

# cmark-gfm is only used by DiffTester (extended tests, separate workflow)
# swiftlint/swiftformat are not currently used in any script

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "  $FAIL tool(s) used in scripts but missing from CI."
    echo "  Add 'brew install <tool>' to .github/workflows/ci.yml"
    exit 1
elif [ "$PASS" -gt 0 ]; then
    echo "  ✓ All $PASS checked dependencies present in CI"
fi
