#!/bin/bash
set -euo pipefail

# MarkView unified metrics tracker
# Usage: bash scripts/metrics.sh
# Pulls npm, GitHub, and MCP registry data, saves snapshots, displays formatted report

REPO="paulhkang94/markview"
NPM_PKG="mcp-server-markview"
MCP_SERVER_ID="io.github.paulhkang94%2Fmarkview"
SNAPSHOT_FILE=".claude/memory/traction-snapshots.jsonl"

echo "=== MarkView Metrics Snapshot — $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" >&2
echo "" >&2

# ==============================================================================
# GITHUB REPO STATS
# ==============================================================================
echo "Fetching GitHub repo stats..." >&2
stars=$(gh api "repos/$REPO" --jq '.stargazers_count' 2>/dev/null || echo "?")
forks=$(gh api "repos/$REPO" --jq '.forks_count' 2>/dev/null || echo "?")
watchers=$(gh api "repos/$REPO" --jq '.subscribers_count' 2>/dev/null || echo "?")
issues=$(gh api "repos/$REPO" --jq '.open_issues_count' 2>/dev/null || echo "?")

# ==============================================================================
# GITHUB TRAFFIC (14D)
# ==============================================================================
echo "Fetching GitHub traffic..." >&2
clones_total=$(gh api "repos/$REPO/traffic/clones" --jq '.count' 2>/dev/null || echo "?")
clones_unique=$(gh api "repos/$REPO/traffic/clones" --jq '.uniques' 2>/dev/null || echo "?")
views_total=$(gh api "repos/$REPO/traffic/views" --jq '.count' 2>/dev/null || echo "?")
views_unique=$(gh api "repos/$REPO/traffic/views" --jq '.uniques' 2>/dev/null || echo "?")

# Top referrers
echo "Fetching top referrers..." >&2
referrers=$(gh api "repos/$REPO/traffic/popular/referrers" --jq '[.[] | {referrer: .referrer, count: .count, uniques: .uniques}]' 2>/dev/null || echo "[]")

# Popular paths
echo "Fetching popular paths..." >&2
popular_paths=$(gh api "repos/$REPO/traffic/popular/paths" --jq '[.[] | {path: .path, count: .count, uniques: .uniques}]' 2>/dev/null || echo "[]")

# ==============================================================================
# GITHUB RELEASES
# ==============================================================================
echo "Fetching release download counts..." >&2
releases=$(gh api "repos/$REPO/releases" --jq '[.[] | {tag_name: .tag_name, published_at: .published_at, downloads: ([.assets[].download_count] | add // 0)}]' 2>/dev/null || echo "[]")

# ==============================================================================
# NPM DOWNLOADS
# ==============================================================================
echo "Fetching npm download stats..." >&2

# 7-day downloads
npm_7d=$(curl -s "https://api.npmjs.org/downloads/point/last-week/$NPM_PKG" | jq '.downloads // 0' 2>/dev/null || echo "0")

# 30-day downloads
npm_30d=$(curl -s "https://api.npmjs.org/downloads/point/last-month/$NPM_PKG" | jq '.downloads // 0' 2>/dev/null || echo "0")

# Per-day for last 14 days
npm_daily=$(curl -s "https://api.npmjs.org/downloads/range/last-14-days/$NPM_PKG" 2>/dev/null | jq '.downloads // []' || echo "[]")

