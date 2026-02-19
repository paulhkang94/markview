#!/bin/bash
set -euo pipefail
PHASE=${1:-all}
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "=== MarkView Verification ==="

# Sanity-check bootstrap helper behavior (mocked, no network required)
bash "$PROJECT_DIR/scripts/test-bootstrap-swiftpm.sh"

# Bootstrap SwiftPM dependencies (with retries)
bash "$PROJECT_DIR/scripts/bootstrap-swiftpm.sh"

# Version sync check
echo ""
echo "--- Version Sync ---"
bash "$PROJECT_DIR/scripts/check-version-sync.sh"

# Tier 0: Build all targets
echo ""
echo "--- Tier 0: Build ---"
BUILD_OUTPUT=$(swift build 2>&1)
if echo "$BUILD_OUTPUT" | tail -3 | grep -q "Build complete"; then
    echo "✓ All targets build successfully"
else
    echo "✗ Build failed"
    echo "$BUILD_OUTPUT" | tail -10
    exit 1
fi
[ "$PHASE" = "0" ] && exit 0

# Tier 0b: Bundle structure (if bundle.sh has been run)
if [ -d "$PROJECT_DIR/MarkView.app" ]; then
    echo ""
    echo "--- Tier 0b: Bundle Verification ---"
    BUNDLE_OK=true
    [ -f "$PROJECT_DIR/MarkView.app/Contents/MacOS/MarkView" ] && echo "✓ Executable in bundle" || { echo "✗ Missing executable"; BUNDLE_OK=false; }
    [ -f "$PROJECT_DIR/MarkView.app/Contents/Info.plist" ] && echo "✓ Info.plist in bundle" || { echo "✗ Missing Info.plist"; BUNDLE_OK=false; }
    if plutil -lint "$PROJECT_DIR/MarkView.app/Contents/Info.plist" > /dev/null 2>&1; then
        echo "✓ Info.plist is valid"
    else
        echo "✗ Info.plist is invalid"
        BUNDLE_OK=false
    fi
    if grep -q "CFBundleDocumentTypes" "$PROJECT_DIR/MarkView.app/Contents/Info.plist"; then
        echo "✓ Document types registered"
    else
        echo "✗ Missing document types"
        BUNDLE_OK=false
    fi

    # Quick Look extension verification
    APPEX_DIR="$PROJECT_DIR/MarkView.app/Contents/PlugIns/MarkViewQuickLook.appex"
    if [ -d "$APPEX_DIR" ]; then
        [ -f "$APPEX_DIR/Contents/MacOS/MarkViewQuickLook" ] && echo "✓ Quick Look extension executable" || { echo "✗ Missing QL executable"; BUNDLE_OK=false; }
        [ -f "$APPEX_DIR/Contents/Info.plist" ] && echo "✓ Quick Look extension Info.plist" || { echo "✗ Missing QL Info.plist"; BUNDLE_OK=false; }
        if plutil -lint "$APPEX_DIR/Contents/Info.plist" > /dev/null 2>&1; then
            echo "✓ Quick Look Info.plist is valid"
        else
            echo "✗ Quick Look Info.plist is invalid"
            BUNDLE_OK=false
        fi
        if codesign --verify --no-strict "$APPEX_DIR" 2>/dev/null; then
            echo "✓ Quick Look extension is signed"
        else
            echo "⚠ Quick Look extension is unsigned (non-fatal)"
        fi
    else
        echo "⚠ Quick Look extension not in bundle (run: bash scripts/bundle.sh)"
    fi

    # Code signing verification
    echo ""
    echo "  --- Signing Verification ---"
    BUNDLE_APP="$PROJECT_DIR/MarkView.app"
    if codesign --verify --deep --strict "$BUNDLE_APP" 2>/dev/null; then
        echo "  ✓ Code signature valid (deep + strict)"
    else
        echo "  ⚠ Strict signature verification failed (expected for ad-hoc)"
    fi

    # Display signing identity
    SIGN_INFO=$(codesign -d --verbose=2 "$BUNDLE_APP" 2>&1 || true)
    AUTHORITY=$(echo "$SIGN_INFO" | grep "Authority=" | head -1 || true)
    if echo "$SIGN_INFO" | grep -q "Signature=adhoc"; then
        echo "  Signing: ad-hoc"
    elif echo "$AUTHORITY" | grep -q "Developer ID"; then
        echo "  Signing: $AUTHORITY"
    else
        echo "  Signing: unknown"
    fi

    # Gatekeeper assessment (only meaningful for Developer ID signed apps)
    if echo "$AUTHORITY" | grep -q "Developer ID"; then
        if spctl --assess --type execute "$BUNDLE_APP" 2>/dev/null; then
            echo "  ✓ Gatekeeper: accepted"
        else
            echo "  ⚠ Gatekeeper: rejected (may need notarization)"
        fi
    fi

    # Notarization ticket check
    if xcrun stapler validate "$BUNDLE_APP" 2>/dev/null; then
        echo "  ✓ Notarization ticket: stapled"
    else
        echo "  Notarization ticket: not stapled (use --notarize with bundle.sh)"
    fi

    [ "$BUNDLE_OK" = true ] || exit 1
