#!/usr/bin/env bash
# tap-audit.sh — compare latest GitHub release version with Homebrew tap version
# Exit 0 = match, Exit 1 = mismatch (prints fix command)
set -euo pipefail

REPO="paulhkang94/markview"
TAP_CASK_URL="https://raw.githubusercontent.com/paulhkang94/homebrew-markview/main/Casks/markview.rb"

LATEST=$(gh release list --repo "$REPO" --limit 1 --json tagName --jq '.[0].tagName' | sed 's/^v//')

CASK=$(curl -fsSL "$TAP_CASK_URL" 2>/dev/null || echo "")
TAP_VER=$(echo "$CASK" | grep -oE 'version "[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")

if [[ -z "$TAP_VER" ]]; then
  echo "ERROR: could not fetch tap cask from ${TAP_CASK_URL}"
  exit 1
fi

if [[ "$TAP_VER" == "$LATEST" ]]; then
  echo "✓ Homebrew tap v${TAP_VER} matches latest release v${LATEST}"
  exit 0
else
  echo "MISMATCH: Homebrew tap v${TAP_VER} ≠ latest release v${LATEST}"
  echo ""
  echo "To fix:"
  echo "  gh workflow run tap-update.yml --repo ${REPO} --field tag_name=v${LATEST}"
  exit 1
fi
