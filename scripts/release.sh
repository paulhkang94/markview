#!/bin/bash
set -euo pipefail

# MarkView — Release script: bump version, test, build, install
# Usage: bash scripts/release.sh [--bump major|minor|patch] [--skip-tests] [--notarize]
# Default: patch bump

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PLIST="$PROJECT_DIR/Sources/MarkView/Info.plist"
BUMP="patch"
SKIP_TESTS=false
DO_NOTARIZE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bump)
            BUMP="$2"
            shift 2
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --notarize)
            DO_NOTARIZE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: bash scripts/release.sh [--bump major|minor|patch] [--skip-tests] [--notarize]"
            exit 1
            ;;
    esac
done

if [[ "$BUMP" != "major" && "$BUMP" != "minor" && "$BUMP" != "patch" ]]; then
    echo "ERROR: --bump must be major, minor, or patch (got: $BUMP)"
    exit 1
fi

echo "=== MarkView Release ==="

# Step 1: Read current version from Info.plist
CURRENT_VERSION=$(plutil -extract CFBundleShortVersionString raw "$PLIST")
echo "Current version: $CURRENT_VERSION"

# Step 2: Bump version
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
esac
NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo "New version: $NEW_VERSION ($BUMP bump)"

# Step 3: Compute build number from git commit count
BUILD_NUMBER=$(git rev-list --count HEAD)
BUILD_NUMBER=$((BUILD_NUMBER + 1))  # +1 for the upcoming commit
echo "Build number: $BUILD_NUMBER"

# Step 4: Update all version sources
plutil -replace CFBundleShortVersionString -string "$NEW_VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"
echo "Updated Info.plist"

# Quick Look Info.plist
QL_PLIST="$PROJECT_DIR/Sources/MarkViewQuickLook/Info.plist"
if [ -f "$QL_PLIST" ]; then
    plutil -replace CFBundleShortVersionString -string "$NEW_VERSION" "$QL_PLIST"
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$QL_PLIST"
    echo "Updated QuickLook Info.plist"
fi

# MCP server version
MCP_MAIN="$PROJECT_DIR/Sources/MarkViewMCPServer/main.swift"
if [ -f "$MCP_MAIN" ]; then
    sed -i '' "s/version: \"[0-9]*\.[0-9]*\.[0-9]*\"/version: \"$NEW_VERSION\"/" "$MCP_MAIN"
    echo "Updated MCP server version"
fi

# Step 5: Run tests (unless --skip-tests)
if [ "$SKIP_TESTS" = false ]; then
    echo ""
    echo "--- Running verify.sh ---"
    bash "$PROJECT_DIR/verify.sh"
    echo ""
else
    echo ""
    echo "--- Skipping tests (--skip-tests) ---"
    echo ""
fi

# Step 6: Build + install app bundle
echo "--- Building and installing app bundle ---"
BUNDLE_FLAGS="--install"

# Auto-enable notarization if credentials exist (env vars or Keychain)
if [ "$DO_NOTARIZE" = false ]; then
    _key_id="${NOTARIZE_KEY_ID:-$(security find-generic-password -a "$USER" -s "NOTARIZE_KEY_ID" -w 2>/dev/null || true)}"
    _issuer_id="${NOTARIZE_ISSUER_ID:-$(security find-generic-password -a "$USER" -s "NOTARIZE_ISSUER_ID" -w 2>/dev/null || true)}"
    if [ -n "$_key_id" ] && [ -n "$_issuer_id" ]; then
        export NOTARIZE_KEY_ID="$_key_id"
        export NOTARIZE_ISSUER_ID="$_issuer_id"
        echo "Notarization credentials detected (Keychain/env) — auto-enabling --notarize"
        DO_NOTARIZE=true
    fi
fi
if [ "$DO_NOTARIZE" = true ]; then
    BUNDLE_FLAGS="$BUNDLE_FLAGS --notarize"
fi
bash "$PROJECT_DIR/scripts/bundle.sh" $BUNDLE_FLAGS

# Step 7: Install CLI
echo ""
echo "--- Installing CLI ---"
bash "$PROJECT_DIR/scripts/install-cli.sh"

# Step 8: Restart app if running (ensures user gets the new binary)
echo ""
echo "--- Restarting MarkView if running ---"
if pgrep -x MarkView > /dev/null 2>&1; then
    pkill -x MarkView
    sleep 1
    open -a MarkView
    echo "Killed old process and relaunched"
else
    echo "MarkView was not running"
fi

# Step 9: Verify the installed binary has the expected version
echo ""
echo "--- Post-install verification ---"
INSTALLED_VERSION=$(plutil -extract CFBundleShortVersionString raw /Applications/MarkView.app/Contents/Info.plist 2>/dev/null || echo "?")
if [ "$INSTALLED_VERSION" = "$NEW_VERSION" ]; then
    echo "Installed version: $INSTALLED_VERSION"
else
    echo "WARNING: Installed version ($INSTALLED_VERSION) does not match expected ($NEW_VERSION)"
fi

# Verify dark mode CSS is present in binary (regression guard)
if strings /Applications/MarkView.app/Contents/MacOS/MarkView | grep -q 'color: #e6edf3'; then
    echo "Dark mode CSS: present in binary"
else
    echo "WARNING: Dark mode CSS NOT found in binary"
fi

# Step 11: Summary
echo ""
echo "=== Released MarkView v$NEW_VERSION (build $BUILD_NUMBER) ==="
echo ""
echo "Installed:"
echo "  /Applications/MarkView.app"
echo "  ~/.local/bin/mdpreview"
echo ""
echo "Next steps:"
echo "  git add Sources/MarkView/Info.plist"
echo "  git commit -m 'Release v$NEW_VERSION'"
echo "  git tag v$NEW_VERSION"
echo "  git push origin main --tags"
if [ "$DO_NOTARIZE" = true ]; then
    echo ""
    echo "Notarization: completed (ticket stapled to app bundle)"
else
    echo ""
    echo "Notarization: skipped (use --notarize to sign + notarize for distribution)"
fi
