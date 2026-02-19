#!/bin/bash
set -euo pipefail

# Bootstrap SwiftPM dependencies with retry logic.
# Useful for CI and local E2E flows to prefetch required package repos.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

if [ ! -f Package.swift ]; then
  echo "No Package.swift found in $PROJECT_DIR"
  exit 1
fi

MAX_ATTEMPTS="${SWIFTPM_BOOTSTRAP_ATTEMPTS:-3}"
ATTEMPT=1

run_resolve() {
  swift package resolve
}

echo "--- Bootstrap SwiftPM Dependencies ---"
while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
  echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: swift package resolve"
  if run_resolve; then
    echo "✓ SwiftPM dependencies resolved"
    exit 0
  fi

  if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
    echo "⚠ resolve failed; cleaning potentially corrupt checkouts and retrying"
    rm -rf .build/repositories .build/checkouts 2>/dev/null || true
    sleep $((ATTEMPT * 2))
  fi

  ATTEMPT=$((ATTEMPT + 1))
done

echo "✗ Failed to resolve SwiftPM dependencies after $MAX_ATTEMPTS attempts"
echo "  If you are in a restricted network, configure outbound access to github.com or use an internal SwiftPM mirror."
exit 1
