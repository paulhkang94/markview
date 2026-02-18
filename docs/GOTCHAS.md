# MarkView Gotchas

Project-specific pitfalls and quirks. Cross-repo learnings go to `claude-repl-template-oss/docs/learnings/`.

### CMARK_OPT_SOURCEPOS changes all HTML output

Enabling `CMARK_OPT_SOURCEPOS` adds `data-sourcepos="line:col-line:col"` to every block element. This breaks any test that does exact HTML string matching. Use regex or `contains` checks for tag matching. All golden baselines must be regenerated.

### postProcessForAccessibility must use regex, not exact string replacement

Tags like `<table>` may now have attributes (e.g., `<table data-sourcepos="...">`). Use `<table(\\s[^>]*)?>` regex pattern instead of exact `<table>` replacement.

### WKWebView evaluateJavaScript is cross-process IPC

Each `evaluateJavaScript` call is an IPC hop to the WebKit render process. Minimize per-frame JS evaluations. Cache element positions in JS and use simple `window.scrollTo()` instead of DOM-querying scripts.

### CADisplayLink on macOS uses NSView factory method

`CADisplayLink.init(target:selector:)` is unavailable on macOS. Use `view.displayLink(target:selector:)` instead.

### ScrollSyncController display link must be stopped when idle

CADisplayLink fires continuously at display refresh rate. Always `invalidate()` when there's no pending work to avoid wasting energy/CPU.

### Single-window macOS apps MUST use `Window`, not `WindowGroup`

`WindowGroup` allows SwiftUI to create duplicate windows on file open events (`kAEOpenDocuments`). No combination of `handlesExternalEvents(matching:)`, `AppDelegate.application(_:open:)`, or notification-based dedup reliably prevents this — `handlesExternalEvents` only works for URL schemes, and `application(_:open:)` doesn't fire for re-opens when SwiftUI intercepts the event first.

**Fix:** Use `Window("Title", id: "main") { ... }` scene instead. It structurally guarantees exactly one window. Route file opens through `AppDelegate.pendingFilePath` → `onReceive` in the view. A regression test in TestRunner checks for `WindowGroup {` in MarkViewApp.swift to prevent reintroduction.

## Quick Look Extension (appex) with SPM

### SPM has no native appex target type — you must manually satisfy all requirements

SPM provides zero validation of app extension requirements. For a Quick Look preview extension to work, you need ALL of these:

1. **`NSExtensionMain()` entry point** — not a regular `@main` struct. The extension must call `NSExtensionMain()` from its `main.swift`.
2. **Sandbox entitlement** — macOS silently rejects unsigned/unsandboxed extensions via pluginkit.
3. **Module-qualified principal class** — `NSExtensionPrincipalClass` in Info.plist must be `ModuleName.ClassName`, not just `ClassName`.
4. **`QLIsDataBasedPreview = true`** in Info.plist for data-based providers (as opposed to file URL-based).

Missing any single requirement causes silent failure — macOS registers nothing and reports no error.

### Never rationalize a failing test — make it skip or fix it

If a test fails, it's either a bug or a bad test. "Expected failure" is a code smell. Make it an explicit `XCTSkip` / conditional skip with a tracking issue, not a comment that normalizes the failure.

### Structure tests are necessary but not sufficient for platform integration

File-exists checks and plist validation confirm your bundle is well-formed, but they don't confirm macOS actually loaded your extension. For system-registered features (Quick Look, Spotlight importers, Share extensions), verify YOUR component is the one responding:

```bash
pluginkit -m | grep your.bundle.id   # ground truth for registration
```

If another app handles the same UTI, your broken extension looks like it works in the UI. Always check the registry, not the UI output.
