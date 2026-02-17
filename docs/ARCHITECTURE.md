# MarkView — Architecture & Technical Reference

## Overview

MarkView is a native macOS markdown previewer built with Swift 6 / SPM. It renders GitHub Flavored Markdown via cmark-gfm, displays it in a WKWebView with live preview, and supports editing, linting, scroll sync, file watching, and export. The architecture cleanly separates a platform-independent core library from the SwiftUI app layer, enabling thorough testing without an app bundle.

**Platform:** macOS 14+ (Sonoma) — required for CADisplayLink, os.Logger, @Observable
**Build system:** Pure SPM — no Xcode project needed, builds with Command Line Tools only

## Why We Built It This Way

### Core Constraints That Shaped the Architecture

1. **No Xcode project** — SPM-only means no `.xcodeproj`, no XIBs, no storyboards. Every UI element is SwiftUI or NSViewRepresentable. This also means we can't use XCTest (it requires an Xcode test target), which led to the standalone test runner pattern.

2. **macOS 14 minimum** — We deliberately target N-2 (not oldest supported). macOS 14 unlocks CADisplayLink (frame-synced scroll), @Observable, os.Logger with categories, and modern Swift concurrency features. The tradeoff: ~5% of macOS users on older versions can't run MarkView.

3. **Core library with zero UI deps** — MarkViewCore imports only Foundation + cmark-gfm. This means 276 tests run in <5s via `swift run MarkViewTestRunner` — no app bundle, no window server, no Accessibility permissions needed.

4. **WKWebView for preview** — Not a custom renderer. WKWebView gives us CSS styling, Prism.js syntax highlighting (18 languages), native PDF export via `createPDF()`, and VoiceOver support for free.

5. **NSTextView for editing** — SwiftUI's TextEditor lacks find/replace, undo/redo, and spell check integration. NSTextView gives us all of these natively through NSViewRepresentable.

---

## Module Structure

```
Sources/
├── MarkViewCore/                  # Library — no UI deps, fully testable
│   ├── MarkdownRenderer.swift     # cmark-gfm rendering + accessibility post-processing
│   ├── FileWatcher.swift          # DispatchSource file monitoring (atomic save aware)
│   ├── MarkdownLinter.swift       # 9-rule linter + auto-fix for safe rules
│   ├── MarkdownSuggestions.swift   # Autocomplete for fences, emoji, headings, links
│   ├── HTMLSanitizer.swift        # XSS prevention (strips scripts, event handlers)
│   ├── LanguagePlugin.swift       # Plugin protocol + registry
│   ├── Metrics.swift              # Local-only opt-in usage analytics
│   └── Plugins/
│       ├── MarkdownPlugin.swift   # Default cmark-gfm renderer
│       ├── CSVPlugin.swift        # CSV/TSV → HTML table
│       └── HTMLPlugin.swift       # HTML passthrough + sanitization
│
├── MarkView/                      # SwiftUI app executable
│   ├── MarkViewApp.swift          # @main, window management, menus, CLI args
│   ├── ContentView.swift          # Editor/preview split layout + drop target
│   ├── PreviewViewModel.swift     # State machine: render, lint, watch, save
│   ├── WebPreviewView.swift       # WKWebView wrapper with scroll sync JS
│   ├── EditorView.swift           # NSTextView wrapper with find bar, settings
│   ├── ScrollSyncController.swift  # CADisplayLink bidirectional scroll sync
│   ├── Settings.swift             # 17 UserDefaults-backed settings
│   ├── StatusBarView.swift        # Word count, lint badges, file path
│   ├── ErrorBanner.swift          # Slide-down notification (5s auto-dismiss)
│   ├── ErrorPresenter.swift       # Error state + GitHub issue URL builder
│   ├── ExportManager.swift        # HTML/PDF export via save panel
│   ├── Document.swift             # File model (minimal)
│   ├── AppLogger.swift            # os.Logger categories + Sentry integration
│   ├── ResourceBundle.swift       # Translocation-safe resource bundle lookup
│   ├── Strings.swift              # Centralized UI strings (localization-ready)
│   ├── Info.plist                 # Document type registrations (.md, .markdown)
│   └── Resources/
│       ├── template.html          # HTML template with GitHub-style CSS
│       └── prism-bundle.min.js    # Prism.js syntax highlighting (18 languages)
│
├── MarkViewMCPServer/             # MCP server for AI tool integration
│   └── main.swift                 # stdio JSON-RPC: preview_markdown, open_file
│
└── MarkViewQuickLook/             # Quick Look extension
    ├── PreviewProvider.swift       # QLPreviewProvider returning rendered HTML
    └── Info.plist                  # Extension point: com.apple.quicklook.preview

Tests/
├── TestRunner/                    # 276 tests across 3 tiers + linter + plugins
│   ├── main.swift                 # TestRunner struct, expect(), fixture loading
│   └── Fixtures/                  # .md inputs, .html goldens, lint/csv/html tests
├── FuzzTester/                    # 10K random markdown inputs → no crashes
├── DiffTester/                    # Compare output vs cmark-gfm CLI
├── VisualTester/                  # Screenshot comparison + WCAG contrast
└── E2ETester/                     # UI automation via AXUIElement APIs (30 tests)
    ├── main.swift                 # Test orchestration (5 tiers)
    ├── AXHelper.swift             # Accessibility API wrapper
    ├── AppController.swift        # App lifecycle (launch, terminate, find window)
    └── TestHelpers.swift          # High-level E2E operations
```

