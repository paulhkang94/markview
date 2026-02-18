# Quick Look Extension: WKWebView Sandbox Crash Analysis

Research date: 2026-02-17

## Executive Summary

**Root cause:** WKWebView's WebContent subprocess (an XPC service at `com.apple.WebKit.WebContent`) cannot establish Mach port connections from within the Quick Look extension's sandbox. The sandbox profile of a QL extension is more restrictive than a normal sandboxed app -- it blocks XPC lookups that WebKit's multi-process architecture requires. Ad-hoc signing (`CODE_SIGN_IDENTITY=-`) is a contributing factor but NOT the sole cause.

**Recommended fix:** Switch from the view-controller path (`QLPreviewingController` + WKWebView) to the **data-based path** (`QLPreviewProvider` + `QLPreviewReply` with HTML content type). This completely avoids WKWebView in the extension process -- Quick Look's own infrastructure renders the HTML. This is available on macOS 12+ and is the approach sbarex/SourceCodeSyntaxHighlight migrated to for Monterey+.

---

## 1. Why WKWebView Crashes in a QL Extension

### The Multi-Process Architecture Problem

WKWebView is not a single-process component. When you create a WKWebView, WebKit spawns:
- **WebContent process** (`com.apple.WebKit.WebContent.xpc`) -- renders HTML/JS
- **Networking process** (`com.apple.WebKit.Networking.xpc`) -- handles network I/O

These are XPC services that must establish Mach port connections back to the host process. In a Quick Look extension's sandbox, these XPC lookups fail.

### Evidence from System Logs

Live system logs from the installed MarkView QL extension show:

```
com.apple.WebKit.WebContent: (libxpc.dylib) assertion failed: 25D125: libxpc.dylib + 214952: 0x10000017
com.apple.WebKit.WebContent: (libxpc.dylib) assertion failed: 25D125: libxpc.dylib + 43272: 0x1
```

These `libxpc.dylib` assertion failures confirm that the WebContent process spawns but immediately crashes because it cannot complete XPC connection setup. The error code `0x10000017` maps to `XPC_COULD_NOT_CREATE_CONNECTION` -- the sandbox profile of the QL extension prevents the Mach port lookup.

### The Entitlements Gap

**Source entitlements** (`MarkViewQuickLook.entitlements`):
- `com.apple.security.app-sandbox` = true
- `com.apple.security.files.user-selected.read-only` = true
- `com.apple.security.cs.allow-unsigned-executable-memory` = true

**Embedded entitlements** (in installed binary -- Xcode adds these during build):
- All of the above, plus:
- `com.apple.security.network.client` = true
- `com.apple.security.cs.disable-library-validation` = true
- `com.apple.security.get-task-allow` = true
- `com.apple.security.temporary-exception.files.absolute-path.read-only` = ["/"]

Even with `network.client` and `disable-library-validation` present in the installed build, the WebContent process still crashes. This proves that standard entitlements are insufficient -- the QL extension sandbox profile has additional restrictions beyond what entitlements can override.

### WebKit Bug History

