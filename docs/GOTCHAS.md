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

## SwiftUI + NSViewRepresentable

### @Published updates may split across multiple updateNSView calls

When an `ObservableObject` updates multiple `@Published` properties in `loadFile()` (e.g., `currentFilePath` then `renderedHTML`), SwiftUI may call `updateNSView` separately for each change. A per-call flag like `let fileChanged = X != lastX; lastX = X` gets consumed by the first (stale) call, so the second call (with actual new content) misses it.

**Fix:** Use a persistent flag (`pendingFileReload`) that's set when the identity changes and only cleared when a full reload actually fires. Combined with `.id()` on the `NSViewRepresentable` for belt-and-suspenders.

### Optimization fast-paths need mode-transition tests

The JS innerHTML swap (`updateContentViaJS`) was added for live editing performance but broke file switching — it fails silently on `loadFileURL`-loaded pages. Any fast-path that optimizes a common case (editing) must have tests for mode transitions (file switching, pane toggling).

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

## App Signing & Distribution

### Developer ID without notarization is REJECTED by Gatekeeper (since macOS 10.15)

Code-signing with Developer ID + hardened runtime is necessary but NOT sufficient for distribution. Since Catalina, Gatekeeper also requires a notarization ticket stapled to the app. Without it, downloaded apps trigger "MarkView.app is damaged and can't be opened."

The quarantine flag (`com.apple.quarantine`) is applied by:
- **Homebrew** (when extracting cask downloads)
- **Safari/browsers** (any downloaded .app or .dmg)
- **AirDrop, Mail attachments** (sometimes)

It is NOT applied by:
- Local `cp` / `mv` / `bundle.sh --install`
- `git clone` + build from source

This is why local testing always works but Homebrew installs break — the developer never sees the quarantine flag.

**Fix:** Always notarize. Short-term: strip quarantine in Homebrew cask `postflight` and `bundle.sh --install`.

### Distribution is multi-repo — test the FULL install path

MarkView's distribution involves 3 repos:
1. `markview` — source, build scripts, notarize.sh
2. `homebrew-markview` — cask formula (downloads tar.gz from GitHub Releases)
3. GitHub Releases — the actual .tar.gz artifact

Changes to signing in repo 1 are meaningless if repo 2 doesn't update and repo 3 doesn't get a new release with the notarized artifact. Always test:
```bash
brew uninstall markview; brew install --cask paulhkang94/markview/markview
open -a MarkView  # This is what users see
```

### New build dependencies must be added to CI in the same commit

When adding a tool dependency (e.g., `xcodegen`) to a build script, you MUST also add `brew install <tool>` to the CI workflow in the same commit. The bundle job was broken for 24+ hours because `project.yml` (XcodeGen) was added to `bundle.sh` without updating `ci.yml`.

**Prevention:** Run `bash scripts/check-ci-deps.sh` before committing changes to build scripts.

### CI distribution tests must match the actual install path

If a test checks `/Applications/MarkView.app`, CI must run `bundle.sh --install` (not just `bundle.sh`). The app only exists at `/Applications/` after `--install`. Without it, the test fails because the app is at `./MarkView.app`.

### Release scripts must default to distribution-safe, not opt-in

`release.sh --notarize` was opt-in — which meant it was never used. Auto-detect credentials and enable by default. Dangerous operations should be opt-in; safety gates should be opt-out.

### Disable competing QL extensions before removing their apps

`pluginkit -e ignore -i <bundle-id>` BEFORE deleting an app that provides a QL extension. macOS caches the extension as the preferred handler; deleting the app causes "Extension not found" errors. `qlmanage -r` + `killall quicklookd` + `killall Finder` to clear caches after.

### QLPreviewProvider (data-based) renders as thumbnails in Finder column view

`QLPreviewProvider` returns data (HTML/PDF/image) that QL renders. In Finder column view, this produces a **thumbnail** — a small, non-interactive preview image. No `contentSize` value fixes this; it's how QL displays data-based previews in the sidebar.