---

## Architectural Layers

```
┌──────────────────────────────────────────────────────────────────┐
│  macOS App  (MarkView.app)                                       │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ UI Layer (SwiftUI + NSViewRepresentable)                   │  │
│  │   MarkViewApp → ContentView → EditorView + WebPreviewView  │  │
│  │   StatusBarView, ErrorBanner, SettingsView, DropTargetView │  │
│  └────────────────────────────────────────────────────────────┘  │
│                           │                                      │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Coordination Layer                                         │  │
│  │   PreviewViewModel   (state machine: render/lint/watch)    │  │
│  │   ScrollSyncController (CADisplayLink frame-synced sync)   │  │
│  │   ExportManager      (HTML/PDF export)                     │  │
│  │   ErrorPresenter     (notification lifecycle)              │  │
│  │   AppLogger          (os.Logger + Sentry)                  │  │
│  │   ResourceBundle     (translocation-safe resource access)  │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                              │ imports
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  MarkViewCore  (library — no UI deps, fully testable)            │
│                                                                  │
│  Rendering:    MarkdownRenderer, HTMLSanitizer, PluginRegistry   │
│  Analysis:     MarkdownLinter (9 rules), MarkdownSuggestions     │
│  System:       FileWatcher (DispatchSource, atomic save aware)   │
│  Telemetry:    Metrics (local-only, opt-in)                      │
│  Plugins:      CSVPlugin, HTMLPlugin, MarkdownPlugin             │
└──────────────────────────────────────────────────────────────────┘
                              │ imported by
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  Extensions & Tools                                              │
│                                                                  │
│  MarkViewQuickLook  — Finder spacebar preview (.appex)           │
│  MarkViewMCPServer  — AI tool integration (preview_markdown)     │
│  Test Executables   — TestRunner, Fuzz, Diff, Visual, E2E        │
└──────────────────────────────────────────────────────────────────┘
```

---

## Key Data Flows

### File Open → Render → Display

```
User opens file (CLI arg / drag-drop / File > Open / MCP / Finder double-click)
  │
  ▼
PreviewViewModel.loadFile(path)
  ├── loadTemplate()           → Cache template.html from bundle (once)
  ├── loadContent(path)        → Read file, renderImmediate(), runLint(), isLoaded=true
  ├── watchFile(path)          → FileWatcher(path) monitors external changes
  └── startAutoSaveTimer()     → Timer at autoSaveInterval (if enabled)

renderImmediate(markdown):
  1. MarkdownRenderer.renderHTML(from:)     → cmark-gfm parse → GFM HTML
  2. MarkdownRenderer.wrapInTemplate(html)  → Inject into template with CSS
  3. renderedHTML = result                  → SwiftUI binding triggers WebView update

WebPreviewView receives new HTML:
  - If base directory unchanged: JS replaceContent() → preserves scroll
  - If base directory changed:   Full page reload via temp file + loadFileURL
```

