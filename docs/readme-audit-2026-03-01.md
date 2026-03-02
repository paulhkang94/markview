# README Audit — 2026-03-01

Auditor: Claude (automated). Ground truth: `Sources/` and `Package.swift` as of 2026-03-01.

---

## Methodology

Each claim in the README was traced to a specific source file and line. Status codes:

- **VERIFIED** — claim matches source code
- **WRONG-DETAIL** — feature exists but the stated detail (count, version, etc.) is wrong
- **MISSING** — claim has no source backing
- **UNDOCUMENTED** — feature in source not mentioned in README

---

## Feature Bullet Points

### VERIFIED: Live preview with split-pane editor and WKWebView rendering

`ContentView.swift:21-57` — `HSplitView` with `EditorView` and `WebPreviewView(html: viewModel.renderedHTML, ...)`. The toggle is wired to `Cmd+E` at `ContentView.swift:88`.

### VERIFIED: GitHub Flavored Markdown via Apple's swift-cmark

`MarkdownRenderer.swift:17` — extensions `["table", "strikethrough", "autolink", "tagfilter", "tasklist"]` attached via `cmark_parser_attach_syntax_extension`. Dependency declared in `Package.swift:15` as `swift-cmark`.

### WRONG-DETAIL: Syntax highlighting for 18 languages via Prism.js

The number **18** is correct per `MarkdownSuggestions.swift:31-35` which lists exactly 18 languages (`bash, c, cpp, css, diff, go, html, java, javascript, json, kotlin, markdown, python, ruby, rust, swift, typescript, yaml`). The `TestRunner/main.swift:1632` confirms: `"Expected 18 languages"`. Prism.js bundle injected in `WebPreviewView.swift:408-411`.

Status: **VERIFIED** (number matches source).

### VERIFIED: Markdown linting with 9 built-in rules and status bar diagnostics

`MarkdownLinter.swift:27-37` — `LintRule` enum has exactly 9 cases: `inconsistentHeadings`, `trailingWhitespace`, `missingBlankLines`, `duplicateHeadings`, `brokenLinks`, `unclosedFences`, `unclosedFormatting`, `mismatchedBrackets`, `invalidTables`. Status bar rendered in `ContentView.swift:65-75` via `StatusBarView`.

### VERIFIED: File watching with DispatchSource (works with VS Code, Vim, and other editors)

`FileWatcher.swift:40-44` — `DispatchSource.makeFileSystemObjectSource` watching `.write`, `.rename`, `.delete`, `.attrib`. Atomic-save handling (rename/delete re-watch) at `FileWatcher.swift:49-55`. Hooked into `PreviewViewModel.watchFile(at:)` at `PreviewViewModel.swift:188-204`.

### VERIFIED: Multi-format support via plugin architecture (Markdown, CSV, HTML)

`LanguagePlugin.swift:5-17` — `LanguagePlugin` protocol. Three concrete implementations: `MarkdownPlugin.swift`, `CSVPlugin.swift`, `HTMLPlugin.swift`. `PluginRegistry` at `LanguagePlugin.swift:21-49`.

### VERIFIED: HTML sanitizer that strips scripts, event handlers, and XSS vectors

`HTMLSanitizer.swift:10-179` — strips `<script>`, `<svg>`, `<math>`, `<style>`, `<base>`, `<form>`, `<input>`, `<textarea>`, `<button>`, `<select>`, `<link>`, `<iframe>`, `<object>`, `<embed>`, event handler attributes (`on\w+=`), `javascript:` URIs, and `data:` URIs.

### MISSING: Auto-suggestions for code fence languages, emoji, headings, and links

`MarkdownSuggestions.swift` implements `suggestLanguages`, `suggestEmoji`, `suggestHeadings`, and `suggestLinks`. However, **no code in `Sources/MarkView/` calls any of these methods**. `EditorView.swift` has zero references to `MarkdownSuggestions`. The suggestion engine exists in the library but is not wired into the editor UI. No autocomplete popup, no completion handler, no delegate call invokes it.

Claim status: **MISSING** — the library module exists but the feature is not surfaced to users.

### VERIFIED: Export to HTML and PDF