`QLPreviewingController` (view-based) provides an `NSViewController` that fills the entire panel — scrollable, interactive, full-size. Use this for document previews.

For sandbox-safe rendering without WKWebView, use `NSAttributedString(html:baseURL:documentAttributes:)` in an `NSTextView`. It handles basic HTML/CSS (headings, bold, tables, blockquotes) and doesn't spawn XPC subprocesses.

**Dark mode caveat:** `NSAttributedString(html:)` bakes in CSS colors at parse time — it doesn't evaluate `@media (prefers-color-scheme: dark)`. You must post-process the attributed string: remap dark foreground colors to light, strip light background colors.

---

## Session 4 — 2026-03-01

### App Sandbox blocks BOTH main process and WKWebView WebContent process

`com.apple.security.app-sandbox` creates two independent restriction layers:
1. **Main process**: `Data(contentsOf: imageURL)` returns nil for files the user didn't explicitly select via an open panel — even with `allowingReadAccessTo` set.
2. **WKWebView WebContent process**: sandboxed independently; `allowingReadAccessTo` doesn't propagate app-level access to this subprocess.

For a Developer ID markdown previewer that needs to read arbitrary local files (images, links), remove `com.apple.security.app-sandbox` from the entitlements. Hardened Runtime (required for notarization) is independent of App Sandbox.

**Do not**: Try `allowingReadAccessTo: baseDirectoryURL` — doesn't bypass sandbox.
**Do not**: Embed images as data URIs — same root cause, `Data(contentsOf:)` also fails under sandbox.
**Do**: Remove `app-sandbox` from `.entitlements`. Keep `cs.allow-unsigned-executable-memory` for WKWebView JIT.

### Swift raw string `#"..."#` terminates at first `"#` inside the content

In `#"..."#` raw string literals, any `"#` sequence inside the string body prematurely ends it. This is silent: `swift run` on a different target compiles fine, but `xcodebuild` on the target that actually includes the file fails.

```swift
// WRONG: [^"#] contains "# which ends the raw string early
let pattern = #"src="([^"#][^"]*\.(png|gif))""#

// CORRECT: use escaped string, or ##"..."## (requires "## to end)
let pattern = "src=\"([^\"]*\\.(png|gif))\""
let pattern = ##"src="([^"#][^"]*\.(png|gif))""##
```

### WKWebView full-width layout — match GitHub not arbitrary max-width

GitHub renders README content fluid to viewport width. Don't add `max-width: 900px; margin: 0 auto` — it creates a dead zone on wide screens and clips tables/images on narrow panes. Match GitHub:
```css
body { max-width: 100%; margin: 0; padding: 16px 32px; box-sizing: border-box; }
```
The `previewWidth` setting overrides this for users who want a constrained reading width.

### GitHub Actions `env:` scope is per-step — secrets don't inherit downstream

Secrets/env vars defined in one step's `env:` block are NOT available to subsequent steps:
```yaml
- name: Store credentials
  env:
    SECRET: ${{ secrets.MY_SECRET }}  # only in THIS step
  run: ...

- name: Use credentials
  run: echo $SECRET  # EMPTY — not inherited
  # Fix: repeat env: block in every step that needs it
```

### CI release workflow pre-flight checklist (learned from 4 failed v1.2.3 tags)

Before pushing a release tag, verify:
1. All required secrets set in repo Settings → Secrets
2. Each step that needs a secret has its own `env:` block with that secret
3. Job has `permissions: contents: write` if creating releases or uploading assets
4. Runner caches are clean — stale SPM binary artifacts cause exit code 74 (`rm -rf ~/Library/Caches/org.swift.swiftpm/artifacts/` before xcodebuild)

### NSTextView spell/grammar checking crashes in QL extension sandbox

`NSTextView` enables spell checking by default, which triggers XPC service lookups (`com.apple.TextInput`) blocked by the QL extension sandbox. Always set `isContinuousSpellCheckingEnabled = false` and `isGrammarCheckingEnabled = false` in extension contexts.

