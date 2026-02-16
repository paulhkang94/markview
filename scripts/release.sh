#!/bin/bash
set -euo pipefail

# MarkView — Release script: bump version, test, build, install
# Usage: bash scripts/release.sh [--bump major|minor|patch] [--skip-tests]
# Default: patch bump

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PLIST="$PROJECT_DIR/Sources/MarkView/Info.plist"
BUMP="patch"
SKIP_TESTS=false

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
        *)
            echo "Unknown option: $1"
            echo "Usage: bash scripts/release.sh [--bump major|minor|patch] [--skip-tests]"
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

# Step 4: Update Info.plist
plutil -replace CFBundleShortVersionString -string "$NEW_VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"
echo "Updated Info.plist"

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
bash "$PROJECT_DIR/scripts/bundle.sh" --install

# Step 7: Install CLI
echo ""
echo "--- Installing CLI ---"
bash "$PROJECT_DIR/scripts/install-cli.sh"

# Step 8: Summary
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