### User Edits in Editor

```
User types in EditorView (NSTextView)
  │
  ▼
Coordinator.textDidChange → onChange(newText)
  │
  ▼
PreviewViewModel.contentDidChange(newText)
  ├── isDirty = (newText != originalContent)
  ├── renderDebounced()   → 150ms debounce → renderImmediate()
  └── lintDebounced()     → 300ms debounce → runLint() → update diagnostics
```

### Scroll Sync (Frame-Perfect)

```
User scrolls editor pane
  │
  ▼
EditorView.Coordinator detects scroll via NSView bounds change
  │
  ▼
ScrollSyncController.editorDidScrollToLine(line)
  ├── Stores pendingPreviewLine
  ├── Echo suppression check (50ms window)
  └── CADisplayLink fires on next vsync
       │
       ▼
       previewCoordinator.scrollToSourceLine(line)
         → JS binary-searches sourcepos cache
         → window.scrollTo(element.offsetTop)

(Reverse direction: preview scroll → JS postMessage → coordinator → editor)
```

### External File Change

```
FileWatcher DispatchSource fires (.write / .rename / .delete / .attrib)
  │
  ▼
100ms debounce → callback
  │
  ├── If !isDirty: loadContent(from: path)    → Silent auto-reload
  └── If isDirty:  externalChangeConflict=true → Alert: "Reload" / "Keep Mine"
```

---

## Design Decision Rationale

### Why cmark-gfm (not a Swift parser)?

cmark-gfm is the reference implementation of GitHub Flavored Markdown. Using it via Apple's swift-cmark package guarantees GFM fidelity — tables, strikethrough, autolinks, task lists, and footnotes all work exactly as on GitHub. A pure Swift parser would need to track GFM spec changes and risk divergence.

The SOURCEPOS flag adds `data-sourcepos="line:col-endline:endcol"` to every rendered element, enabling bidirectional scroll sync between editor and preview without maintaining a separate AST.

### Why no XCTest?

SPM executable targets can't use XCTest without an Xcode test target. Our custom `TestRunner` struct provides the same functionality:

```swift
struct TestRunner {
    var passed = 0, failed = 0, skipped = 0
    mutating func test(_ name: String, _ body: () throws -> Void)
    mutating func skip(_ name: String, reason: String)
    func summary()
}
```

This enables `swift run MarkViewTestRunner` — no Xcode, no simulator, no .xctest bundle. Tests run in <5s and work in CI with just Command Line Tools installed.

### Why DispatchSource for file watching (not FilePresenter)?

`NSFilePresenter` is designed for document-based apps with NSDocument. It conflicts with direct file I/O and doesn't handle atomic saves (write-to-temp + rename) that editors like VS Code and Vim use.

`DispatchSourceFileSystemObject` watches at the file descriptor level:
- `.write` — direct edits
- `.rename` — atomic save (temp file renamed to target)
- `.delete` — file removed (re-watch after delay)
- `.attrib` — permission changes

On rename/delete, FileWatcher closes the old descriptor and opens a new one at the same path after 50ms (waiting for the rename to complete).

### Why CADisplayLink for scroll sync (not Timer)?

CADisplayLink fires exactly once per display refresh (60 Hz = 16.7ms, or 120 Hz on ProMotion). A Timer fires independently of vsync, causing visible jitter when scroll updates land between frames.

Echo suppression (50ms window) prevents A→B→A scroll loops. The 50ms window is tuned empirically — long enough to catch feedback from the other pane, short enough that intentional rapid scrolling still works.

os_signpost instrumentation enables profiling in Instruments.app:
```
ScrollSyncCycle: editorScrollToLine → previewApplyScroll → complete
```

### Why WKWebView + JS injection (not page reload)?

