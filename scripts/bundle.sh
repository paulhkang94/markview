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

# Auto-set build number from git commit count — always monotonically increasing,
# never stale regardless of whether a version bump was run. This is the Tier 0
# guardrail: the installed app always shows a unique build number per commit.
GIT_BUILD=$(git rev-list --count HEAD 2>/dev/null || echo "0")
plutil -replace CFBundleVersion -string "$GIT_BUILD" "$PLIST"
# Mirror to QuickLook plist so check-version-sync.sh passes
QL_PLIST="$PROJECT_DIR/Sources/MarkViewQuickLook/Info.plist"
[ -f "$QL_PLIST" ] && plutil -replace CFBundleVersion -string "$GIT_BUILD" "$QL_PLIST"
BUILD="$GIT_BUILD"
echo "=== Building $APP_NAME.app v$VERSION (build $BUILD) ==="

# Step 1: Always regenerate .xcodeproj from project.yml (XcodeGen)
# Must always re-run so new resources (e.g. mermaid.min.js) are picked up.
# xcodeproj references individual files — skipping regeneration means new
# files in Sources/MarkView/Resources/ are silently omitted from the build.
echo "--- Generating Xcode project ---"
if command -v xcodegen &> /dev/null; then
    xcodegen generate --spec "$PROJECT_DIR/project.yml" --project "$PROJECT_DIR"
    echo "✓ Xcode project generated"
else
    echo "ERROR: xcodegen not found. Install with: brew install xcodegen"
    exit 1
fi

# Step 2: Build with xcodebuild (handles app + extension + signing order)
echo "--- Building with xcodebuild ---"
XCODE_BUILD_DIR="$PROJECT_DIR/build/Build/Products/Release"
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$PROJECT_DIR/build" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
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

# Step 5: Re-sign ALL nested code (frameworks, extensions) with timestamp for notarization
# Apple rejects notarization if any nested binary lacks a secure timestamp.
# xcodebuild signs the QL extension but may not use --timestamp.
# SPM frameworks (Sentry) come pre-signed without our timestamp.
echo "--- Re-signing nested code for notarization ---"

# Re-sign frameworks (Sentry.framework, etc.)
find "$APP_DIR/Contents/Frameworks" -type f -perm +111 -name "*.dylib" -o -name "Sentry" 2>/dev/null | while read -r binary; do
    codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "$binary" 2>/dev/null && echo "  ✓ Re-signed: $(basename "$binary")" || true
done
# Re-sign framework bundles
find "$APP_DIR/Contents/Frameworks" -name "*.framework" -maxdepth 1 2>/dev/null | while read -r fw; do
    codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "$fw" 2>/dev/null && echo "  ✓ Re-signed: $(basename "$fw")" || true
done

# Re-sign SPM resource bundles in Contents/Resources/ (MarkView_MarkViewCore.bundle etc.)
# xcodebuild uses ad-hoc (-) for these; we need Developer ID for distribution.
find "$APP_DIR/Contents/Resources" -name "*.bundle" -maxdepth 1 2>/dev/null | while read -r bundle; do
    codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "$bundle" 2>/dev/null && echo "  ✓ Re-signed: $(basename "$bundle")" || true
done

# Re-sign main executable — xcodebuild may sign it ad-hoc when CODE_SIGN_STYLE=Manual
# even when CODE_SIGN_IDENTITY is set to Developer ID Application.
# Gatekeeper rejects "Developer ID outer + ad-hoc inner main executable".
MAIN_BIN="$APP_DIR/Contents/MacOS/$APP_NAME"
if [ -f "$MAIN_BIN" ]; then
    codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "$MAIN_BIN" 2>/dev/null && echo "  ✓ Re-signed: $APP_NAME (main executable)" || true
fi

# Re-sign Quick Look extension with entitlements + timestamp
QL_APPEX="$APP_DIR/Contents/PlugIns/MarkViewQuickLook.appex"
if [ -d "$QL_APPEX" ]; then
    # Generate PkgInfo for the QL extension — xcodebuild omits it for app extensions
    # but macOS expects it (XPC! = package type for XPC/app-extension bundles).
    QL_CONTENTS="$QL_APPEX/Contents"
    if [ ! -f "$QL_CONTENTS/PkgInfo" ]; then
        printf 'XPC!????' > "$QL_CONTENTS/PkgInfo"
        echo "  ✓ Generated PkgInfo for MarkViewQuickLook.appex"
    fi

    ENTITLEMENTS_QL_FLAGS=()
    if [ -f "$ENTITLEMENTS_QL" ]; then
        ENTITLEMENTS_QL_FLAGS=(--entitlements "$ENTITLEMENTS_QL")
    fi
    codesign -s "$SIGN_IDENTITY" -f "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" "${ENTITLEMENTS_QL_FLAGS[@]+"${ENTITLEMENTS_QL_FLAGS[@]}"}" "$QL_APPEX" 2>/dev/null && echo "  ✓ Re-signed: MarkViewQuickLook.appex" || true
fi

# Step 6: Re-sign the outer .app bundle (after all nested re-signing)
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

# Verify code signature — hard failure for Developer ID builds, warning for ad-hoc
if codesign --verify --deep --strict "$APP_DIR" 2>/dev/null; then
    echo "  ✓ Code signature valid"
elif [ "$SIGN_IDENTITY" = "-" ]; then
    echo "  ⚠ Ad-hoc signature (expected — no Developer ID cert found)"
else
    echo "  ✗ Code signature invalid with Developer ID — bundle will be rejected by Gatekeeper"
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
