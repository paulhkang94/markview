# MarkView: Cross-Platform Status

Executive summary for all three platforms. Last updated: 2026-04-12.

Each platform has a per-platform SSOT doc linked in the table below.

| Platform | Version | Status | SSOT |
|----------|---------|--------|------|
| **macOS** | v1.4.2 | Shipping, 1,807 downloads | [STATUS.md](STATUS.md) |
| **iOS** | v1.0.0 | In submission - screenshots done, metadata pending | [markview-ios/docs/RELEASE.md](../../markview-ios/docs/RELEASE.md) |
| **Android** | v1.0.0 | Blocked - Google Play identity verification rejected | [markview-android/docs/RELEASE.md](../../markview-android/docs/RELEASE.md) |

---

## Feature Matrix

| Feature | macOS v1.4.2 | iOS v1.0.0 | Android v1.0.0 |
|---------|-------------|-----------|----------------|
| GFM rendering | ✅ cmark-gfm | ✅ cmark-gfm (shared MarkViewCore) | ✅ marked.js |
| Syntax highlighting | ✅ Prism.js 18+ langs | ✅ Prism.js (shared) | ❌ unstyled code blocks |
| Mermaid diagrams | ✅ 6 types + controls | ✅ (shared) | ❌ not wired |
| KaTeX math | ✅ no `$...$` | ✅ (shared, incl. fix) | ❌ not wired |
| GFM alerts (5 types) | ✅ | ✅ (shared) | ❌ not wired |
| diff2html diff viewer | ✅ | ✅ (shared) | ❌ not wired |
| TOC sidebar | ✅ | ✅ iPad / hidden iPhone | ❌ |
| PDF export | ✅ print dialog | ✅ WKWebView createPDF | ❌ |
| Dark mode | ✅ | ✅ | ✅ |
| File picker (in-app) | ✅ | ✅ folder toolbar button | ✅ intent |
| Find in document | ✅ Cmd+F | ❌ | ❌ |
| Live file watching | ✅ | ❌ | ❌ |
| Alert icons (emoji) | ✅ macOS emoji fonts | ⚠️ simulator only | ⚠️ simulator only |
| MCP server | ✅ 9 tools | ❌ N/A | ❌ N/A |
| Quick Look extension | ✅ | ❌ N/A | ❌ N/A |

### PDF rendering (future feature)

MarkView currently EXPORTS markdown to PDF (via WKWebView `createPDF`). It does not DISPLAY PDF files.