Full page reloads destroy scroll position and Prism.js highlighting state. Instead, we update content via JS:

```javascript
document.getElementById('content').innerHTML = newHTML;
Prism.highlightAll();
```

This preserves scroll position and applies syntax highlighting incrementally. Full reload only happens when the base directory changes (needed for resolving relative image paths).

### Why template-based HTML?

The renderer outputs body HTML only. `wrapInTemplate()` injects it into a full HTML document with:
- GitHub-like CSS styling (light/dark themes)
- Responsive width (configurable: 700px–100%)
- Prism.js script tag
- Settings-injected CSS overrides (font size, theme)

This separation means custom themes can be applied by swapping the template, and exports get the same styling as preview.

### Why ResourceBundle multi-location lookup?

SPM places resource bundles at the `.app` root level. But macOS Gatekeeper's app translocation copies only `Contents/` into the randomized path — losing the root-level bundle.

`ResourceBundle.swift` checks three locations:
1. `Contents/Resources/MarkView_MarkView.bundle` (translocation-safe)
2. `.app` root (SPM default, backward compat)
3. SPM build directory (development via `swift run`)

`bundle.sh` copies the resource bundle into `Contents/Resources/` during bundling.

### Why local-only metrics?

Privacy-first design. `Metrics.swift` collects session data (files opened, render times, features used) in `~/Library/Application Support/MarkView/metrics.json`. Data is never transmitted. The user can inspect the JSON directly. Opt-in is off by default.

---

## Dependencies & Their Roles

| Dependency | Version | Role | Why |
|-----------|---------|------|-----|
| swift-cmark | 0.4.0+ | GFM rendering | Reference GFM implementation, sourcepos support |
| swift-sdk (MCP) | 0.10.0+ | AI tool integration | Model Context Protocol for Claude/other AI tools |
| sentry-cocoa | 9.4.0+ | Error reporting | Crash reports + breadcrumbs, 10% sample in prod |

### Why Sentry?

Production error visibility. Development uses unsampled collection (all errors), production samples 10%. Breadcrumbs with categories (file, render, sync, export) provide context for crash reports. The GitHub issue URL builder in ErrorPresenter also leverages Sentry context.

---

## Test Strategy

| Target | Tests | What It Validates |
|--------|-------|-------------------|
| **MarkViewTestRunner** | 276 | Renderer, GFM compliance, FileWatcher, linter, plugins, goldens, performance gates |
| **MarkViewFuzzTester** | 10K inputs | No crashes on random markdown (including random bytes) |
| **MarkViewDiffTester** | ~40 fixtures | Output matches cmark-gfm CLI (reference implementation) |
| **MarkViewVisualTester** | ~10 screenshots | Pixel-level comparison + WCAG contrast validation |
| **MarkViewE2ETester** | 30 | UI automation: launch, edit, save, file watch, conflict resolution, settings |

### Test Tiers

| Tier | Scope | Speed |
|------|-------|-------|
| 0 | Build succeeds (`swift build`) | ~30s |
| 1 | Renderer unit tests, GFM extensions, FileWatcher, linter, plugins | <3s |
| 2 | Fixture-based GFM compliance, performance benchmarks, stress tests | <2s |
| 3 | Golden file regression, full-template E2E, determinism, performance gates | <1s |
| Extended | Fuzz (10K), differential (vs cmark-gfm), visual, Quick Look, E2E (30 tests) | ~90s |

### Why Standalone Test Executables?

Each test type has fundamentally different requirements:
- **Unit/integration** (TestRunner): Fast, deterministic, no external deps
- **Fuzz** (FuzzTester): High volume, crash detection, non-deterministic
- **Differential** (DiffTester): Requires cmark-gfm CLI binary
- **Visual** (VisualTester): Requires WKWebView offscreen rendering, golden images
- **E2E** (E2ETester): Requires .app bundle, Accessibility permissions, window server

Separate executables mean you only pay the cost of what you run. CI can skip E2E tests on headless runners.

---

## Usage Methods