# ==============================================================================
# NPM PUBLISH HISTORY (last 5 versions)
# ==============================================================================
echo "Fetching npm publish history..." >&2
npm_publish_history=$(curl -s "https://registry.npmjs.org/$NPM_PKG" 2>/dev/null | jq '
  . as $root |
  [.versions | keys[] as $v | {version: $v, published: $root.time[$v]}] |
  sort_by(.published) |
  reverse |
  .[0:5]
' 2>/dev/null || echo "[]")

# ==============================================================================
# MCP REGISTRY INFO
# ==============================================================================
echo "Fetching MCP registry data..." >&2
mcp_data=$(curl -s "https://registry.modelcontextprotocol.io/v0.1/servers/$MCP_SERVER_ID/versions" 2>/dev/null || echo "null")
if [ "$mcp_data" != "null" ] && [ "$mcp_data" != "" ]; then
  mcp_version_count=$(echo "$mcp_data" | jq '[.versions[]? | select(.status == "active")] | length' 2>/dev/null || echo "0")
  mcp_latest=$(echo "$mcp_data" | jq -r '[.versions[]? | select(.status == "active") | .published_date] | map(select(. != null)) | max' 2>/dev/null || echo "unknown")
else
  mcp_version_count="0"
  mcp_latest="unknown"
fi

# ==============================================================================
# BUILD JSON SNAPSHOT (one line per entry - JSONL format)
# ==============================================================================
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
snapshot=$(jq -c "{timestamp: \"$timestamp\", github: {stars: $stars, forks: $forks, watchers: $watchers, open_issues: $issues, traffic_14d: {clones: {total: $clones_total, unique: $clones_unique}, views: {total: $views_total, unique: $views_unique}}, referrers: $referrers, popular_paths: $popular_paths, releases: $releases}, npm: {downloads_7d: $npm_7d, downloads_30d: $npm_30d, daily_last_14d: $npm_daily, publish_history: $npm_publish_history}, mcp_registry: {active_versions: $mcp_version_count, latest_published: \"$mcp_latest\"}}" <<< '{}')

# Save snapshot
echo "$snapshot" >> "$SNAPSHOT_FILE"

# ==============================================================================
# FORMATTED OUTPUT
# ==============================================================================
echo ""
echo "GitHub Stats:"
printf "  Stars: %-6s  Forks: %-6s  Watchers: %-6s  Open Issues: %s\n" "$stars" "$forks" "$watchers" "$issues"
echo ""

echo "GitHub Traffic (14d):"
printf "  Clones: %s total, %s unique\n" "$clones_total" "$clones_unique"
printf "  Views:  %s total, %s unique\n" "$views_total" "$views_unique"
echo ""

echo "NPM Downloads:"
printf "  Last 7 days:  %s\n" "$npm_7d"
printf "  Last 30 days: %s\n" "$npm_30d"
echo ""

echo "NPM Daily Downloads (last 14 days):"
echo "$npm_daily" | jq -r '.[] | "\(.day): \(.downloads)"' 2>/dev/null | while read -r day_data; do
  day=$(echo "$day_data" | cut -d':' -f1)
  downloads=$(echo "$day_data" | cut -d':' -f2 | xargs)
  # Simple bar chart (max 50 chars)
  bar_width=$((downloads > 0 ? (downloads / 2) : 0))
  bar_width=$((bar_width > 50 ? 50 : bar_width))
  printf "  %s: " "$day"
  printf '%*s' "$bar_width" | tr ' ' '█'
  printf " %d\n" "$downloads"
done
echo ""

echo "Top Referrers:"
echo "$referrers" | jq -r '.[] | "  \(.referrer): \(.count) (\(.uniques) unique)"' 2>/dev/null || echo "  (none)"
echo ""

echo "Popular Paths:"
echo "$popular_paths" | jq -r '.[] | "  \(.path): \(.count) (\(.uniques) unique)"' 2>/dev/null | head -5 || echo "  (none)"
echo ""

echo "Top Release Downloads:"
echo "$releases" | jq -r '.[] | "  \(.tag_name): \(.downloads) downloads (published \(.published_at | split("T")[0]))"' 2>/dev/null | head -5 || echo "  (none)"
echo ""

echo "NPM Publish History (last 5 versions):"
echo "$npm_publish_history" | jq -r '.[] | "  \(.version): \(.published | split("T")[0])"' 2>/dev/null || echo "  (none)"
echo ""

echo "MCP Registry:"
printf "  Active versions: %s\n" "$mcp_version_count"
printf "  Latest published: %s\n" "$mcp_latest"
echo ""

# ==============================================================================
# DIFF WITH PREVIOUS SNAPSHOT
# ==============================================================================
echo "=== Notable Changes Since Last Snapshot ==="
if [ -f "$SNAPSHOT_FILE" ] && [ $(wc -l < "$SNAPSHOT_FILE") -gt 1 ]; then
  prev_snapshot=$(tail -2 "$SNAPSHOT_FILE" | head -1)
  curr_snapshot=$(tail -1 "$SNAPSHOT_FILE")

  prev_stars=$(echo "$prev_snapshot" | jq '.github.stars // 0' 2>/dev/null || echo "0")
  curr_stars=$(echo "$curr_snapshot" | jq '.github.stars // 0' 2>/dev/null || echo "0")

  prev_npm_7d=$(echo "$prev_snapshot" | jq '.npm.downloads_7d // 0' 2>/dev/null || echo "0")
  curr_npm_7d=$(echo "$curr_snapshot" | jq '.npm.downloads_7d // 0' 2>/dev/null || echo "0")

  prev_clones=$(echo "$prev_snapshot" | jq '.github.traffic_14d.clones.total // 0' 2>/dev/null || echo "0")
  curr_clones=$(echo "$curr_snapshot" | jq '.github.traffic_14d.clones.total // 0' 2>/dev/null || echo "0")

  prev_views=$(echo "$prev_snapshot" | jq '.github.traffic_14d.views.total // 0' 2>/dev/null || echo "0")
  curr_views=$(echo "$curr_snapshot" | jq '.github.traffic_14d.views.total // 0' 2>/dev/null || echo "0")

  # Safely handle jq parsing
  if [ "$prev_stars" != "null" ] && [ "$curr_stars" != "null" ]; then
    stars_delta=$((curr_stars - prev_stars))
  else
    stars_delta=0
  fi

  if [ "$prev_npm_7d" != "null" ] && [ "$curr_npm_7d" != "null" ]; then
    npm_7d_delta=$((curr_npm_7d - prev_npm_7d))
  else
    npm_7d_delta=0
  fi

  if [ "$prev_clones" != "null" ] && [ "$curr_clones" != "null" ]; then
    clones_delta=$((curr_clones - prev_clones))
  else
    clones_delta=0
  fi

  if [ "$prev_views" != "null" ] && [ "$curr_views" != "null" ]; then
    views_delta=$((curr_views - prev_views))
  else
    views_delta=0
  fi

  echo ""
  [ "$stars_delta" != "0" ] && printf "  ⭐  Stars: %+d (now %d)\n" "$stars_delta" "$curr_stars"
  [ "$npm_7d_delta" != "0" ] && printf "  📦 NPM 7d: %+d (now %d)\n" "$npm_7d_delta" "$curr_npm_7d"
  [ "$clones_delta" != "0" ] && printf "  📥 Clones: %+d (now %d)\n" "$clones_delta" "$curr_clones"
  [ "$views_delta" != "0" ] && printf "  👁  Views:  %+d (now %d)\n" "$views_delta" "$curr_views"

  # Check if there are no changes
  if [ "$stars_delta" = "0" ] && [ "$npm_7d_delta" = "0" ] && [ "$clones_delta" = "0" ] && [ "$views_delta" = "0" ]; then
    echo "  (no significant changes)"
  fi
else
  echo "  (no previous snapshot)"
fi
echo ""

echo "Snapshot saved: $SNAPSHOT_FILE"
