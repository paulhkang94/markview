#!/usr/bin/env bash
# ci-status.sh — Check CI status for a PR or the latest push on a branch.
#
# Usage:
#   bash scripts/ci-status.sh [PR_NUMBER]
#   bash scripts/ci-status.sh          # uses current branch's latest run
#
# Outputs a summary line per check, then an overall PASS/FAIL/PENDING verdict.
# Safe in zsh: never uses jq != operator (uses 'select(... | not)' instead).

set -euo pipefail

REPO="paulhkang94/markview"

if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
  # PR mode: get checks from the PR's head SHA
  PR="$1"
  CHECKS=$(gh pr view "$PR" --repo "$REPO" --json statusCheckRollup --jq '.statusCheckRollup')
else
  # Branch mode: latest run on current branch
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  CHECKS=$(gh run list --repo "$REPO" --branch "$BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId' | xargs -I{} \
    gh run view {} --repo "$REPO" --json jobs --jq '.jobs | map({name: .name, status: .status, conclusion: .conclusion})')
fi

if [[ -z "$CHECKS" || "$CHECKS" == "null" || "$CHECKS" == "[]" ]]; then
  echo "No checks found."
  exit 0
fi

# Print each check — use 'select(... | not)' to avoid zsh != expansion issues
echo "$CHECKS" | jq -r '.[] | "\(.conclusion // .status | ascii_upcase)\t\(.name)"' | sort | column -t -s $'\t'

echo ""

# Count pending (not COMPLETED status)
PENDING=$(echo "$CHECKS" | jq '[.[] | select(.status == "COMPLETED" | not)] | length')
FAILED=$(echo "$CHECKS" | jq '[.[] | select(.conclusion == "FAILURE")] | length')
TOTAL=$(echo "$CHECKS" | jq 'length')

if [[ "$PENDING" -gt 0 ]]; then
  echo "PENDING — $PENDING/$TOTAL checks still running"
  exit 2
elif [[ "$FAILED" -gt 0 ]]; then
  echo "FAILED — $FAILED/$TOTAL checks failed"
  exit 1
else
  echo "PASS — all $TOTAL checks succeeded"
  exit 0
fi
