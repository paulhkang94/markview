#!/bin/bash
set -euo pipefail

# MarkView — Build .app bundle from SPM executable
# Usage: bash scripts/bundle.sh [--install]

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="MarkView"
BUNDLE_ID="com.markview.app"
BUILD_DIR=".build/release"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications/$APP_NAME.app"

PLIST="$PROJECT_DIR/Sources/MarkView/Info.plist"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$PLIST" 2>/dev/null || echo "unknown")
BUILD=$(plutil -extract CFBundleVersion raw "$PLIST" 2>/dev/null || echo "?")
echo "=== Building $APP_NAME.app v$VERSION (build $BUILD) ==="

# Step 1: Build release
echo "--- Building release binary ---"
swift build -c release 2>&1 | tail -3
echo "✓ Release build complete"

# Step 2: Create .app bundle structure
echo "--- Creating app bundle ---"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Step 3: Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
echo "✓ Executable copied"

# Step 4: Copy resources
if [ -d "Sources/MarkView/Resources" ]; then
    cp Sources/MarkView/Resources/template.html "$APP_DIR/Contents/Resources/" 2>/dev/null || true
    cp Sources/MarkView/Resources/prism-bundle.min.js "$APP_DIR/Contents/Resources/" 2>/dev/null || true
    cp Sources/MarkView/Resources/AppIcon.icns "$APP_DIR/Contents/Resources/" 2>/dev/null || true
    echo "✓ Resources copied"
fi

# Step 5: Generate Info.plist
cp "$PROJECT_DIR/Sources/MarkView/Info.plist" "$APP_DIR/Contents/Info.plist"
echo "✓ Info.plist copied"

# Step 6: Create PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo ""
echo "✓ Bundle created at: $APP_DIR"

# Step 7: Verify bundle structure
echo ""
echo "--- Verifying bundle structure ---"
VALID=true
[ -f "$APP_DIR/Contents/MacOS/$APP_NAME" ] && echo "  ✓ Executable exists" || { echo "  ✗ Missing executable"; VALID=false; }
[ -f "$APP_DIR/Contents/Info.plist" ] && echo "  ✓ Info.plist exists" || { echo "  ✗ Missing Info.plist"; VALID=false; }
[ -f "$APP_DIR/Contents/PkgInfo" ] && echo "  ✓ PkgInfo exists" || { echo "  ✗ Missing PkgInfo"; VALID=false; }

# Verify Info.plist has required keys
if plutil -lint "$APP_DIR/Contents/Info.plist" > /dev/null 2>&1; then
    echo "  ✓ Info.plist is valid"
else
    echo "  ✗ Info.plist is invalid"
    VALID=false
fi

if grep -q "CFBundleDocumentTypes" "$APP_DIR/Contents/Info.plist"; then
    echo "  ✓ Document types registered"
else
    echo "  ✗ Missing document types"
    VALID=false
fi

if [ "$VALID" = true ]; then
    echo ""
    echo "=== Bundle verification passed ==="
else
    echo ""
    echo "=== Bundle verification FAILED ==="
    exit 1
fi

# Step 8: Install if requested
if [ "${1:-}" = "--install" ]; then
    echo ""
    echo "--- Installing to /Applications ---"
    rm -rf "$INSTALL_DIR"
    cp -R "$APP_DIR" "$INSTALL_DIR"
    echo "✓ Installed to $INSTALL_DIR"

    # Register with Launch Services
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -f "$INSTALL_DIR"
        echo "✓ Registered with Launch Services"
    fi

    echo ""
    echo "Done! Right-click any .md file → Open With → MarkView"
fi
