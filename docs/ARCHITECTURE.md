# MarkView — Architecture

## Overview

MarkView is a native macOS markdown preview app built with Swift/SPM.

## Module Structure

```
Sources/MarkViewCore/           # Library (no UI, fully testable)
  MarkdownRenderer.swift        # cmark-gfm C API wrapper
  FileWatcher.swift             # DispatchSource file monitoring
  Metrics.swift                 # Local-first opt-in analytics
  MarkdownLinter.swift          # 9-rule pure Swift linting engine
  MarkdownSuggestions.swift     # Auto-suggest for code fences, emoji, headings, links
  LanguagePlugin.swift          # Plugin protocol + registry
  HTMLSanitizer.swift           # XSS prevention (strips scripts, event handlers)
  Plugins/
    MarkdownPlugin.swift        # cmark-gfm renderer (default)
    CSVPlugin.swift             # CSV → HTML table
    HTMLPlugin.swift            # HTML passthrough + sanitization

Sources/MarkView/               # SwiftUI app (macOS 13+)
  MarkViewApp.swift             # @main, menus, CLI args, Open With handler
  ContentView.swift             # Main view with editor/preview split
  PreviewViewModel.swift        # State management, debounced render + lint
  WebPreviewView.swift          # WKWebView with Prism.js syntax highlighting
  EditorView.swift              # Monospaced TextEditor with settings
  ExportManager.swift           # HTML/PDF export
  Settings.swift                # 17 settings with theme/width/font enums
  StatusBarView.swift           # Word count, lint diagnostics
  Document.swift                # Document model
  Info.plist                    # App bundle document type associations
  Resources/
    template.html               # HTML template with GitHub-style CSS
    prism-bundle.min.js         # Syntax highlighting (18 languages)

Tests/TestRunner/               # Standalone test suite (no XCTest)
Tests/FuzzTester/               # Random input crash testing
Tests/DiffTester/               # Differential testing vs cmark-gfm CLI
```

## Key Design Decisions

- **Pure SPM**: No Xcode project needed — builds with just Command Line Tools
- **Standalone test runner**: Custom `TestRunner` struct avoids XCTest dependency
- **cmark-gfm via Apple's swift-cmark**: Guaranteed GFM fidelity
- **JS injection for updates**: Replaces innerHTML instead of page reload, preserving scroll
- **Golden file testing**: Exact HTML diff catches renderer regressions
- **Plugin architecture**: `LanguagePlugin` protocol for extensibility (CSV, HTML, etc.)
- **HTML sanitizer**: Strips scripts, event handlers, javascript: URIs for safe preview

## Usage Methods

| Method | Status | How |
|--------|--------|-----|
| **CLI** (`md`, `mdpreview`) | Works | `scripts/install-cli.sh` symlinks binary to `~/.local/bin/` |
| **Open With** (Finder) | Works | `scripts/bundle.sh --install` registers .app with Launch Services |
| **Quick Look** (space bar) | Not yet | Requires `.appex` target (needs Xcode project, not feasible with pure SPM) |

### Quick Look — Future Enhancement

Quick Look extensions (`.appex`) require an Xcode project with a specific target type. Since MarkView is pure SPM (builds with Command Line Tools only), implementing a Quick Look extension would require either:
1. Adding an `.xcodeproj` alongside the SPM package
2. Using a separate Xcode-based project that embeds the MarkViewCore library
3. Waiting for SPM to support appex targets

This is deferred until one of these approaches becomes practical.

## Test Tiers

| Tier | What |
|------|------|
| 0 | Build succeeds |
| 1 | Renderer unit tests, GFM extensions, FileWatcher, word count, metrics, settings, linter, suggestions, plugins |
| 2 | Fixture-based GFM compliance, performance benchmarks, stress tests |
| 3 | Golden file regression, full-template E2E, determinism, structural validation, performance gates |
| Extended | Fuzz testing (10K+ random inputs), differential testing vs cmark-gfm CLI |
