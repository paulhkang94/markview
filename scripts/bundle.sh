#!/bin/bash
set -euo pipefail

# MarkView — Build .app bundle from SPM executable
# Usage: bash scripts/bundle.sh [--install] [--notarize]

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="MarkView"
BUNDLE_ID="com.markview.app"
BUILD_DIR=".build/release"
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

# Step 1: Build release
echo "--- Building release binary ---"
swift build -c release 2>&1 | tail -3
echo "✓ Release build complete"

# Step 2: Create .app bundle structure
echo "--- Creating app bundle ---"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Step 3: Copy executable (signed later with the full bundle)
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
echo "✓ Executable copied"

# Step 4: Copy SPM resource bundle into Contents/Resources/ (standard macOS location)
# SPM's generated Bundle.module places the bundle at the .app root, but macOS app
# translocation (Gatekeeper) only copies Contents/ — so root-level bundles get lost.
# ResourceBundle.swift searches Contents/Resources/ first, then falls back to .app root.
SPM_BUNDLE="$BUILD_DIR/MarkView_MarkView.bundle"
if [ -d "$SPM_BUNDLE" ]; then
    cp -R "$SPM_BUNDLE" "$APP_DIR/Contents/Resources/MarkView_MarkView.bundle"
    echo "✓ SPM resource bundle copied to Contents/Resources/"
else
    echo "⚠ SPM resource bundle not found at $SPM_BUNDLE — app will crash at launch!"
    exit 1
fi

# Also copy resources to Contents/Resources/ for direct access and AppIcon
if [ -d "Sources/MarkView/Resources" ]; then
    cp Sources/MarkView/Resources/AppIcon.icns "$APP_DIR/Contents/Resources/" 2>/dev/null || true
    echo "✓ App icon copied"
fi

# Step 5: Generate Info.plist
cp "$PROJECT_DIR/Sources/MarkView/Info.plist" "$APP_DIR/Contents/Info.plist"
echo "✓ Info.plist copied"

# Step 6: Create PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

# Step 6b: Embed Quick Look extension (.appex)
QL_NAME="MarkViewQuickLook"
QL_APPEX_DIR="$APP_DIR/Contents/PlugIns/$QL_NAME.appex"
QL_PLIST="$PROJECT_DIR/Sources/MarkViewQuickLook/Info.plist"

echo "--- Embedding Quick Look extension ---"
mkdir -p "$QL_APPEX_DIR/Contents/MacOS"

if [ -f "$BUILD_DIR/$QL_NAME" ]; then
    cp "$BUILD_DIR/$QL_NAME" "$QL_APPEX_DIR/Contents/MacOS/$QL_NAME"
    cp "$QL_PLIST" "$QL_APPEX_DIR/Contents/Info.plist"
    echo -n "XPC!????" > "$QL_APPEX_DIR/Contents/PkgInfo"
    # Sign extension before parent app (signing order: inner → outer)
    ENTITLEMENTS_QL_FLAGS=()
    if [ -f "$ENTITLEMENTS_QL" ]; then
        ENTITLEMENTS_QL_FLAGS=(--entitlements "$ENTITLEMENTS_QL")
    fi
    codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "${ENTITLEMENTS_QL_FLAGS[@]+"${ENTITLEMENTS_QL_FLAGS[@]}"}" "$QL_APPEX_DIR" 2>/dev/null && echo "✓ Quick Look extension embedded and signed" || echo "✓ Quick Look extension embedded (unsigned)"
else
    echo "⚠ Quick Look extension binary not found — skipping"
fi

# Step 6c: Embed MCP server binary
MCP_NAME="MarkViewMCPServer"
MCP_BIN_NAME="markview-mcp-server"
echo "--- Embedding MCP server ---"
if [ -f "$BUILD_DIR/$MCP_NAME" ]; then
    cp "$BUILD_DIR/$MCP_NAME" "$APP_DIR/Contents/MacOS/$MCP_BIN_NAME"
    codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "$APP_DIR/Contents/MacOS/$MCP_BIN_NAME" 2>/dev/null && echo "✓ MCP server embedded and signed" || echo "✓ MCP server embedded (unsigned)"
else
    echo "⚠ MCP server binary not found — skipping (build with: swift build -c release --product MarkViewMCPServer)"
fi

# Sign the main executable
ENTITLEMENTS_APP_FLAGS=()
if [ -f "$ENTITLEMENTS_APP" ]; then
    ENTITLEMENTS_APP_FLAGS=(--entitlements "$ENTITLEMENTS_APP")
fi
codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "${ENTITLEMENTS_APP_FLAGS[@]+"${ENTITLEMENTS_APP_FLAGS[@]}"}" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null && echo "✓ Main executable signed" || echo "✓ Main executable (unsigned)"

# Sign the outer .app bundle
codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "${ENTITLEMENTS_APP_FLAGS[@]+"${ENTITLEMENTS_APP_FLAGS[@]}"}" "$APP_DIR" 2>/dev/null && echo "✓ App bundle signed" || echo "✓ App bundle (unsigned)"

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

# Verify SPM resource bundle in Contents/Resources/ (prevents crash at runtime)
if [ -f "$APP_DIR/Contents/Resources/MarkView_MarkView.bundle/Resources/template.html" ]; then
    echo "  ✓ SPM resource bundle has template.html"
else
    echo "  ✗ SPM resource bundle missing template.html (app will crash at launch!)"
    VALID=false
fi

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

# Step 8: Install if requested
if [ "$DO_INSTALL" = true ]; then
    echo ""
    echo "--- Installing to /Applications ---"
    rm -rf "$INSTALL_DIR"
    cp -R "$APP_DIR" "$INSTALL_DIR"

    if [ "$SIGN_IDENTITY" = "-" ]; then
        # Only strip quarantine for ad-hoc signed builds
        xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
    fi

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

# Step 9: Notarize if requested
if [ "$DO_NOTARIZE" = true ]; then
    TARGET_APP="$APP_DIR"
    if [ "$DO_INSTALL" = true ]; then
        TARGET_APP="$INSTALL_DIR"
    fi
    echo ""
    bash "$PROJECT_DIR/scripts/notarize.sh" "$TARGET_APP"
fi
