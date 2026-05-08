# MarkView Mobile: iOS + Android

Living document. Updated each session. SSOT for mobile prototype state, App Store
blockers, and strategic direction.

**Decision (2026-04-11): SHIP to both stores.**

Rationale for publishing (overrides 2026-04-04 "skip" recommendation):
1. **Personal need**: Android (Galaxy S25 Ultra) has no free, polished, lightweight .md
   file viewer. The developer IS the first user.
2. **App name reservation**: "MarkView" must be claimed on both stores before a squatter does.
3. **Portfolio**: Starting at Fanatics as mobile staff SWE in May. OSS on macOS + iOS + Android
   is the right signal for the role.
4. **Market gap is real**: The developer searched, found nothing, and had no app to open .md
   files before building this. That's not a conjecture. It's lived experience.

The 2026-04-04 "skip" was based on lack of community demand signals. That framing was wrong:
personal utility + name reservation + career reasons justify shipping even at zero external demand.

---

## Current Prototype State

### iOS (markview-ios) v1.0.0/build 2

| | |
|---|---|
| **Status** | Functional on real device |
| **Rendering parity** | macOS v1.4.2 (MarkViewCore is shared - KaTeX fix + diff viewer included) |
| **UI-layer gaps** | Find/search, TOC toggle on iPhone, font size (see PLATFORMS.md) |
| **Real device tested** | iPad UDID `00008103-000D306E140B001E` |
| **Rendering** | MarkViewCore migration complete - same pipeline as macOS |
| **Unicode** | CJK/Arabic/emoji verified on real hardware (simulator fonts unreliable) |
| **Fixes verified** | Footnotes, images, Mermaid, KaTeX, diff viewer - all correct on device |
| **Cross-platform code** | Package.swift: `.iOS(.v16)` + `.macOS(.v13)`, zero AppKit imports |
| **Alert icons** | Emoji (ℹ️💡❗⚠️🔴) work on real device. Show "?" in simulator only (known limitation). |
| **File picker** | In-app folder button present (MarkViewApp.swift toolbar). Opens UIDocumentPickerViewController. |

**v1.1+ feature candidates:**
- Find/search in document (no Cmd+F equivalent)
- TOC toggle button on iPhone (TOC hidden below 768px, no access path)
- Font size control
- XCUITest suite for App Store critical paths

### Android (markview-android) v1.0.0/build 2

| | |
|---|---|
| **Status** | Confirmed working on Galaxy S25 Ultra (R5CXC2YSECW, Android 15) |
| **Feature parity** | macOS v1.3.0 (independent template.html - not sharing MarkViewCore) |
| **Rendering** | Kotlin + Compose + WebView, same JS bundles as macOS |
| **File handling** | Registered as .md handler in Files + Samsung My Files apps |
| **Unicode** | CJK/Arabic/emoji verified on real device |
| **Signed AAB** | Built and signed (`~/.android/markview-release.jks`, Keychain: `MARKVIEW_KEYSTORE_PASS`) |

**v1.0 pending (required before Play Store):**
- Samsung `content://` intent filters (IMPLEMENTATION-PLAN.md Phase 1)
- Prism.js syntax highlighting (currently unstyled code blocks)

**v1.1+ candidates:**
- In-app file picker button (currently opens only via intent from Files app)
- Feature parity with macOS v1.4.2 (Mermaid, KaTeX, diff viewer, GFM alerts)

---

## App Store Blockers

### Android: Play Store

| # | Blocker | Severity | Status |
|---|---------|----------|--------|
| 1 | Google Play identity verification | CRITICAL | **REJECTED** 2026-04-06 - re-verify with physical ID photo + bank statement |
| 2 | Google Play Service Account for CI | HIGH | Not created yet |
| 3 | CI upload wired (r0adkll/upload-google-play@v1) | HIGH | Commented out in workflow |
| 4 | Play app listing: package + store metadata | HIGH | Not created |
| 5 | Feature graphic (1024x500 px) + screenshots (1080x1920 px) | MEDIUM | Not created |
| 6 | Samsung content:// intent filters | MEDIUM | Documented in IMPLEMENTATION-PLAN.md |

**Play Console:** Account created 2026-04-04 (paulkang.dev, ID: 5018909132441005957)
**Keystore:** `~/.android/markview-release.jks` - password in Keychain `MARKVIEW_KEYSTORE_PASS`
**Build:** `cd ~/repos/markview-android && ./gradlew bundleRelease`

### iOS: App Store