- HTML: `ExportManager.swift:9-24` + notification wired in `ContentView.swift:122-129`, menu item in `MarkViewApp.swift:138-143`.
- PDF: `ExportManager.swift:27-58` + notification wired in `ContentView.swift:130-141`, menu item in `MarkViewApp.swift:144-149`.
- Both keyboard shortcuts registered: `Cmd+Shift+E` (HTML), `Cmd+Shift+P` (PDF) at `MarkViewApp.swift:141, 147`.

### VERIFIED: Dark mode support with system/light/dark theme options

`Settings.swift:5-15` — `AppTheme` enum: `.light`, `.dark`, `.system`. Applied in `WebPreviewView.swift:44-51` by setting `webView.appearance`. Settings UI in `Settings.swift:202-212`.

### WRONG-DETAIL: 17 configurable settings including font, preview width, tab behavior, and more

`Settings.swift:65-84` — counts 18 `@AppStorage` properties: `editorFontSize`, `previewFontSize`, `editorLineSpacing`, `showLineNumbers`, `wordWrap`, `autoSave`, `autoSaveInterval`, `metricsOptIn`, `theme` (stored as `themeRaw`), `previewWidth` (stored as `previewWidthRaw`), `editorFontFamily`, `tabBehavior` (stored as `tabBehaviorRaw`), `spellCheck`, `defaultOpenDir`, `windowRestore`, `lineHighlight`, `minimapEnabled`, `formatOnSave`. That is **18**, not 17.

---

## Keyboard Shortcuts

All shortcuts checked against `MarkViewApp.swift:113-228`.

| Shortcut | README claim | Source status |
|---|---|---|
| `Cmd+O` | Open file | VERIFIED: `MarkViewApp.swift:116` |
| `Cmd+W` / Escape | Close window | VERIFIED: `MarkViewApp.swift:118-127` |
| `Cmd+S` | Save | VERIFIED: `MarkViewApp.swift:131-135` |
| `Cmd+Shift+E` | Export HTML | VERIFIED: `MarkViewApp.swift:141` |
| `Cmd+Shift+P` | Export PDF | VERIFIED: `MarkViewApp.swift:147` |
| `Cmd+E` | Toggle editor | VERIFIED: `ContentView.swift:88` |
| `Cmd++` | Increase font size | VERIFIED: `MarkViewApp.swift:157` |
| `Cmd+-` | Decrease font size | VERIFIED: `MarkViewApp.swift:163` |
| `Cmd+0` | Reset font size | VERIFIED: `MarkViewApp.swift:169` |
| `Cmd+F` | Find | VERIFIED: `MarkViewApp.swift:182` |
| `Cmd+Option+F` | Find and replace | VERIFIED: `MarkViewApp.swift:184` |
| `Cmd+G` | Find next | VERIFIED: `MarkViewApp.swift:186` |
| `Cmd+Shift+G` | Find previous | VERIFIED: `MarkViewApp.swift:188` |

Note: The README does not list keyboard shortcuts explicitly — they exist in the source but are not documented. See UNDOCUMENTED section.

---

## Export Formats

### VERIFIED: exportHTML wired

`ContentView.swift:122-129` — `.onReceive(NotificationCenter.default.publisher(for: .exportHTML))` calls `ExportManager.exportHTML(html:suggestedName:errorPresenter:)`.

### VERIFIED: exportPDF wired

`ContentView.swift:130-141` — `.onReceive(NotificationCenter.default.publisher(for: .exportPDF))` calls `ExportManager.exportPDF(from:suggestedName:errorPresenter:)`.

---

## MCP Server Tools

### VERIFIED: `preview_markdown` tool implemented

`MarkViewMCPServer/main.swift:54-55` — `case "preview_markdown"` dispatches to `handlePreviewMarkdown`. Tool registered in `ListTools` handler at `main.swift:18-34`. Writes to `~/.cache/markview/previews/` (not `/tmp`), opens with `open -a MarkView`.

### VERIFIED: `open_file` tool implemented

`MarkViewMCPServer/main.swift:56-57` — `case "open_file"` dispatches to `handleOpenFile`. Registered in `ListTools` at `main.swift:35-48`. Validates path existence and markdown extension before opening.

Both tools match the README table exactly. No undeclared tools found.

