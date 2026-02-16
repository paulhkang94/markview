# MarkView — Development Guide

## Build & Test
```bash
swift build                        # Build all targets
swift run MarkViewTestRunner       # Run full test suite (133 tests)
swift run MarkView                 # Launch app
swift run MarkView /path/to/file.md  # Launch with specific file
```

## Extended Testing
```bash
swift run MarkViewFuzzTester       # Fuzz test (10K random inputs)
swift run MarkViewDiffTester       # Differential test vs cmark-gfm CLI
```

## Verify
```bash
bash verify.sh              # Full verification (build + all tests)
bash verify.sh 0            # Build only
bash verify.sh --extended   # Full + fuzz + differential tests
```

## App Bundle
```bash
bash scripts/bundle.sh             # Build .app bundle
bash scripts/bundle.sh --install   # Build + install to /Applications
bash scripts/install-cli.sh        # Install md/mdpreview CLI commands
```

## Safety Guards
- Do NOT modify Package.swift without running `swift package resolve` after
- Do NOT modify MarkdownRenderer.swift without running `swift run MarkViewTestRunner` after
- Do NOT modify template.html without running tests after
- After any code change, run `swift build` before committing

## Architecture
- **MarkViewCore** (library): MarkdownRenderer + FileWatcher + Linter + Suggestions + Plugins — no UI deps, fully testable
- **MarkView** (executable): SwiftUI app — ContentView, WebPreviewView, PreviewViewModel, Settings (17 settings)
- **MarkViewTestRunner** (executable): Standalone test suite — no XCTest/Testing framework needed
- **MarkViewFuzzTester** (executable): Random input crash testing
- **MarkViewDiffTester** (executable): Differential testing vs cmark-gfm CLI
- **cmark-gfm** via Apple's swift-cmark for GFM rendering
- **WKWebView** for HTML preview with Prism.js syntax highlighting (18 languages)
- **DispatchSource** for file watching (handles atomic saves from VS Code, Vim, etc.)
- **LanguagePlugin** protocol: extensible rendering for CSV, HTML, and future formats
- **HTMLSanitizer**: XSS prevention (strips scripts, event handlers, javascript: URIs)
- Test fixtures in Tests/TestRunner/Fixtures/ with .md, .html, .csv files