| # | Blocker | Severity | Status |
|---|---------|----------|--------|
| 1 | Apple Distribution cert | HIGH | ✅ Done (created 4/11/26) |
| 2 | App Store Connect app listing | HIGH | ✅ Done ("MarkView: Markdown File Viewer", App ID 6762072726) |
| 3 | Bundle ID registration | HIGH | ✅ Done (dev.paulkang.markview-ios) |
| 4 | Screenshots: iPhone 6.9" + iPad 13" | HIGH | ✅ Done (2026-04-12, app-store-screenshots/) |
| 5 | App Store Connect metadata | HIGH | Pending - fill at appstoreconnect.apple.com/apps/6762072726/ |
| 6 | Archive + upload to TestFlight | HIGH | Pending - Xcode Archive after metadata |
| 7 | Real device TestFlight testing | MEDIUM | Pending - install on iPad Pro |
| 8 | Submit for review | HIGH | Pending - after TestFlight passes |

**Apple Dev Program:** `haramfaith@gmail.com` (team `B4M2AX4B6X`) - NOT paulhkang94@gmail.com
**App Store Connect login:** `haramfaith@gmail.com`
**Fastlane:** 2.232.2 at `/opt/homebrew/lib/ruby/gems/4.0.0/bin/fastlane`
**Bundle ID:** `dev.paulkang.markview-ios`

---

## Build & Release Commands

### Android

```bash
# Build signed release AAB
cd ~/repos/markview-android && ./gradlew bundleRelease
# Output: app/build/outputs/bundle/release/app-release.aab

# Retrieve keystore password
security find-generic-password -a 'markview-android' -s 'MARKVIEW_KEYSTORE_PASS' -w
```

### iOS

```bash
# Capture screenshots (both simulators)
cd ~/repos/markview-ios
MARKVIEW_SIMULATOR=E8A4D1FE-2234-4BB3-A4D9-5E34364A01DE bash scripts/test-simulator.sh
MARKVIEW_SIMULATOR=BD10C671-FD61-4E4E-B117-BCC201A3BD16 bash scripts/test-simulator.sh --screenshots-only

# Archive and upload to TestFlight (Xcode)
xcodegen generate
# Then: Xcode > Product > Archive > Distribute > App Store Connect
```

---

## Release Plan: iOS First

Decision updated 2026-04-12: iOS ships before Android. Original "Android first" rationale
assumed Android was simpler - that's wrong. Android is blocked by identity verification
with limited re-attempts. iOS is fully unblocked.

**iOS sequence (current):**
1. ✅ Distribution cert + bundle ID + listing + screenshots
2. Fill App Store Connect metadata (appstoreconnect.apple.com/apps/6762072726/)
3. Archive + upload via Xcode (Product > Archive)
4. TestFlight testing on real iPad
5. Submit for review

**Android sequence (blocked):**
1. Re-verify Google Play identity: photograph physical ID + bank statement
2. Create Play app listing (package: dev.paulkang.markview)
3. Add Samsung content:// intent filters (IMPLEMENTATION-PLAN.md Phase 1)
4. Create service account + wire CI
5. Capture screenshots (1080x1920 px)
6. Upload signed AAB

---

## MCP Integration on Mobile (future)

Local MCP server (stdio transport) is not feasible on iOS/Android per App Store guidelines.
Options for future AI integration:

1. **iCloud Drive bridge** (short-term): macOS MarkView writes previews to iCloud; iOS reads. No MCP needed.
2. **Remote MCP proxy** (medium-term): Cloudflare Worker proxies MCP calls. Requires backend work.
3. **Anthropic remote MCP** (long-term): If Anthropic ships remote MCP in Claude iOS app, MarkView registers as remote server.

Not a launch blocker. Ship the read-only viewer first.

---

## Key Files

| File | Location | Purpose |
|------|----------|---------|
| Cross-platform status | `~/repos/markview/docs/PLATFORMS.md` | Feature matrix, iOS/Android gaps, shared architecture |
| Android release checklist | `~/repos/markview-android/docs/RELEASE.md` | Step-by-step Play Store submission |
| iOS release checklist | `~/repos/markview-ios/docs/RELEASE.md` | Step-by-step App Store submission |
| iOS store listing copy | `~/repos/markview-ios/docs/APP_STORE_LISTING.md` | All App Store Connect fields with content |
| Android implementation plan | `~/repos/markview-android/IMPLEMENTATION-PLAN.md` | Feature work (intent filters, Prism.js) |
| Android store listing | `~/repos/markview-android/docs/APP_STORE_LISTING.md` | Metadata, screenshots spec |
| iOS architecture | `~/repos/markview-ios/docs/architecture-review.md` | MarkViewCore migration audit |
| Strategy (superseded) | `docs/personal/p3-mobile-strategy.md` | 2026-04-04 "skip" decision, overridden 2026-04-11 |
| This file | `~/repos/markview/docs/MOBILE.md` | SSOT for mobile state |
