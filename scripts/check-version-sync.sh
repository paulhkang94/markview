#!/bin/bash
set -euo pipefail

# Verify all version strings across the project are in sync.
# The canonical version is read from Sources/MarkView/Info.plist.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PLIST="$PROJECT_DIR/Sources/MarkView/Info.plist"

# Read plist values using Python (cross-platform: works on macOS + Linux CI).
# plutil is macOS-only and fails silently on Ubuntu.
plist_value() {
    python3 -c "
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    d = plistlib.load(f)
print(d.get(sys.argv[2], ''))
" "$1" "$2" 2>/dev/null || true
}

CANONICAL=$(plist_value "$PLIST" "CFBundleShortVersionString")

if [ -z "$CANONICAL" ]; then
    echo "✗ Cannot read version from Info.plist"
    exit 1
fi

CANONICAL_BUILD=$(plist_value "$PLIST" "CFBundleVersion")

echo "Canonical version: $CANONICAL (build $CANONICAL_BUILD)"

ERRORS=0

# Git tag ↔ plist version check (Tier 0: no AI, pure string comparison)
# Note: during a release, plist is bumped BEFORE the tag is created.
# If plist version has no tag yet (unreleased bump), treat as warning not error.
LATEST_TAG=$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 --match "v*" 2>/dev/null | sed 's/^v//' || true)
CANONICAL_TAG_EXISTS=$(git -C "$PROJECT_DIR" tag --list "v$CANONICAL" 2>/dev/null || true)
if [ -z "$LATEST_TAG" ]; then
    echo "  ⚠ No version tags found — skipping tag sync check"
elif [ "$LATEST_TAG" = "$CANONICAL" ]; then
    echo "  ✓ Git tag v$LATEST_TAG matches Info.plist $CANONICAL"
elif [ -z "$CANONICAL_TAG_EXISTS" ]; then
    # Plist was bumped but tag not yet created — this is expected mid-release
    echo "  ⚠ Info.plist is $CANONICAL but no tag v$CANONICAL exists yet (unreleased bump — run: git tag v$CANONICAL && git push --tags)"
else
    # Tag exists but doesn't match plist — genuine mismatch
    echo "  ✗ Git tag v$LATEST_TAG does not match Info.plist $CANONICAL"
    echo "    Fix: bash scripts/release.sh --bump patch  (or major/minor)"
    ERRORS=$((ERRORS + 1))
fi

# Warn if commits exist since last tag (unreleased changes)
COMMITS_SINCE_TAG=$(git -C "$PROJECT_DIR" rev-list "v${LATEST_TAG}..HEAD" --count 2>/dev/null || echo "0")
if [ "$COMMITS_SINCE_TAG" -gt 0 ] 2>/dev/null; then
    echo "  ⚠ $COMMITS_SINCE_TAG commit(s) since v$LATEST_TAG — consider bumping version before release"
fi

# Quick Look Info.plist
QL_PLIST="$PROJECT_DIR/Sources/MarkViewQuickLook/Info.plist"
if [ -f "$QL_PLIST" ]; then
    QL_VER=$(plist_value "$QL_PLIST" "CFBundleShortVersionString")
    if [ "$QL_VER" = "$CANONICAL" ]; then
        echo "  ✓ QuickLook CFBundleShortVersionString: $QL_VER"
    else
        echo "  ✗ QuickLook CFBundleShortVersionString: $QL_VER (expected $CANONICAL)"
        ERRORS=$((ERRORS + 1))
    fi
    QL_BUILD=$(plist_value "$QL_PLIST" "CFBundleVersion")
    if [ "$QL_BUILD" = "$CANONICAL_BUILD" ]; then
        echo "  ✓ QuickLook CFBundleVersion: $QL_BUILD"
    else
        echo "  ✗ QuickLook CFBundleVersion: $QL_BUILD (expected $CANONICAL_BUILD)"
        ERRORS=$((ERRORS + 1))
    fi
fi

# MCP server version string
MCP_MAIN="$PROJECT_DIR/Sources/MarkViewMCPServer/main.swift"
if [ -f "$MCP_MAIN" ]; then
    MCP_VER=$(grep -oE 'version: "[0-9]+\.[0-9]+\.[0-9]+"' "$MCP_MAIN" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
    if [ "$MCP_VER" = "$CANONICAL" ]; then
        echo "  ✓ MCP server main.swift: $MCP_VER"
    else
        echo "  ✗ MCP server main.swift: $MCP_VER (expected $CANONICAL)"
        ERRORS=$((ERRORS + 1))
    fi
fi

# npm/package.json, server.json, postinstall.js — all three must match
NPM_PKG="$PROJECT_DIR/npm/package.json"
if [ -f "$NPM_PKG" ]; then
    NPM_VER=$(python3 -c "import json; print(json.load(open('$NPM_PKG'))['version'])" 2>/dev/null || echo "?")
    if [ "$NPM_VER" = "$CANONICAL" ]; then
        echo "  ✓ npm/package.json: $NPM_VER"
    else
        echo "  ✗ npm/package.json: $NPM_VER (expected $CANONICAL)"
        ERRORS=$((ERRORS + 1))
    fi
fi

NPM_SERVER="$PROJECT_DIR/npm/server.json"
if [ -f "$NPM_SERVER" ]; then
    SERVER_VER=$(python3 -c "import json; print(json.load(open('$NPM_SERVER'))['version'])" 2>/dev/null || echo "?")
    if [ "$SERVER_VER" = "$CANONICAL" ]; then
        echo "  ✓ npm/server.json: $SERVER_VER"
    else
        echo "  ✗ npm/server.json: $SERVER_VER (expected $CANONICAL)"
        ERRORS=$((ERRORS + 1))
    fi
fi

NPM_POSTINSTALL="$PROJECT_DIR/npm/scripts/postinstall.js"
if [ -f "$NPM_POSTINSTALL" ]; then
    POST_VER=$(grep -oE 'const VERSION = "[0-9]+\.[0-9]+\.[0-9]+"' "$NPM_POSTINSTALL" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "?")
    if [ "$POST_VER" = "$CANONICAL" ]; then
        echo "  ✓ npm/scripts/postinstall.js: $POST_VER"
    else
        echo "  ✗ npm/scripts/postinstall.js: $POST_VER (expected $CANONICAL)"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Installed app (advisory only — not an error if not installed)
INSTALLED_PLIST="/Applications/MarkView.app/Contents/Info.plist"
if [ -f "$INSTALLED_PLIST" ]; then
    INST_VER=$(plist_value "$INSTALLED_PLIST" "CFBundleShortVersionString")
    if [ "$INST_VER" = "$CANONICAL" ]; then
        echo "  ✓ Installed app: $INST_VER"
    else
        echo "  ⚠ Installed app: $INST_VER (stale — run: bash scripts/bundle.sh --install)"
    fi
fi

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "✗ Version sync failed: $ERRORS mismatches"
    exit 1
else
    echo "✓ All versions in sync"
fi
