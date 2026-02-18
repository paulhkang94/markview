#!/bin/bash
set -euo pipefail

# Verify all version strings across the project are in sync.
# The canonical version is read from Sources/MarkView/Info.plist.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PLIST="$PROJECT_DIR/Sources/MarkView/Info.plist"
CANONICAL=$(plutil -extract CFBundleShortVersionString raw "$PLIST" 2>/dev/null || true)

if [ -z "$CANONICAL" ]; then
    echo "✗ Cannot read version from Info.plist"
    exit 1
fi

CANONICAL_BUILD=$(plutil -extract CFBundleVersion raw "$PLIST" 2>/dev/null || true)

echo "Canonical version: $CANONICAL (build $CANONICAL_BUILD)"

ERRORS=0

# Quick Look Info.plist
QL_PLIST="$PROJECT_DIR/Sources/MarkViewQuickLook/Info.plist"
if [ -f "$QL_PLIST" ]; then
    QL_VER=$(plutil -extract CFBundleShortVersionString raw "$QL_PLIST" 2>/dev/null || true)
    if [ "$QL_VER" = "$CANONICAL" ]; then
        echo "  ✓ QuickLook CFBundleShortVersionString: $QL_VER"
    else
        echo "  ✗ QuickLook CFBundleShortVersionString: $QL_VER (expected $CANONICAL)"
        ERRORS=$((ERRORS + 1))
    fi
    QL_BUILD=$(plutil -extract CFBundleVersion raw "$QL_PLIST" 2>/dev/null || true)
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

# Installed app (advisory only — not an error if not installed)
INSTALLED_PLIST="/Applications/MarkView.app/Contents/Info.plist"
if [ -f "$INSTALLED_PLIST" ]; then
    INST_VER=$(plutil -extract CFBundleShortVersionString raw "$INSTALLED_PLIST" 2>/dev/null || true)
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