**Proposal:** Add PDF display support using PDF.js (Mozilla's JavaScript PDF renderer).

| Option | Search quality | Effort | Notes |
|--------|---------------|--------|-------|
| WKWebView native PDF loading | Same as macOS Preview (limited) | Low | Inherits PDFKit's per-character spacing heuristic bug |
| PDFKit (`PDFView`) | Same as macOS Preview (limited) | Low | Same limitation |
| **PDF.js bundled in WKWebView** | **Same as Chrome (excellent)** | **Medium** | Right answer; ~500KB gzipped; what Chrome uses internally |
| Poppler/MuPDF (native C) | Excellent | High | Overkill; complex to compile for macOS + iOS |

**Recommendation:** PDF.js is the correct approach if we ship this feature. It gives Chrome-quality text search (full string match across the entire document regardless of glyph spacing), handles all PDF versions, and bundles cleanly into WKWebView.

**Priority:** P3 - post-v1.0 iOS/Android release. Core value is markdown. QuickLook + Safari already handle PDF on macOS/iOS. Ship markdown excellence first.

**When to revisit:** After iOS App Store approval + Android Play Store live. Could differentiate MarkView as a lightweight "document viewer" beyond just .md files.

### Alert icon note

`template.html:279` uses emoji strings (`ℹ️💡❗⚠️🔴`) for alert icons.

Real devices on all platforms render these correctly - macOS, iOS device, and Android device all have system emoji fonts. The simulator limitation (WKWebView in iOS Simulator and Android Emulator lack emoji fonts, showing "?") is a test environment artifact only.

Fix path if needed: replace emoji with inline SVG icons following the pattern in `HTMLPipeline.swift` for Mermaid controls. This would also make App Store screenshots (taken on simulator) show correctly.

---

## App Icons

| Platform | Status | Asset |
|----------|--------|-------|
| macOS | ✅ Done | SF Pro Bold M, purple-blue gradient |
| iOS | ✅ Done | Same design, full size set (20pt - 1024pt) in `Assets.xcassets/AppIcon.appiconset/` |
| Android | ✅ Done | Confirmed working on S25 Ultra |

---

## iOS Gaps (v1.0.0 vs macOS v1.4.2)

These are tracked here as v1.1+ candidates. None block App Store submission.

| Gap | Priority | Notes |
|-----|----------|-------|
| Find in document (Cmd+F equivalent) | P1 | macOS has both editor and preview find. iOS: no search. |
| TOC toggle button on iPhone | P1 | TOC is correctly hidden below 768px viewport but unreachable. Need a toolbar button to switch to a TOC-only view. |
| Alert icons show "?" in simulator | P1 | Emoji `ℹ️💡❗⚠️🔴` in `template.html:279`. Real device renders correctly. Fix: SVG icons. Affects App Store simulator screenshots. |
| Font size control | P2 | macOS has a slider. iOS has none. |
| Live file watching | P2 | macOS reloads on save. iOS requires reopen. |
| Word count / stats | P3 | macOS toolbar stat. iOS has none. |

---

## Android Gaps (v1.0.0 vs macOS v1.4.2)

Android uses its own `template.html` with `marked.min.js` - not the shared MarkViewCore pipeline. All rendering features need to be wired separately.

| Gap | Priority | Notes |
|-----|----------|-------|
| Syntax highlighting (Prism.js) | P1 | Bundle exists in macOS repo under `Sources/MarkViewCore/Resources/`. Copy + inject. |
| Mermaid diagrams | P1 | `mermaid.min.js` available in macOS repo. Wire via template. |
| KaTeX math | P2 | Same pattern as Mermaid. |
| GFM alerts | P1 | Alert parsing logic in `template.html` JS. Copy the alert block from the shared template. |
| Samsung content:// intent filters | P1 | Documented in IMPLEMENTATION-PLAN.md Phase 1. |
| PDF export | P2 | Android WebView has `printDocumentAdapter`. |
| TOC sidebar | P3 | Low priority for v1.0. |
| Identity verification (Play Store) | BLOCKER | ID must be photographed physically. Limited attempts - prepare docs first. |

---

## Release Sequence

1. **iOS first** - unblocked. Screenshots captured (2026-04-12), metadata to fill.
   - Retake alert screenshots on real device OR fix emoji → SVG before uploading.
   - Archive + upload → TestFlight → submit.

2. **Android second** - blocked on identity verification.
   - Re-verify identity: photo of physical ID + bank statement/utility bill.
   - Then: create Play listing → wire CI → Samsung intent filters → upload AAB.

---

## Shared Code Architecture

```
~/repos/markview/                    macOS app + shared library
  Sources/MarkViewCore/              Shared rendering (iOS + macOS use this)
    HTMLPipeline.swift               Full injection pipeline
    MarkdownRenderer.swift           cmark-gfm rendering
    Resources/template.html          HTML template (emoji alert icons at line 279)

~/repos/markview-ios/               iOS app
  Sources/                          UIKit/SwiftUI app shell (5 files)
  Package.swift → MarkViewCore      Local package reference to ~/repos/markview

~/repos/markview-android/           Android app
  app/src/main/assets/template.html Independent template (NOT shared with macOS/iOS)
  app/src/main/java/.../            Kotlin + Compose
```

The iOS app is thin - it delegates all rendering to MarkViewCore. Any fix to
`template.html` or `HTMLPipeline.swift` automatically applies to both macOS and iOS.
Android has its own template that must be updated separately.