fi

# Tier 1-3: Run full test suite (unit, GFM compliance, performance, golden files, E2E)
echo ""
echo "--- Tier 1-3: Full Test Suite ---"
TEST_OUTPUT=$(swift run MarkViewTestRunner 2>&1)
# Display test output (filter build noise)
echo "$TEST_OUTPUT" | grep -v "^Building\|^Build of\|^\[" | grep -v "^$"

# Check result from the last line
RESULT=$(echo "$TEST_OUTPUT" | tail -1)
if echo "$RESULT" | grep -q "0 failed"; then
    true
else
    echo ""
    echo "=== Some checks failed ==="
    exit 1
fi

# Golden baseline drift check — catches the same issue CI catches
echo ""
echo "--- Golden Drift Check ---"
swift run MarkViewTestRunner --generate-goldens 2>&1 | grep -v "^\[" | grep -v "^$" | grep -v "^Building\|^Build of\|^warning:"
if git diff --quiet Tests/TestRunner/Fixtures/expected/ 2>/dev/null; then
    echo "✓ Golden baselines are up to date"
else
    echo "✗ Golden baselines are stale — commit the updated files:"
    git diff --stat Tests/TestRunner/Fixtures/expected/
    exit 1
fi

# CLI smoke test
echo ""
echo "--- CLI Check ---"
if [ -x "$HOME/.local/bin/mdpreview" ] && file "$HOME/.local/bin/mdpreview" | grep -q "text"; then
    echo "✓ mdpreview CLI is installed (shell script)"
else
    echo "⚠ mdpreview not installed or is not a shell script (run: bash scripts/install-cli.sh)"
fi

echo ""
echo "=== All checks passed ==="