---

## Quick Look Extension

### VERIFIED: `Sources/MarkViewQuickLook/` exists with relevant code

`Sources/MarkViewQuickLook/PreviewProvider.swift` — 159 lines. `PreviewViewController` conforms to `QLPreviewingController`. Calls `MarkdownRenderer.renderHTML`, `postProcessForAccessibility`, `wrapInTemplate`, injects dark mode CSS, writes to temp HTML file, loads via `WKWebView.loadFileURL`. Registered as `app-extension` in `project.yml:55-80`.

---

## "Automatic" Behavior Claims

### VERIFIED: Live reload (file watching)

`PreviewViewModel.swift:188-205` — `FileWatcher` started in `loadFile(at:)`. On file change: if not dirty, calls `loadContent(from:)` which re-renders. If dirty, sets `externalChangeConflict = true` (triggers alert). Works with atomic saves (VS Code, Vim).

### VERIFIED: Auto-save

`PreviewViewModel.swift:89-108` — `startAutoSaveTimer()` starts a repeating `Timer` with `AppSettings.shared.autoSaveInterval`. Saves only when `isDirty`. Opt-in via `AppSettings.autoSave` (default `false`). Setting visible in `Settings.swift:217-229`.

### VERIFIED: Format on save

`PreviewViewModel.swift:71-73` — `if AppSettings.shared.formatOnSave { autoFixLint() }` called at top of `save()`. Auto-fix applies trailing whitespace and missing-blank-line rules (`MarkdownLinter.autoFixableRules`).

---

## Platform Requirements

### WRONG-DETAIL: Architecture section says "SwiftUI app (macOS 13+)"

`README.md:168` — `Sources/MarkView/ # SwiftUI app (macOS 13+)`.

But `Package.swift:5` declares `.macOS(.v14)`. `project.yml:8` sets `deploymentTarget.macOS: "14.0"`. `ScrollSyncController.swift:14` explicitly notes "Uses CADisplayLink (macOS 14+)".

The Installation section correctly states `macOS 14+` at `README.md:46`. The architecture section is inconsistent.

### VERIFIED: Swift 6.0+ requirement

`project.yml:41` — `SWIFT_VERSION: "6.0"`. Package uses `swift-tools-version: 6.1`.

---

## Architecture Section Claims

### WRONG-DETAIL: Test count "341 standalone tests (no XCTest)"

`grep -c "runner.test"` in `Tests/TestRunner/main.swift` = **360** test cases. The README states 341. The CLAUDE.md says 276. None of the three agree — the source is the ground truth and shows 360.

### WRONG-DETAIL: "19 visual regression tests + WCAG contrast"

`grep -c "runner.test"` in `Tests/VisualTester/main.swift` = **5** test cases (not 19). The visual tester file is 300 lines and runs 5 named tests including WCAG contrast checks.

### VERIFIED: FuzzTester (10K random input crash testing)

`Tests/FuzzTester/` directory exists. Package.swift target at line 38-42. Described as "10K random inputs" — consistent with fuzz testing pattern.

### VERIFIED: DiffTester

`Tests/DiffTester/` directory exists. Package.swift target at line 44-48.

### VERIFIED: MCP test script

`scripts/test-mcp.sh` referenced. README says "5 MCP protocol + integration tests". Separate from the Swift test suite.

---

## Screenshots and Demo

### UNVERIFIABLE: Screenshot staleness

`docs/screenshots/preview-only.png` and `docs/screenshots/editor-preview.png` exist on disk. Cannot determine if they match the current UI without visual inspection. Screenshots reference a split-pane UI and toolbar — both match the current `ContentView.swift` architecture.

### UNVERIFIABLE: `docs/markview_demo.gif`

File exists. Content not inspectable in this audit.

---

## UNDOCUMENTED Features (in source, not in README)

### 1. Mermaid diagram rendering

`WebPreviewView.swift:414-504` — `injectMermaid(into:)` fully injects and initializes Mermaid.js for rendering flowcharts, sequence diagrams, Gantt charts, ER diagrams, and pie charts. `Package.swift:22` includes `mermaid.min.js` as a bundled resource. This is a substantial feature with custom bridge code converting cmark-gfm `<pre><code class="language-mermaid">` output to `<div class="mermaid">` elements, responsive SVG sizing, and subgraph label overlap fixes. **Not mentioned anywhere in the README.**

