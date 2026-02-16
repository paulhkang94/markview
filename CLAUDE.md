# MarkView — Development Guide

## Build & Test
```bash
swift build                        # Build all targets
swift run MarkViewTestRunner       # Run full test suite (36 tests)
swift run MarkView                 # Launch app
swift run MarkView /path/to/file.md  # Launch with specific file
```

## Verify
```bash
bash verify.sh          # Full verification (build + all tests)
bash verify.sh 0        # Build only
```

## Safety Guards
- Do NOT modify Package.swift without running `swift package resolve` after
- Do NOT modify MarkdownRenderer.swift without running `swift run MarkViewTestRunner` after
- Do NOT modify template.html without running tests after
- After any code change, run `swift build` before committing

## Architecture
- **MarkViewCore** (library): MarkdownRenderer + FileWatcher — no UI deps, fully testable
- **MarkView** (executable): SwiftUI app — ContentView, WebPreviewView, PreviewViewModel
- **MarkViewTestRunner** (executable): Standalone test suite — no XCTest/Testing framework needed
- **cmark-gfm** via Apple's swift-cmark for GFM rendering
- **WKWebView** for HTML preview
- **DispatchSource** for file watching (handles atomic saves from VS Code, Vim, etc.)
- Test fixtures in Tests/TestRunner/Fixtures/ with .md files for compliance testing
