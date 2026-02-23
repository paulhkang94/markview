# MarkView — Development Guide

## Setup (first time / after clone)
```bash
brew install xcodegen                # One-time: install XcodeGen
xcodegen generate                    # Generate MarkView.xcodeproj from project.yml
```

## Build & Test
```bash
swift build                          # Build SPM targets (MarkViewCore, MCP, testers)
swift run MarkViewTestRunner         # Run full test suite (276 tests)
xcodebuild -scheme MarkView build    # Build app + Quick Look extension (Xcode targets)
```

## Extended Testing
```bash
swift run MarkViewFuzzTester         # Fuzz test (10K random inputs)
swift run MarkViewDiffTester         # Differential test vs cmark-gfm CLI
swift run MarkViewE2ETester          # E2E UI tests (needs .app bundle + AX permissions)
bash scripts/test-mcp.sh             # MCP server tests (29 protocol + integration tests)
```

## Verify
```bash
bash verify.sh              # Full verification (build + all tests)
bash verify.sh 0            # Build only
bash verify.sh --extended   # Full + fuzz + differential tests
```

## App Bundle
```bash
bash scripts/bundle.sh             # Build .app bundle (uses xcodebuild)
bash scripts/bundle.sh --install   # Build + install to /Applications
bash scripts/install-cli.sh        # Install md/mdpreview CLI commands
```

## Claude Code Integration — MCP Tools

The MarkViewMCPServer exposes two tools. Use them proactively whenever generating markdown that a user should SEE:

**`preview_markdown`** — renders inline markdown content in MarkView (opens a live window):
- Use when: generating a dashboard, report, or summary the user should read visually
- Never write a text command — call the tool directly
- Example use cases: `flow dashboard-md` output, research summaries, architecture docs

**`open_file`** — opens an existing .md file path in MarkView:
- Use when: a file was just written to disk (e.g. `flow dashboard-md` writes `~/.flow/dashboard.md`)
- After writing a markdown file the user should see, IMMEDIATELY call `open_file` with the path
- Do NOT ask the user to find or open the file themselves

**Fallback (if MCP unavailable):**
```bash
open -a MarkView /path/to/file.md
```

**Anti-pattern (never do this):**
- Writing "**markview** open_file path" as text — this does nothing
- Asking the user to "pass the path to MarkView" — do it yourself
- Using a subagent to call MarkView — MCP tools only work from main context

## Doc Placement
- `docs/research/` is for **MarkView-specific** research only (rendering, QuickLook, testing approaches, etc.)
- General research (MCP analysis, strategy, cross-project tooling) goes to `~/repos/docs/research/`
- When launching subagents that produce research docs, specify the full absolute path for the output file

## Safety Guards
- Do NOT modify Package.swift without running `swift package resolve` after
- Do NOT modify project.yml without running `xcodegen generate` after
- Do NOT modify MarkdownRenderer.swift without running `swift run MarkViewTestRunner` after
- Do NOT modify template.html without running tests after
- After any code change, run `swift build` before committing
- After every push, rebuild and install the app: `bash scripts/bundle.sh --install && qlmanage -r`

## Architecture

### Hybrid SPM + Xcode (via XcodeGen)
- **SPM targets** (in `Package.swift`): MarkViewCore, MarkViewMCPServer, test runners
- **Xcode targets** (in `project.yml` → XcodeGen): MarkView app, MarkViewQuickLook extension
- `.xcodeproj` is gitignored — regenerate with `xcodegen generate`

### Targets
- **MarkViewCore** (SPM library): MarkdownRenderer + FileWatcher + Linter + Suggestions + Plugins — no UI deps, fully testable
- **MarkView** (Xcode app): SwiftUI app — ContentView, WebPreviewView, PreviewViewModel, Settings (17 settings)
- **MarkViewQuickLook** (Xcode app extension): Quick Look preview using QLPreviewingController + NSAttributedString(html:) — full-panel, scrollable, no WKWebView
- **MarkViewTestRunner** (SPM executable): Standalone test suite — no XCTest/Testing framework needed
- **MarkViewFuzzTester** (SPM executable): Random input crash testing
- **MarkViewDiffTester** (SPM executable): Differential testing vs cmark-gfm CLI
- **MarkViewE2ETester** (SPM executable): E2E UI tests — launches .app, interacts via AXUIElement APIs (30 tests)
- **MarkViewMCPServer** (SPM executable): MCP server for AI tool integration (preview_markdown, open_file)

### Key Technologies
- **cmark-gfm** via Apple's swift-cmark for GFM rendering
- **WKWebView** for HTML preview with Prism.js syntax highlighting (18 languages)
- **DispatchSource** for file watching (handles atomic saves from VS Code, Vim, etc.)
- **LanguagePlugin** protocol: extensible rendering for CSV, HTML, and future formats
- **HTMLSanitizer**: XSS prevention (strips scripts, event handlers, javascript: URIs)
- Test fixtures in Tests/TestRunner/Fixtures/ with .md, .html, .csv files
