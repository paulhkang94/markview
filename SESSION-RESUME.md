# MarkView — Session Resume (2026-04-04 v2)

Use this file to resume the next session. Start with `/catchup`.

---

## Resume Prompt

```
/catchup

Context: Massive multi-platform session (2026-04-04). Shipped iOS app v1.0.0
(PDF export, icon, nav title), Android app v1.0.0 (Prism.js, file picker,
link fix, PNG icons), macOS CSS custom properties dark-mode fix + color-scheme
meta tag. App Store release infrastructure in place for both mobile repos.
macOS v1.4.0 code committed but NOT yet tagged or npm-published.

Apple Dev Program is under haramfaith@gmail.com (team B4M2AX4B6X).

Read first:
- /Users/pkang/repos/markview/SESSION-RESUME.md         ← this file
- /Users/pkang/repos/markview/docs/STATUS.md             ← living architecture doc
- /Users/pkang/repos/markview-ios/docs/RELEASE.md        ← iOS App Store checklist
- /Users/pkang/repos/markview-android/docs/RELEASE.md    ← Android Play Store checklist
```

---

## PRIORITY ORDER

### P0 — Tag v1.4.0 + npm publish (blocked: run preflight first)

```bash
cd ~/repos/markview
bash scripts/release-preflight.sh   # creates .release-preflight-passed-1.4.0
git tag v1.4.0
git push --tags
cd npm && npm version 1.4.0 && npm publish
```

### P0 — iOS: Verify iPad rendering after all fixes

Key things to verify on physical iPad (8):
- App icon shows (fixed: ASSETCATALOG_COMPILER_APPICON_NAME added)
- Dark mode tables correct (fixed: CSS custom properties)
- Inline code visible (fixed: rgba(175,184,193,0.2))
- PDF export works (tap share icon)
- Links open in Safari (not in-app, iOS uses SFSafariViewController automatically)

Build + install:
```bash
cd ~/repos/markview-ios && xcodegen generate
xcodebuild -project MarkView.xcodeproj -scheme MarkView \
  -destination 'id=00008103-000D306E140B001E' \
  -allowProvisioningUpdates build
```

### P0 — App Store: Complete manual setup steps

**iOS (haramfaith@gmail.com account):**
1. Sign in at appstoreconnect.apple.com with haramfaith@gmail.com
2. Create app: "MarkView — Markdown Viewer", bundle ID `dev.paulkang.markview-ios`
3. Generate API key: App Store Connect → Users & Access → Integrations → Keys
4. Create private certs repo: `gh repo create paulhkang94/markview-certs --private`
5. Run `fastlane match appstore` to create Distribution cert + provisioning profile

**Android:**
1. ✅ Google Play Console created — `paulkang.dev`, Account ID `5018909132441005957`, `paulhkang94@gmail.com`
2. ⏳ Complete identity verification — upload gov ID at play.google.com/console (takes 2–7 days), verify Android device (Play Console app), verify phone
3. Create app listing: "MarkView — Markdown Viewer", package `dev.paulkang.markview`
4. Create service account for CI: Play Console → Setup → API access → Create
5. Upload first AAB: `~/repos/markview-android/app/build/outputs/bundle/release/app-release.aab`

### P1 — iOS Quick Look provider

`QLPreviewingController` for Files.app spacebar preview (`.md` files).
New target in project.yml, similar to macOS `MarkViewQuickLook`.

### P1 — Android: MCP tool quick wins for macOS

From roadmap `features-roadmap-2026-04-04.md` Week 1:
- `lint_content` — lint raw string (no file), XS effort
- `get_word_count` — words/chars/lines/tokens, XS effort
- `outline` — heading tree + line numbers, S effort
- `preview_markdown` return HTML in response, S effort

### P1 — Android: E2E test infrastructure

Add Appium + WebdriverIO for WebView DOM inspection:
- `switchContext('WEBVIEW_dev.paulkang.markview')` to inspect rendered DOM
- Assert tables exist, code blocks have .token spans, dark mode vars correct
- See `~/repos/markview-android/docs/TESTING.md`

### P2 — macOS: MCP `export_pdf` tool

Uses `WKWebView.createPDF()` in MCP server context. Medium effort — needs main
thread + CFRunLoopRun() for WKWebView in a non-UI process.

### P2 — iOS: iCloud Drive sync

`UIDocumentPickerViewController` + `NSFileCoordinator`.
Retention feature: Claude Code generates doc on macOS → appears on iPhone.

### P3 — Diagram controls visual QA

Manual check: open golden-corpus.md, verify 8 SVG icons at 3 window sizes.
No code changes needed.

---

## Key Infrastructure

### Signing & Release

```bash
# Android keystore password
security find-generic-password -a 'markview-android' -s 'MARKVIEW_KEYSTORE_PASS' -w

# Android release AAB build
cd ~/repos/markview-android && ./gradlew bundleRelease
# Output: app/build/outputs/bundle/release/app-release.aab

# Fastlane (installed 2026-04-04)
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
fastlane --version  # 2.232.2

# iOS App Store apple_id: haramfaith@gmail.com (team B4M2AX4B6X)
# NOT contact@paulkang.dev or paulhkang94@gmail.com
```