| Method | How | Requirements |
|--------|-----|-------------|
| **CLI** (`mdpreview file.md`) | `scripts/install-cli.sh` → symlinks to `~/.local/bin/` | .app installed |
| **Finder Open With** | `scripts/bundle.sh --install` → registers with Launch Services | .app in /Applications |
| **Quick Look** (spacebar) | Embedded .appex in .app bundle | Developer ID signing + notarization |
| **MCP Server** | `markview-mcp-server` in .app bundle | AI tool configured |
| **Direct** (`swift run MarkView`) | SPM development mode | Swift toolchain |

---

## Build & Bundle Pipeline

```bash
swift build                        # Debug build (all targets)
swift build -c release             # Release build
bash scripts/bundle.sh             # Create MarkView.app bundle
bash scripts/bundle.sh --install   # Bundle + install to /Applications
bash scripts/install-cli.sh        # Install mdpreview CLI to ~/.local/bin/
```

### Bundle Structure

```
MarkView.app/
├── Contents/
│   ├── Info.plist                          # Bundle metadata, document types
│   ├── PkgInfo                             # "APPL????"
│   ├── MacOS/
│   │   ├── MarkView                        # Main executable
│   │   └── markview-mcp-server             # MCP server binary
│   ├── Resources/
│   │   └── MarkView_MarkView.bundle/       # SPM resource bundle
│   │       └── Resources/
│   │           ├── template.html
│   │           └── prism-bundle.min.js
│   └── PlugIns/
│       └── MarkViewQuickLook.appex/        # Quick Look extension
│           ├── Contents/
│           │   ├── Info.plist
│           │   ├── PkgInfo                 # "XPC!????"
│           │   └── MacOS/
│           │       └── MarkViewQuickLook
```

### Why This Bundle Layout?

SPM builds flat binaries. `bundle.sh` assembles the macOS bundle structure that Launch Services, Quick Look, and app translocation expect. The resource bundle goes into `Contents/Resources/` (not the .app root) specifically for Gatekeeper translocation resilience.

---

## Settings (17 Total)

| Setting | Default | Range | Storage Key |
|---------|---------|-------|-------------|
| Editor font size | 14pt | 10–24 | `editorFontSize` |
| Editor font family | SF Mono | SF Mono/Menlo/Courier/Monaco | `editorFontFamily` |
| Editor line spacing | 1.4 | 1.0–2.0 | `editorLineSpacing` |
| Word wrap | on | toggle | `wordWrap` |
| Spell check | on | toggle | `spellCheck` |
| Line highlight | off | toggle | `lineHighlight` |
| Minimap | off | toggle | `minimapEnabled` |
| Tab behavior | 4 spaces | 2sp/4sp/tab | `tabBehavior` |
| Format on save | on | toggle | `formatOnSave` |
| Preview font size | 16pt | 12–24 | `previewFontSize` |
| Preview width | Medium (900px) | 700/900/1200/100% | `previewWidth` |
| Theme | System | Light/Dark/System | `theme` |
| Auto-save | off | toggle | `autoSave` |
| Auto-save interval | 5s | 1–30s | `autoSaveInterval` |
| Window restore | on | toggle | `windowRestore` |
| Metrics opt-in | off | toggle | `metricsOptIn` |
| Default open dir | (empty) | path | `defaultOpenDir` |

All settings stored in UserDefaults via `@AppStorage`. `AppSettings.shared` singleton accessed throughout the app.

---

## Performance Characteristics

| Operation | Typical Latency | Mechanism |
|-----------|----------------|-----------|
| Markdown render (small file) | <5ms | cmark-gfm C parser |
| Markdown render (50KB file) | <50ms | cmark-gfm with GFM extensions |
| Render debounce | 150ms | Task.sleep cancelation |
| Lint debounce | 300ms | Task.sleep cancelation |
| Scroll sync | 1 frame (16.7ms @ 60Hz) | CADisplayLink |
| File watch reaction | ~150ms | DispatchSource + 100ms debounce |
| Auto-save | Configurable (1–30s) | Timer.scheduledTimer |
| Error banner dismiss | 5s | DispatchQueue.main.asyncAfter |