This is a **known, long-standing issue**:
- [WebKit Bug 219632](https://bugs.webkit.org/show_bug.cgi?id=219632): "REGRESSION(r261238): WKWebView crashes on launch inside a quicklook preview" -- documented since Big Sur (11.x)
- WebKit changeset 271895 partially fixed it for Big Sur, but the underlying sandbox restriction persists in newer macOS versions
- sbarex documented this extensively in [QLTest](https://github.com/sbarex/QLTest)

---

## 2. How QLMarkdown (sbarex/QLMarkdown) Handles It

### Entitlements Used

QLMarkdown's extension uses these entitlements:
1. `com.apple.security.app-sandbox` = true
2. `com.apple.security.temporary-exception.mach-lookup.global-name` with `com.apple.nsurlsessiond` -- workaround for WebKit networking
3. `com.apple.security.temporary-exception.files.absolute-path.read-only` with `/` -- read access to filesystem for local images
4. `com.apple.security.network.client` = true

### Code Signing

QLMarkdown is **NOT notarized or signed** with Developer ID. Precompiled releases require users to:
```bash
xattr -r -d com.apple.quarantine /Applications/QLMarkdown.app
```

### Key Insight

QLMarkdown uses the **mach-lookup temporary exception** entitlement to allow the WebContent process to connect to `com.apple.nsurlsessiond`. However, this is a **temporary exception** entitlement -- Apple can reject it during App Store/notarization review. It works for ad-hoc distributed apps but is NOT a production-quality solution.

---

## 3. Is Ad-Hoc Signing the Problem?

**Partially, but not entirely.**

### What Ad-Hoc Signing Does

- `CODE_SIGN_IDENTITY=-` creates a code hash but no cryptographic signature
- Only works on the machine that built it (no identity chain for verification)
- WebKit's WebContent process inherits sandbox profile from the host process
- Ad-hoc signing means no Team ID, which affects sandbox lookups

### The Real Issue

Even with Developer ID signing, the QL extension sandbox restricts Mach port lookups that WKWebView requires. Developer ID signing would:
1. Allow the binary to run on other machines
2. Enable notarization
3. Potentially allow certain XPC lookups that require team identity matching

But it would NOT fix the fundamental sandbox profile restriction on QL extensions. The `mach-lookup.global-name` temporary exception entitlement is what actually fixes the XPC connection -- not the signing identity.

### Verdict

Ad-hoc signing is a prerequisite problem for distribution, but switching to Developer ID signing alone will NOT fix the WKWebView crash. The mach-lookup entitlement workaround is also required, and that entitlement is fragile.

---

## 4. Alternative Approaches (Ranked by Recommendation)

### Option A: Data-Based QLPreviewProvider with HTML Reply (RECOMMENDED)

**Approach:** Switch from `QLPreviewingController` (view-controller path) to `QLPreviewProvider` (data-based path). Return a `QLPreviewReply` with HTML content.

```swift
import QuickLookUI
import MarkViewCore

class PreviewProvider: QLPreviewProvider {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let markdown = try String(contentsOf: request.fileURL, encoding: .utf8)
        let html = MarkdownRenderer.renderHTML(from: markdown)
        let accessible = MarkdownRenderer.postProcessForAccessibility(html)
        var document = MarkdownRenderer.wrapInTemplate(accessible)

        // Apply QL-specific CSS overrides
        document = document.replacingOccurrences(
            of: "</head>",
            with: "<style>body { max-width: 100% !important; padding: 24px 48px !important; }</style></head>"
        )

        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 800, height: 600)
        ) { _ in
            return Data(document.utf8)
        }

        reply.stringEncoding = .utf8
        reply.title = request.fileURL.lastPathComponent
        return reply
    }
}
```

**Pros:**
- No WKWebView in extension process -- Quick Look renders HTML itself
- No sandbox/entitlement issues -- Apple's QL infrastructure handles rendering
- Available macOS 12+ (we target 14+, so fully compatible)
- This is what sbarex/SourceCodeSyntaxHighlight migrated to for Monterey+
- Works with ad-hoc signing
- Simpler code (no WKNavigationDelegate, no temp files)
- CSS attachments supported via `QLPreviewReply.attachments` with `cid:` references

**Cons:**
- Less control over rendering (Quick Look's HTML renderer, not WKWebView)
- JavaScript execution may be limited or absent (Prism.js syntax highlighting may not work)
- Need to test if inline `<style>` and CSS work as expected
- `preferredContentSize` control is via `contentSize` parameter instead

**Required Info.plist changes:**
```xml
<key>QLIsDataBasedPreview</key>
<true/>
<key>NSExtensionPrincipalClass</key>
<string>$(PRODUCT_MODULE_NAME).PreviewProvider</string>
```

### Option B: Mach-Lookup Temporary Exception Entitlement (QLMarkdown approach)

**Approach:** Keep WKWebView but add the mach-lookup entitlement.

Add to `MarkViewQuickLook.entitlements`:
```xml
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
    <string>com.apple.nsurlsessiond</string>
</array>
<key>com.apple.security.network.client</key>
<true/>
```

**Pros:**
- Minimal code changes
- Preserves full WKWebView rendering (Prism.js, etc.)

**Cons:**
- "Temporary exception" entitlements may be rejected by App Store / notarization review
- Fragile -- Apple can change which mach services are needed between macOS versions
- Does not fix the root cause, just patches around it
- May need additional mach services on macOS Tahoe (26.x) beyond what was needed on Big Sur

### Option C: NSAttributedString Rendering (No WebKit)

**Approach:** Convert HTML to NSAttributedString and display in NSTextView.

```swift
let attrString = try NSAttributedString(
    data: Data(html.utf8),
    options: [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
    ],
    documentAttributes: nil
)
let textView = NSTextView(frame: bounds)
textView.textStorage?.setAttributedString(attrString)
view = textView
```

**Pros:**
- No WebKit subprocess, no sandbox issues
- Simple, lightweight

**Cons:**
- NSAttributedString HTML→rich text conversion is lossy and slow
- No CSS support (no Prism.js, no custom styling)
- Poor rendering quality compared to WKWebView or QL HTML
- Code blocks, tables, and complex markdown will render poorly
- Not suitable for a quality markdown preview

### Option D: Core Text / Direct Drawing

**Approach:** Parse markdown AST and render directly with Core Text or NSTextView with manual formatting.

**Pros:**
- Full control over rendering
- No external process dependencies

**Cons:**
- Massive implementation effort
- Would need to reimplement most of what HTML/CSS provides for free
- Not practical for a markdown previewer

### Option E: Hybrid (Data-Based with WKWebView Fallback)

**Approach:** Use QLPreviewProvider (Option A) as primary. If JS-dependent features are needed (Prism.js), provide a degraded-but-functional preview via HTML without JS, with syntax highlighting via CSS classes pre-computed at build time.

---

## 5. QLMarkdown Entitlements (Complete)

From sbarex/QLMarkdown's extension target:

| Entitlement | Value | Purpose |
|---|---|---|
| `com.apple.security.app-sandbox` | `true` | Required for App Store / notarization |
| `com.apple.security.network.client` | `true` | WKWebView needs outbound network (even for local content) |
| `com.apple.security.temporary-exception.mach-lookup.global-name` | `["com.apple.nsurlsessiond"]` | Big Sur WebKit crash workaround |
| `com.apple.security.temporary-exception.files.absolute-path.read-only` | `["/"]` | Read local images referenced in markdown |

Note: QLMarkdown is NOT notarized. The temporary-exception entitlements would need Apple review for distribution.

---

## 6. Recommendation for MarkView

### Immediate Fix: Switch to Option A (Data-Based QLPreviewProvider)

1. **Rename** `PreviewViewController` to `PreviewProvider`, change base class from `NSViewController` to `QLPreviewProvider`
2. **Return HTML data** via `QLPreviewReply(dataOfContentType: .html, ...)` instead of loading WKWebView
3. **Update Info.plist**: Add `QLIsDataBasedPreview = true`, change `NSExtensionPrincipalClass`
4. **Simplify entitlements**: Remove `cs.allow-unsigned-executable-memory` (no JS JIT needed), remove `app-sandbox` if not needed for data-based path
5. **Test**: CSS attachments via `cid:` for any external CSS/images, verify rendering quality

### Syntax Highlighting Strategy

Since the data-based HTML path may not support JavaScript (Prism.js), consider:
- Pre-computing syntax highlighting at the Swift level (use the cmark AST to add CSS classes)
- Embedding inline CSS for syntax highlighting colors (no JS needed)
- Or accept plain code blocks in Quick Look (users see full highlighting in the main app)

### Long-Term

If you eventually get a Developer ID certificate:
- Option B (mach-lookup entitlement) becomes viable for preserving full WKWebView fidelity
- But Option A is still cleaner and more maintainable

---

## References

- [WebKit Bug 219632](https://bugs.webkit.org/show_bug.cgi?id=219632) -- WKWebView crash regression in Quick Look
- [sbarex/QLTest](https://github.com/sbarex/QLTest) -- Test project documenting QL + WKWebView bugs
- [sbarex/QLMarkdown](https://github.com/sbarex/QLMarkdown) -- Working QL extension with WKWebView + mach-lookup workaround
- [sbarex/SourceCodeSyntaxHighlight](https://github.com/sbarex/SourceCodeSyntaxHighlight) -- Migrated to data-based QL API on Monterey+
- [Apple Developer Forums: WKWebView and the sandbox](https://developer.apple.com/forums/thread/126381)
- [Apple Developer Forums: WKWebView/Sandbox Intermittent](https://developer.apple.com/forums/thread/774395)
- [Apple Developer Forums: WKWebView and QuickLook Issues](https://developer.apple.com/forums/thread/659292)
- [QLPreviewProvider Documentation](https://developer.apple.com/documentation/quicklookui/qlpreviewprovider)
- [QLPreviewReply Documentation](https://developer.apple.com/documentation/quicklookui/qlpreviewreply)
- [WebKit Blog: Handling blank WKWebViews](https://nevermeant.dev/handling-blank-wkwebviews/)