### TV Stamp Paths (two-gate system)
```bash
date +%s > ~/repos/claude-loop/.claude/memory/.last-verify-at     # commit-gate (SEPARATE call)
date +%s > ~/repos/markview/.last-render-verify-at                  # render-verify
# CRITICAL: stamp in its own Bash call. Hook reads BEFORE command executes.
```

### Build Commands (all platforms)
```bash
# macOS
cd ~/repos/markview
swift run MarkViewTestRunner   # 350+ tests
make playwright                 # 150 Playwright tests + installs app
bash verify.sh                  # full gate

# iOS (device)
cd ~/repos/markview-ios && xcodegen generate
xcodebuild -project MarkView.xcodeproj -scheme MarkView \
  -destination 'id=00008103-000D306E140B001E' \
  -allowProvisioningUpdates build

# Android
cd ~/repos/markview-android
./gradlew assembleDebug
adb -s R5CXC2YSECW install -r app/build/outputs/apk/debug/app-debug.apk

# Android golden-corpus test (private dir)
cat ~/repos/markview/Tests/TestRunner/Fixtures/golden-corpus.md | \
  adb -s R5CXC2YSECW shell "run-as dev.paulkang.markview sh -c \
  'cat > /data/data/dev.paulkang.markview/files/golden-corpus.md'"
adb -s R5CXC2YSECW shell am start -a android.intent.action.VIEW \
  -d "file:///data/data/dev.paulkang.markview/files/golden-corpus.md" \
  -n dev.paulkang.markview/.MainActivity
```

### Device UDIDs
- iPad (8), iOS 18.6.2: `00008103-000D306E140B001E`
- Galaxy S25U, Android 15: `R5CXC2YSECW` (adb)

---

## Session Commits (2026-04-04)

### markview (macOS)
| Hash | Description |
|------|-------------|
| `e660b09` | fix(dark-mode): color-scheme meta tag + render-verify gate wired |
| `7cd61bf` | fix(rendering): CSS custom properties — dark mode reliable across all renderers |
| `65ac608` | feat(icon): SF Pro Bold M at 28% + inline code CSS fix (150/150 tests) |
| `9cf5b84` | feat(icon): clean M — remove # symbol, unified brand |

### markview-ios
| Hash | Description |
|------|-------------|
| `16d551e` | feat(release): App Store infrastructure + CI/CD |
| `56da208` | chore: delete orphan marked.js + update docs |
| `c43b7c1` | feat(icon): 32% padding |
| `0665f29` | feat(icon): SF Pro Bold M + fix ASSETCATALOG_COMPILER_APPICON_NAME |
| `fee5b5d` | feat: PDF export + nav title + app icon + Info.plist |

### markview-android
| Hash | Description |
|------|-------------|
| `fab9d59` | feat(release): Play Store infrastructure + CI/CD |
| `1d32528` | fix(android): open hyperlinks in system browser |
| `f4468b9` | fix(file-picker): re-render content on new file + PNG icon mipmaps |
| `b2800f9` | feat(icon): SF Pro Bold M 28% + remove debug package suffix |
| `43a1568` | feat: Prism.js + TopAppBar + file picker + adaptive icon |

---

## Architecture Notes

### iOS dark mode — two requirements
Both are required for WKWebView (A11Y research finding 2026-04-04):
```html
<meta name="color-scheme" content="light dark">  <!-- in <head> -->
```
```css
:root { color-scheme: light dark; }  /* in CSS */
```
Without the meta tag, scrollbars/form controls/system colors ignore dark mode.

### Android AndroidView update block
When markdown state changes (file picker), the `update` block must call
`renderMarkdown` via JS. The `factory` closure captures initial state only.
```kotlin
AndroidView(
    factory = { /* create WebView, load URL, onPageFinished renders initial */ },
    update = { webView ->
        webView.evaluateJavascript(
            "if (typeof renderMarkdown === 'function') { renderMarkdown($encodedMarkdown) }",
            null
        )
    }
)
```

### CSS custom properties (dark mode fix)
The template.html now uses `--color-*` CSS variables. Light values in `:root`,
dark overrides in `@media (prefers-color-scheme: dark) { :root { ... } }`.
This eliminates cascade/specificity conflicts in Chrome auto-dark and WKWebView.

### Android icon: PNG mipmaps > XML gradient
Samsung launcher flattens `aapt:attr` XML gradients. Generated PNG mipmaps
(mdpi→xxxhdpi) via cairosvg from the SVG source guarantee pixel-accurate gradients.
Source: `~/repos/markview/icons/markview-icon.svg`
Generator: `bash ~/repos/markview/icons/generate.sh`

### App Store Apple ID
Apple Developer Program is registered under `haramfaith@gmail.com` (team B4M2AX4B6X).
Use this for: App Store Connect, fastlane match, fastlane Appfile, TestFlight.
NOT: contact@paulkang.dev, NOT: paulhkang94@gmail.com.