---

## MCP Server Learnings (Session 2026-03-01)

### MCP Protocol is Foundation-backed and rapidly adopting

As of early 2026, MCP (Model Context Protocol) is donated to the Agentic AI Foundation (co-founded by Anthropic, Block, OpenAI, with backing from Google, Microsoft, AWS, Cloudflare, Bloomberg). This is NOT a Anthropic-only initiative — it's an open standard with thousands of MCP servers built across Node.js, Python, Go, and Swift. Safe to invest in long-term.

### No existing markdown MCP server offers native UI + live preview

Competitive analysis shows: Markdownify (PDF/HTML→MD conversion, no preview), MarkItDown (file format conversion, no UI), Feishu Markdown (platform-specific export), Library MCP (knowledge base search, text-only), Notes MCP (CRUD operations, no rendering). **Clear market gap: MarkView is the only native macOS markdown preview MCP server.**

### MCP servers should be separate binaries, not embedded in UI apps

The recommended architecture is a standalone CLI tool (`markview-mcp-server`) using the `MarkViewCore` library via the official Swift MCP SDK. This provides:
- Stateless server (correct MCP design)
- Easy testing (server runs independently)
- Faster iteration (no app rebuild on server changes)
- Standard pattern (most MCP servers are CLI tools)

**Not recommended**: Embedding MCP directly in MarkView.app violates separation of concerns and creates security/debugging issues.

### Swift MCP SDK is mature and macOS-first

The official Swift MCP SDK (github.com/modelcontextprotocol/swift-sdk) supports macOS 13+, uses async/await, includes JSON-RPC stdio transport out of the box, and is actively maintained by Anthropic. No need for Node.js wrapper layers.

### MVP scope is 2-3 days with just 2 tools

Starting with `preview_markdown(content)` and `open_file(path)` covers the core use case: "Claude writes markdown → MarkView opens automatically." Full feature set (resources, export tools, linting) can follow in Phase 2 based on user feedback.

### Auto-open workflow ("AI generates → app launches") is the killer differentiator

The most compelling UX: Claude Desktop user writes markdown → calls `preview_markdown` tool → temp file created → `open -a MarkView` launches app with live preview in ~200ms. Zero user interaction, instant results. This workflow doesn't exist in any other markdown preview tool.

---

## Playwright / HTMLPipeline Testing

### `gen-playwright-fixtures.sh --no-build` uses stale release binary

`--no-build` skips rebuilding `MarkViewHTMLGen`. If `HTMLPipeline.swift`, `template.html`, or any injected JS changed since the last build, the fixture HTML will not reflect those changes. All Playwright tests that assert on the new behavior will time out waiting for DOM state that never appears.

**Rule:** Always run `make playwright` (full build) after any `HTMLPipeline.swift` or `template.html` change. Only use `--no-build` when you've verified the binary is current (e.g., you just ran a successful `make playwright` and only changed test spec files).

### `.mermaid svg` selector catches injected SVG control icons

After injecting pan/zoom/reset/copy buttons inside `.mermaid`, each button's SVG icon matches `.mermaid svg`. Tests that used `.mermaid svg` to find the Mermaid diagram now match the first icon instead.

**Fix:** Use `.mermaid-inner svg` (the diagram container) for diagram assertions. Use `.mermaid-controls svg` for icon assertions. Never use bare `.mermaid svg` when controls are injected.

### `Tests/` vs `tests/` casing — macOS merges, Linux fails

macOS filesystem is case-insensitive: `Tests/` and `tests/` resolve to the same directory. SPM test targets and Playwright tests can accidentally share a directory on macOS with no visible error. Linux CI is case-sensitive and will fail with "directory not found".

**Rule:** Keep all Playwright tests in lowercase `tests/` (project root). Keep all SPM test sources in `Tests/` (SPM convention, uppercase). Never cross-reference them. Audit with `ls -la` and verify both directories are distinct before assuming the split is correct.
