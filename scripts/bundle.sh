#!/bin/bash
set -euo pipefail

# MarkView — Build .app bundle using xcodebuild (XcodeGen project)
# Usage: bash scripts/bundle.sh [--install] [--notarize]
#
# Prerequisites: brew install xcodegen && xcodegen generate

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="MarkView"
BUNDLE_ID="com.markview.app"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications/$APP_NAME.app"

# Entitlements paths
ENTITLEMENTS_APP="$PROJECT_DIR/Sources/MarkView/MarkView.entitlements"
ENTITLEMENTS_QL="$PROJECT_DIR/Sources/MarkViewQuickLook/MarkViewQuickLook.entitlements"

# Parse arguments
DO_INSTALL=false
DO_NOTARIZE=false
for arg in "$@"; do
    case "$arg" in
        --install) DO_INSTALL=true ;;
        --notarize) DO_NOTARIZE=true ;;
        *) echo "Unknown option: $arg"; echo "Usage: bash scripts/bundle.sh [--install] [--notarize]"; exit 1 ;;
    esac
done

# Auto-detect signing identity: Developer ID if available, fall back to ad-hoc
if security find-identity -v | grep -q "Developer ID Application"; then
    SIGN_IDENTITY="Developer ID Application"
    SIGN_FLAGS=(--timestamp --options runtime)
    echo "Signing identity: Developer ID Application"
else
    SIGN_IDENTITY="-"
    SIGN_FLAGS=()
    echo "Signing identity: ad-hoc (Developer ID not found)"
    if [ "$DO_NOTARIZE" = true ]; then
        echo "ERROR: --notarize requires Developer ID signing"
        exit 1
    fi
fi

PLIST="$PROJECT_DIR/Sources/MarkView/Info.plist"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$PLIST" 2>/dev/null || echo "unknown")
BUILD=$(plutil -extract CFBundleVersion raw "$PLIST" 2>/dev/null || echo "?")
echo "=== Building $APP_NAME.app v$VERSION (build $BUILD) ==="

# Step 1: Ensure .xcodeproj exists (XcodeGen)
if [ ! -d "$PROJECT_DIR/$APP_NAME.xcodeproj" ]; then
    echo "--- Generating Xcode project ---"
    if command -v xcodegen &> /dev/null; then
        xcodegen generate --spec "$PROJECT_DIR/project.yml" --project "$PROJECT_DIR"
        echo "✓ Xcode project generated"
    else
        echo "ERROR: xcodegen not found. Install with: brew install xcodegen"
        exit 1
    fi
fi

# Step 2: Build with xcodebuild (handles app + extension + signing order)
echo "--- Building with xcodebuild ---"
XCODE_BUILD_DIR="$PROJECT_DIR/build/Build/Products/Release"
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$PROJECT_DIR/build" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | tail -5
echo "✓ xcodebuild complete"

# Step 3: Copy built .app to project root
BUILT_APP="$XCODE_BUILD_DIR/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "ERROR: Built app not found at $BUILT_APP"
    echo "Checking build directory..."
    find "$PROJECT_DIR/build" -name "*.app" -maxdepth 5 2>/dev/null || true
    exit 1
fi
rm -rf "$APP_DIR"
cp -R "$BUILT_APP" "$APP_DIR"
echo "✓ App bundle copied to $APP_DIR"

# Step 4: Build and embed MCP server (still an SPM target)
MCP_NAME="MarkViewMCPServer"
MCP_BIN_NAME="markview-mcp-server"
echo "--- Building MCP server (SPM) ---"
swift build -c release --product "$MCP_NAME" 2>&1 | tail -3
SPM_BUILD_DIR=".build/release"
if [ -f "$SPM_BUILD_DIR/$MCP_NAME" ]; then
    cp "$SPM_BUILD_DIR/$MCP_NAME" "$APP_DIR/Contents/MacOS/$MCP_BIN_NAME"
    codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "$APP_DIR/Contents/MacOS/$MCP_BIN_NAME" 2>/dev/null && echo "✓ MCP server embedded and signed" || echo "✓ MCP server embedded (unsigned)"
else
    echo "⚠ MCP server binary not found — skipping (build with: swift build -c release --product MarkViewMCPServer)"
fi

# Step 5: Re-sign the outer .app bundle (after embedding MCP server)
ENTITLEMENTS_APP_FLAGS=()
if [ -f "$ENTITLEMENTS_APP" ]; then
    ENTITLEMENTS_APP_FLAGS=(--entitlements "$ENTITLEMENTS_APP")
fi
codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "${ENTITLEMENTS_APP_FLAGS[@]+"${ENTITLEMENTS_APP_FLAGS[@]}"}" "$APP_DIR" 2>/dev/null && echo "✓ App bundle re-signed" || echo "✓ App bundle (unsigned)"

echo ""
echo "✓ Bundle created at: $APP_DIR"

# Step 6: Verify bundle structure
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

QL_NAME="MarkViewQuickLook"
QL_APPEX_DIR="$APP_DIR/Contents/PlugIns/$QL_NAME.appex"
if [ -f "$QL_APPEX_DIR/Contents/MacOS/$QL_NAME" ]; then
    echo "  ✓ Quick Look extension exists"
else
    echo "  ⚠ Quick Look extension missing (non-fatal)"
fi

# Verify code signature
if codesign --verify --deep --strict "$APP_DIR" 2>/dev/null; then
    echo "  ✓ Code signature valid"
else
    echo "  ⚠ Code signature verification failed (non-fatal for ad-hoc)"
fi

if [ "$VALID" = true ]; then
    echo ""
    echo "=== Bundle verification passed ==="
else
    echo ""
    echo "=== Bundle verification FAILED ==="
    exit 1
fi

# Step 7: Install if requested
if [ "$DO_INSTALL" = true ]; then
    echo ""
    echo "--- Installing to /Applications ---"
    rm -rf "$INSTALL_DIR"
    cp -R "$APP_DIR" "$INSTALL_DIR"

    # Strip quarantine for all local installs — notarization only applies to
    # downloads (Homebrew, GitHub Releases). Local bundle.sh --install is trusted.
    xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true

    # Register with Launch Services
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -f "$INSTALL_DIR"
        echo "✓ Registered with Launch Services"
    fi

    # Register Quick Look extension with pluginkit
    QL_INSTALLED="$INSTALL_DIR/Contents/PlugIns/MarkViewQuickLook.appex"
    if [ -d "$QL_INSTALLED" ]; then
        pluginkit -a "$QL_INSTALLED" 2>/dev/null && echo "✓ Quick Look extension registered" || echo "⚠ Quick Look extension registration failed (needs Developer ID for Finder spacebar — use qlmanage -p to test)"
    fi

    echo ""
    echo "✓ Installed to $INSTALL_DIR"
    echo "Done! Right-click any .md file → Open With → MarkView"
    echo "Test Quick Look: qlmanage -p /path/to/file.md"
fi

# Step 8: Notarize if requested
if [ "$DO_NOTARIZE" = true ]; then
    TARGET_APP="$APP_DIR"
    if [ "$DO_INSTALL" = true ]; then
        TARGET_APP="$INSTALL_DIR"
    fi
    echo ""
    bash "$PROJECT_DIR/scripts/notarize.sh" "$TARGET_APP"
fi
