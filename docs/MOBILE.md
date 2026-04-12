# MarkView Mobile — iOS + Android

Living document. Updated each session. SSOT for mobile prototype state, App Store
blockers, and strategic direction.

**Decision (2026-04-11): SHIP to both stores.**

Rationale for publishing (overrides 2026-04-04 "skip" recommendation):
1. **Personal need**: Android (Galaxy S25 Ultra) has no free, polished, lightweight .md
   file viewer — the developer IS the first user.
2. **App name reservation**: "MarkView" must be claimed on both stores before a squatter does.
3. **Portfolio**: Starting at Fanatics as mobile staff SWE in May. OSS on macOS + iOS + Android
   is the right signal for the role.
4. **Market gap is real**: The developer searched, found nothing, and had no app to open .md
   files before building this. That's not a conjecture — it's lived experience.

The 2026-04-04 "skip" was based on lack of community demand signals. That framing was wrong:
personal utility + name reservation + career reasons justify shipping even at zero external demand.

---

## Current Prototype State

### iOS (markview-ios) — v1.0.0/build 2

| | |
|---|---|
| **Status** | Functional on real device |
| **Feature parity** | macOS v1.3.0 (3 minor versions behind v1.4.2) |
| **Real device tested** | iPad UDID `00008103-000D306E140B001E` |
| **Rendering** | MarkViewCore migration complete — same pipeline as macOS |
| **Unicode** | CJK/Arabic/emoji verified on real hardware (simulator fonts unreliable) |
| **Fixes verified** | Footnotes, images, Mermaid, KaTeX — all correct on device |
| **Cross-platform code** | Package.swift: `.iOS(.v16)` + `.macOS(.v13)`, zero AppKit imports |

**Pending features:**
- E2ETester find-bar tests (9 stubs, require AX permission)
- Feature parity with macOS v1.4.2 (KaTeX `$...$` fix, diff viewer, etc.)
- XCUITest suite for App Store critical paths

### Android (markview-android) — v1.0.0/build 2

| | |
|---|---|
| **Status** | Confirmed working on Galaxy S25 Ultra (R5CXC2YSECW, Android 15) |
| **Feature parity** | macOS v1.3.0 |
| **Rendering** | Kotlin + Compose + WebView, same JS bundles as macOS |
| **File handling** | Registered as .md handler in Files + Samsung My Files apps |
| **Unicode** | CJK/Arabic/emoji verified on real device |
| **Signed AAB** | Built and signed (`~/.android/markview-release.jks`, Keychain: `MARKVIEW_KEYSTORE_PASS`) |

**Pending features:**
- File picker button (open .md from within app, not just from Files app)
- Samsung `content://` intent filters (IMPLEMENTATION-PLAN.md Phase 1)
- Prism.js syntax highlighting (currently unstyled code blocks)
- Feature parity with macOS v1.4.2

---

## App Store Blockers

### Android — Play Store

| # | Blocker | Severity | Status |
|---|---------|----------|--------|
| 1 | Google Play identity verification | CRITICAL | Pending (upload gov ID, 2-7 day wait) |
| 2 | Google Play Service Account for CI | HIGH | Not created yet |
| 3 | CI upload wired (r0adkll/upload-google-play@v1) | HIGH | Commented out in workflow |
| 4 | Play app listing: package + store metadata | HIGH | Not created |
| 5 | Feature graphic (1024×500 px) + screenshots (1080×1920 px) | MEDIUM | Not created |
| 6 | Samsung content:// intent filters | MEDIUM | Documented in IMPLEMENTATION-PLAN.md |

**Play Console:** Account created 2026-04-04 (paulkang.dev, ID: 5018909132441005957)  
**Keystore:** `~/.android/markview-release.jks` — password in Keychain `MARKVIEW_KEYSTORE_PASS`  
**Build:** `cd ~/repos/markview-android && ./gradlew bundleRelease`

### iOS — App Store

| # | Blocker | Severity | Status |
|---|---------|----------|--------|
| 1 | Apple Distribution cert | HIGH | Not created |
| 2 | App Store Connect app listing | HIGH | Not created |
| 3 | App Store Connect API key (for CI, avoids 2FA) | HIGH | Not created |
| 4 | `fastlane match` certs repo (`paulhkang94/markview-certs`) | HIGH | Not created |
| 5 | XCUITest suite | HIGH | Not written |
| 6 | Screenshots (iPhone 6.7" + iPad Pro 12.9") | HIGH | Not captured |
| 7 | Real iPhone device testing | MEDIUM | Only iPad tested |

**Apple Dev Program:** `haramfaith@gmail.com` (team `B4M2AX4B6X`) — NOT paulhkang94@gmail.com  
**App Store Connect login:** `haramfaith@gmail.com`  
**Fastlane:** 2.232.2 at `/opt/homebrew/lib/ruby/gems/4.0.0/bin/fastlane`  
**Bundle ID:** `dev.paulkang.markview-ios`  
**Recommended cert path:** `fastlane match appstore` with private repo `paulhkang94/markview-certs`

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
# Install to connected device
cd ~/repos/markview-ios
xcodegen generate
fastlane beta  # → TestFlight (once CI secrets wired)

# Match certs (once markview-certs repo created)
fastlane match appstore
```

---

## Release Plan: Android First

Android ships before iOS for two reasons:
1. The developer uses Galaxy S25 Ultra — Android is personal validation, not just publishing
2. Android blockers are mostly infrastructure (service account, CI wiring, screenshots)
   — iOS has more dev work (XCUITest suite, fastlane match setup)

**Android sequence:**
1. Complete Google Play identity verification (awaiting gov ID processing)
2. Create Play app listing + content rating questionnaire
3. Create service account + wire CI
4. Add Samsung intent filters (IMPLEMENTATION-PLAN.md Phase 1)
5. Capture screenshots
6. Upload signed AAB → internal testing → production

**iOS sequence:**
1. Create Distribution cert via fastlane match
2. Create App Store Connect listing
3. Generate App Store Connect API key
4. Write XCUITest suite (5-7 tests: file open, PDF export, dark mode)
5. Capture screenshots (6.7" + iPad 12.9")
6. TestFlight → App Store

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
| Android release checklist | `~/repos/markview-android/docs/RELEASE.md` | Step-by-step Play Store submission |
| iOS release checklist | `~/repos/markview-ios/docs/RELEASE.md` | Step-by-step App Store submission |
| Android implementation plan | `~/repos/markview-android/IMPLEMENTATION-PLAN.md` | Feature work (intent filters, Prism.js) |
| Android store listing | `~/repos/markview-android/docs/APP_STORE_LISTING.md` | Metadata, screenshots spec |
| iOS store listing | `~/repos/markview-ios/docs/APP_STORE_LISTING.md` | Metadata, screenshots spec |
| iOS architecture | `~/repos/markview-ios/docs/architecture-review.md` | MarkViewCore migration audit |
| Strategy (superseded) | `docs/personal/p3-mobile-strategy.md` | 2026-04-04 "skip" decision — overridden 2026-04-11 |
| This file | `~/repos/markview/docs/MOBILE.md` | SSOT for all mobile state |