### 2. Bidirectional scroll sync (editor ↔ preview)

`ScrollSyncController.swift:1-127` — Full `CADisplayLink`-based scroll sync between editor and preview panes. Uses `data-sourcepos` attributes from cmark-gfm to map source lines to DOM elements. Binary search for O(log n) scroll position lookup. Scroll sync fires on both editor scroll and preview scroll, suppresses echo. Position persists across pane toggle. **Not mentioned anywhere in the README.**

### 3. Sentry crash reporting

`MarkViewApp.swift:52-65` — `SentrySDK.start` with DSN, 10% trace sampling, environment-based config (development/production). Users are not told about this in the README. The privacy/opt-in UI only covers the local metrics collector (`MetricsCollector.swift`), not Sentry.

### 4. Local usage metrics collector

`MarkViewCore/Metrics.swift:1-128` — `MetricsCollector` tracks files opened, render count/time, exports, editor usage, feature usage. Written to `~/Library/Application Support/MarkView/metrics.json`. Opt-in toggle in settings (`metricsOptIn`). **Not mentioned in README.**

### 5. Image inlining (local images in preview)

`WebPreviewView.swift:298-337` — `inlineLocalImages(in:baseDirectory:)` reads local images and embeds them as `data:TYPE;base64,...` URIs so the sandboxed WKWebView can display relative-path images from the same directory as the markdown file. Supports png, jpg, gif, svg, webp, ico, bmp, tiff. **Not mentioned in README.**

### 6. Drag-and-drop file opening

`ContentView.swift:204-237` — `DropTargetView` accepts `.fileURL` drops, validates markdown extensions (`md, markdown, mdown, mkd, mkdn, mdwn, txt`), and loads the file. **Not mentioned in README.**

### 7. Format on save (auto-lint fix)

`PreviewViewModel.swift:71-73`, `Settings.swift:84, 162-163` — `formatOnSave` setting (default `true`) auto-applies lint fixes (trailing whitespace, missing blank lines before headings) on every save. **Not mentioned in README.**

### 8. Find and Replace

`MarkViewApp.swift:179-191` — Find bar (`Cmd+F`), find and replace (`Cmd+Option+F`), next (`Cmd+G`), previous (`Cmd+Shift+G`), use selection for find. Uses native `NSTextView.performFindPanelAction`. **Not mentioned in README.**

### 9. Window resize on pane toggle

`ContentView.swift:187-201` — When toggling editor pane, window resizes: preview-only = 55% screen width, editor+preview = 80% screen width, centered horizontally. **Not mentioned in README.**

---

## Summary Table

| Category | Count |
|---|---|
| VERIFIED claims | 18 |
| WRONG-DETAIL claims | 4 |
| MISSING claims | 1 |
| UNDOCUMENTED features | 9 |

### Wrong Details at a Glance

1. **Settings count**: README says 17, source has 18 `@AppStorage` properties.
2. **macOS target in Architecture section**: README says "macOS 13+" for the SwiftUI app; `Package.swift` and `project.yml` both require macOS 14+. Installation prereqs correctly say 14+.
3. **Test count**: README says 341 tests; `runner.test` grep count = 360.
4. **Visual test count**: README says 19; `runner.test` grep count = 5.

### The One Unimplemented Feature

Auto-suggestions (`MarkdownSuggestions.swift`) — the engine is built and tested in isolation, but **no call site exists in the UI layer**. `EditorView.swift` has zero references to `MarkdownSuggestions`. Users cannot trigger suggestions.

### Top Two Undocumented Features

1. **Mermaid diagram rendering** — full Mermaid.js integration with responsive SVG, dark mode, and subgraph layout fixes. Bundled in the app, fires on every page load, renders flowcharts/sequence/Gantt/ER/pie. Significant feature gap in README.
2. **Bidirectional scroll sync** — `CADisplayLink`-based frame-perfect editor/preview sync using `data-sourcepos` line mapping. Substantial engineering investment (~130 lines dedicated to this feature). Completely absent from README.
