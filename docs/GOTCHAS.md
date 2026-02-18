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

## Automated Testing

### Never launch the app GUI during automated testing

`open -a MarkView`, `qlmanage -p`, and similar commands steal focus, interrupt the user, and create unpredictable window state. For CI and agent-driven testing:
- Use `MarkViewE2ETester` (runs headless via AXUIElement APIs with proper setup)
- For unit/integration tests, use `swift run MarkViewTestRunner` (no GUI)
- If you must test app behavior, run in background with `open -g -a MarkView` (no activation) or defer to the user
- Never launch GUI apps in automated bash commands without warning the user first

## Sentry Integration
<!-- local-only -->

### Sentry project slug is platform-based, not project-name-based

When creating a Sentry project, the slug is derived from the platform selection (e.g., "Apple — macOS" → `apple-macos`), not from the project name you enter. This affects all API calls, CI config (`SENTRY_PROJECT`), and GitHub Action inputs. Always verify the actual slug in Settings → Projects or via `GET /api/0/projects/{org}/`.

### Personal API tokens cannot access integrations endpoints

Sentry personal tokens (created via Developer Settings → Personal Tokens) return 403 on `/organizations/{org}/integrations/`. The `org:integrations` scope is only available to internal/public Sentry integrations (OAuth apps), not personal tokens. This means alert actions referencing GitHub integration (like "Create GitHub Issue on error") must be configured in the browser UI, not via API.

## XcodeGen

### `info:` key overwrites your Info.plist

XcodeGen's `info:` key on a target tells it to **generate** a plist at that path, replacing your custom one with a template. If you have a hand-crafted Info.plist (e.g., with NSExtension keys for Quick Look), use only `INFOPLIST_FILE` in `settings.base` and omit the `info:` key entirely. Set `GENERATE_INFOPLIST_FILE: false` to prevent Xcode from also generating one.

## WKWebView in Quick Look Extensions

### WebContent process needs sandbox entitlements to launch

WKWebView spawns a separate WebContent subprocess via XPC. In an app extension sandbox, this subprocess crashes silently (`reason=Crash, PID=0`) without these entitlements:

- `com.apple.security.network.client` — WebKit IPC even for local content
- `com.apple.security.cs.disable-library-validation` — load WebKit framework bundles
- `com.apple.security.temporary-exception.files.absolute-path.read-only` with `/` — file access for WebContent process

Symptoms: infinite loading spinner in Quick Look, `log show` shows "Invalid connection identifier (web process failed to launch)". Reference: sbarex/QLMarkdown uses all three.

### Disable competing QL extensions before removing their apps

`pluginkit -e ignore -i <bundle-id>` BEFORE deleting an app that provides a QL extension. macOS caches the extension as the preferred handler; deleting the app causes "Extension not found" errors. `qlmanage -r` + `killall quicklookd` + `killall Finder` to clear caches after.
