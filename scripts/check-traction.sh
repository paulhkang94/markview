#!/bin/bash
set -euo pipefail

# MarkView traction checker — run before/after launch posts
# Usage: bash scripts/check-traction.sh [--json]

JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

REPO="paulhkang94/markview"

# Gather data
stars=$(gh api "repos/$REPO" --jq '.stargazers_count' 2>/dev/null || echo "?")
forks=$(gh api "repos/$REPO" --jq '.forks_count' 2>/dev/null || echo "?")
watchers=$(gh api "repos/$REPO" --jq '.subscribers_count' 2>/dev/null || echo "?")
issues=$(gh api "repos/$REPO" --jq '.open_issues_count' 2>/dev/null || echo "?")

clones_total=$(gh api "repos/$REPO/traffic/clones" --jq '.count' 2>/dev/null || echo "?")
clones_unique=$(gh api "repos/$REPO/traffic/clones" --jq '.uniques' 2>/dev/null || echo "?")
views_total=$(gh api "repos/$REPO/traffic/views" --jq '.count' 2>/dev/null || echo "?")
views_unique=$(gh api "repos/$REPO/traffic/views" --jq '.uniques' 2>/dev/null || echo "?")

if $JSON_MODE; then
  cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stars": $stars,
  "forks": $forks,
  "watchers": $watchers,
  "open_issues": $issues,
  "clones_14d": {"total": $clones_total, "unique": $clones_unique},
  "views_14d": {"total": $views_total, "unique": $views_unique}
}
EOF
else
  echo "=== MarkView Traction — $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo ""
  printf "  Stars: %-6s  Forks: %-6s  Watchers: %-6s  Issues: %s\n" "$stars" "$forks" "$watchers" "$issues"
  echo ""
  printf "  Clones (14d): %s total, %s unique\n" "$clones_total" "$clones_unique"
  printf "  Views  (14d): %s total, %s unique\n" "$views_total" "$views_unique"
  echo ""

  echo "  Top referrers:"
  gh api "repos/$REPO/traffic/popular/referrers" --jq '.[] | "    \(.referrer): \(.count) (\(.uniques) unique)"' 2>/dev/null || echo "    (none)"
  echo ""

  echo "  Release downloads:"
  gh api "repos/$REPO/releases" --jq '.[] | "    \(.tag_name): \([.assets[].download_count] | add // 0) downloads"' 2>/dev/null || echo "    (none)"
fi