# Extended tests (fuzz + differential) — only with --extended flag
if [ "$PHASE" = "--extended" ]; then
    echo ""
    echo "--- Extended: Fuzz Testing ---"
    swift run MarkViewFuzzTester 2>&1 | grep -v "^\[" | grep -v "^$"

    echo ""
    echo "--- Extended: Differential Testing ---"
    swift run MarkViewDiffTester 2>&1 | grep -v "^\[" | grep -v "^$"

    echo ""
    echo "--- Extended: Visual Regression Tests ---"
    # Generate goldens first (idempotent), then compare
    swift run MarkViewVisualTester --generate-goldens 2>&1 | grep -v "^\[" | grep -v "^$" | grep -v "^Building\|^Build of\|^warning:"
    swift run MarkViewVisualTester 2>&1 | grep -v "^\[" | grep -v "^$" | grep -v "^Building\|^Build of\|^warning:"

    # Quick Look system integration tests
    echo ""
    echo "--- Extended: Quick Look System Integration ---"

    QL_APPEX="/Applications/MarkView.app/Contents/PlugIns/MarkViewQuickLook.appex"
    QL_PASS=0
    QL_FAIL=0
    QL_SKIP=0

    if [ -d "$QL_APPEX" ]; then
        # 1. Bundle structure
        [ -f "$QL_APPEX/Contents/MacOS/MarkViewQuickLook" ] && { echo "  ✓ Extension executable exists"; QL_PASS=$((QL_PASS + 1)); } || { echo "  ✗ Missing extension executable"; QL_FAIL=$((QL_FAIL + 1)); }
        [ -f "$QL_APPEX/Contents/Info.plist" ] && { echo "  ✓ Extension Info.plist exists"; QL_PASS=$((QL_PASS + 1)); } || { echo "  ✗ Missing extension Info.plist"; QL_FAIL=$((QL_FAIL + 1)); }
        [ -f "$QL_APPEX/Contents/PkgInfo" ] && { echo "  ✓ Extension PkgInfo exists"; QL_PASS=$((QL_PASS + 1)); } || { echo "  ✗ Missing PkgInfo"; QL_FAIL=$((QL_FAIL + 1)); }

        # 2. PkgInfo type
        PKGTYPE=$(cat "$QL_APPEX/Contents/PkgInfo" 2>/dev/null || true)
        if [[ "$PKGTYPE" == "XPC!????" ]]; then
            echo "  ✓ PkgInfo declares XPC service type"; QL_PASS=$((QL_PASS + 1))
        else
            echo "  ✗ PkgInfo wrong type: got '$PKGTYPE', expected 'XPC!????'"; QL_FAIL=$((QL_FAIL + 1))
        fi

        # 3. Info.plist validity
        if plutil -lint "$QL_APPEX/Contents/Info.plist" > /dev/null 2>&1; then
            echo "  ✓ Extension Info.plist is valid XML"; QL_PASS=$((QL_PASS + 1))
        else
            echo "  ✗ Extension Info.plist is invalid"; QL_FAIL=$((QL_FAIL + 1))
        fi

        # 4. Required plist keys
        PLIST_CONTENT=$(plutil -convert xml1 -o - "$QL_APPEX/Contents/Info.plist" 2>/dev/null || true)
        for KEY in NSExtensionPointIdentifier NSExtensionPrincipalClass QLSupportedContentTypes CFBundleIdentifier; do
            if echo "$PLIST_CONTENT" | grep -q "$KEY"; then
                echo "  ✓ Info.plist has $KEY"; QL_PASS=$((QL_PASS + 1))
            else
                echo "  ✗ Info.plist missing $KEY"; QL_FAIL=$((QL_FAIL + 1))
            fi
        done

        # 5. Extension point identifier
        EXT_POINT=$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$QL_APPEX/Contents/Info.plist" 2>/dev/null || true)
        if [[ "$EXT_POINT" == "com.apple.quicklook.preview" ]]; then
            echo "  ✓ Extension point: com.apple.quicklook.preview"; QL_PASS=$((QL_PASS + 1))
        else
            echo "  ✗ Wrong extension point: '$EXT_POINT'"; QL_FAIL=$((QL_FAIL + 1))
        fi

        # 6. Supported content types include markdown
        if echo "$PLIST_CONTENT" | grep -q "net.daringfireball.markdown"; then
            echo "  ✓ Supports net.daringfireball.markdown"; QL_PASS=$((QL_PASS + 1))
        else
            echo "  ✗ Missing markdown content type"; QL_FAIL=$((QL_FAIL + 1))
        fi

        # 7. Code signing
        if codesign --verify --no-strict "$QL_APPEX" 2>/dev/null; then
            echo "  ✓ Extension is code-signed"; QL_PASS=$((QL_PASS + 1))
        else
            echo "  ⚠ Extension is unsigned (ad-hoc signing may have been stripped)"; QL_SKIP=$((QL_SKIP + 1))
        fi

        # 8. Signing identity check (Developer ID vs ad-hoc)
        SIGN_INFO=$(codesign -dvv "$QL_APPEX" 2>&1 || true)
        if echo "$SIGN_INFO" | grep -q "Signature=adhoc"; then
            echo "  ⚠ Ad-hoc signed — Finder spacebar preview requires Developer ID signing + notarization"; QL_SKIP=$((QL_SKIP + 1))
        elif echo "$SIGN_INFO" | grep -q "Developer ID"; then
            echo "  ✓ Developer ID signed — Finder spacebar preview should work"; QL_PASS=$((QL_PASS + 1))
        fi

        # 9. Binary architecture
        ARCH=$(file "$QL_APPEX/Contents/MacOS/MarkViewQuickLook" 2>/dev/null || true)
        if echo "$ARCH" | grep -q "arm64"; then
            echo "  ✓ Binary is arm64"; QL_PASS=$((QL_PASS + 1))
        elif echo "$ARCH" | grep -q "Mach-O"; then
            echo "  ✓ Binary is valid Mach-O"; QL_PASS=$((QL_PASS + 1))
        else
            echo "  ✗ Binary architecture issue: $ARCH"; QL_FAIL=$((QL_FAIL + 1))
        fi

        # 10. Parent app bundle identifier consistency
        PARENT_ID=$(plutil -extract CFBundleIdentifier raw "/Applications/MarkView.app/Contents/Info.plist" 2>/dev/null || true)
        EXT_ID=$(plutil -extract CFBundleIdentifier raw "$QL_APPEX/Contents/Info.plist" 2>/dev/null || true)
        if [[ "$EXT_ID" == "$PARENT_ID."* ]]; then
            echo "  ✓ Extension ID ($EXT_ID) is child of parent ($PARENT_ID)"; QL_PASS=$((QL_PASS + 1))
        else
            echo "  ⚠ Extension ID ($EXT_ID) is not prefixed by parent ($PARENT_ID) — may cause signing issues"; QL_SKIP=$((QL_SKIP + 1))
        fi

        # 11. Version sync between extension and parent
        PARENT_VER=$(plutil -extract CFBundleShortVersionString raw "/Applications/MarkView.app/Contents/Info.plist" 2>/dev/null || true)
        EXT_VER=$(plutil -extract CFBundleShortVersionString raw "$QL_APPEX/Contents/Info.plist" 2>/dev/null || true)
        if [[ "$PARENT_VER" == "$EXT_VER" ]]; then
            echo "  ✓ Version sync: parent=$PARENT_VER, extension=$EXT_VER"; QL_PASS=$((QL_PASS + 1))
        else
            echo "  ✗ Version mismatch: parent=$PARENT_VER, extension=$EXT_VER"; QL_FAIL=$((QL_FAIL + 1))
        fi

        # 12. pluginkit registration status
        if pluginkit -m -p com.apple.quicklook.preview 2>/dev/null | grep -q "com.markview"; then
            echo "  ✓ Extension registered with pluginkit"; QL_PASS=$((QL_PASS + 1))
        else
            # Developer ID signed apps MUST register — ad-hoc gets a pass
            APPEX_SIGN_INFO=$(codesign -dvv "$QL_APPEX" 2>&1 || true)
            if echo "$APPEX_SIGN_INFO" | grep -q "Developer ID"; then
                echo "  ✗ Extension NOT registered with pluginkit (Developer ID signed — this is a bug)"; QL_FAIL=$((QL_FAIL + 1))
            else
                echo "  ⚠ Extension NOT registered with pluginkit (expected for ad-hoc signed apps)"; QL_SKIP=$((QL_SKIP + 1))
            fi
        fi

        # 13. UTType recognition for .md files
        FIXTURE="$PROJECT_DIR/Tests/TestRunner/Fixtures/basic.md"
        if [ -f "$FIXTURE" ]; then
            MD_TYPE=$(mdls -attr kMDItemContentType "$FIXTURE" 2>/dev/null | grep -o '".*"' | tr -d '"' || true)
            if [[ "$MD_TYPE" == "net.daringfireball.markdown" ]]; then
                echo "  ✓ System recognizes .md as net.daringfireball.markdown"; QL_PASS=$((QL_PASS + 1))
            elif [[ -n "$MD_TYPE" ]]; then
                echo "  ⚠ System sees .md as '$MD_TYPE' (not net.daringfireball.markdown)"; QL_SKIP=$((QL_SKIP + 1))
            else
                echo "  ⚠ Could not determine UTType for .md files"; QL_SKIP=$((QL_SKIP + 1))
            fi
        fi

        echo ""
        echo "  Quick Look E2E: $QL_PASS passed, $QL_FAIL failed, $QL_SKIP skipped/advisory"
        if (( QL_FAIL > 0 )); then
            echo "  ✗ Quick Look integration has failures"
            exit 1
        fi
    else
        echo "  ⊘ Quick Look extension not installed — skipping (run: bash scripts/bundle.sh --install)"
    fi

    # qlmanage smoke test — verify Quick Look can preview a markdown file without crashing
    echo ""
    echo "--- Extended: qlmanage Smoke Test ---"
    QL_FIXTURE="$PROJECT_DIR/Tests/TestRunner/Fixtures/basic.md"
    if [ -f "$QL_FIXTURE" ]; then
        # Run qlmanage with a 10-second timeout; -p triggers preview generation
        if timeout 10 qlmanage -p "$QL_FIXTURE" > /dev/null 2>&1; then
            echo "  ✓ qlmanage -p returned success for basic.md"
        else
            QL_EXIT=$?
            if [ "$QL_EXIT" -eq 124 ]; then
                echo "  ⚠ qlmanage -p timed out (10s) — may need manual investigation"
            else
                echo "  ✗ qlmanage -p failed with exit code $QL_EXIT"
                exit 1
            fi
        fi
    else
        echo "  ⊘ Fixture not found: $QL_FIXTURE — skipping"
    fi

    # Window lifecycle smoke test (no AX permissions needed)
    echo ""
    echo "--- Extended: Window Lifecycle Smoke Test ---"
    bash "$PROJECT_DIR/scripts/test-window-lifecycle.sh"

    # E2E UI automation tests (require .app bundle + AX permissions)
    if [ -d "$PROJECT_DIR/MarkView.app" ] || [ -d "/Applications/MarkView.app" ]; then
        echo ""
        echo "--- Extended: E2E Tests ---"
        swift run MarkViewE2ETester 2>&1 | grep -v "^\[" | grep -v "^$" | grep -v "^Building\|^Build of\|^warning:"
    else
        echo ""
        echo "--- Extended: E2E Tests ---"
        echo "  ⊘ Skipped — no .app bundle found (run: bash scripts/bundle.sh)"
    fi

    echo ""
    echo "=== Extended verification complete ==="
fi
