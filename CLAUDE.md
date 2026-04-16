# MarkView — AI Development Guide

## Quick Reference
- **Build**: `swift build`
- **Test**: `swift run MarkViewTestRunner` (294 Swift tests + 91 MCP tests)
- **Playwright e2e**: `make playwright` (66 tests — builds fixture binary, runs Playwright, installs MarkView.app)
- **Verify all**: `bash verify.sh`
- **App bundle**: `bash scripts/bundle.sh --install`
- **MCP tests**: `bash scripts/test-mcp.sh`
- **PHK debug logging**: `PHK_DEBUG=1 swift run MarkViewTestRunner` (verbose HTML pipeline output)

## Architecture

**Hybrid SPM + Xcode (XcodeGen)** — `.xcodeproj` is gitignored, regenerate with `xcodegen generate`.

| Target | Type | Purpose |
|--------|------|---------|
| `MarkViewCore` | SPM library | Rendering, file watching, linting — no UI deps |
| `MarkView` | Xcode app | SwiftUI app with WKWebView preview |
| `MarkViewQuickLook` | Xcode extension | Quick Look preview provider |
| `MarkViewMCPServer` | SPM executable | MCP server for AI tool integration |
| `MarkViewTestRunner` | SPM executable | Full test suite (no XCTest dependency) |
| `MarkViewHTMLGen` | SPM executable | CLI fixture generator for Playwright tests |

**Key files:**
- `Sources/MarkViewCore/MarkdownRenderer.swift` — core GFM rendering via swift-cmark
- `Sources/MarkViewCore/HTMLPipeline.swift` — full injection pipeline (Prism → Mermaid → KaTeX → controls)
- `Sources/MarkViewCore/template.html` — preview HTML template with Prism.js
- `Sources/MarkViewMCPServer/main.swift` — MCP server (tools: `preview_markdown`, `open_file`)
- `Sources/MarkViewHTMLGen/main.swift` — Playwright fixture generator (used by `make playwright`)
- `Sources/MarkViewApp/` — SwiftUI views
- `project.yml` — XcodeGen config (source of truth for Xcode targets)
- `tests/` — Playwright e2e test suite (Node.js, Chromium)

## MCP Tools (for AI integration)

The `MarkViewMCPServer` exposes two tools:

**`preview_markdown`** — render markdown content in MarkView:
```json
{ "content": "# Hello\nThis is **markdown**" }
```
Writes to a temp file and opens in MarkView with live reload.

**`open_file`** — open an existing markdown file:
```json
{ "path": "/path/to/file.md" }
```
Opens the file in MarkView. File must exist and have a markdown extension.

**How to use from Claude Code:**
- Call `open_file` directly from the main conversation (not from subagents — MCP tools require main context)
- Fallback: `open -a MarkView /path/to/file.md` via Bash

## Safety Rules
- Run `swift package resolve` after changing `Package.swift`
- Run `xcodegen generate` after changing `project.yml`
- Run `swift run MarkViewTestRunner` after changing `MarkdownRenderer.swift` or `template.html`
- Run `make playwright` (not `--no-build`) after any `HTMLPipeline.swift` or `template.html` change
- Run `bash scripts/bundle.sh --install && qlmanage -r` after any app change

## Testing
```bash
swift run MarkViewTestRunner          # Unit + integration (294 tests)
swift run MarkViewFuzzTester          # 10K random inputs
swift run MarkViewDiffTester          # Compare vs cmark-gfm CLI
swift run MarkViewE2ETester           # UI tests (requires .app + AX permissions)
bash scripts/test-mcp.sh              # MCP protocol tests (91 tests — 9 tools)
make playwright                       # Playwright e2e DOM tests (66 tests) — rebuilds MarkViewHTMLGen, runs Chromium
```

> **Playwright fixture gotcha**: `gen-playwright-fixtures.sh --no-build` uses the last built release binary.
> Always run `make playwright` (full build) after any `HTMLPipeline.swift` or `template.html` change.
> The `--no-build` flag is only safe when you haven't touched the rendering pipeline.

## Common Tasks

**Add a new rendering feature:**
1. Modify `MarkdownRenderer.swift`
2. Add test fixtures in `Tests/TestRunner/Fixtures/`
3. Run `swift run MarkViewTestRunner`

**Add a new MCP tool:**
1. Add tool definition in `main.swift` `tools` array
2. Add handler function
3. Add test in `scripts/test-mcp.sh`

**Change the preview template:**
1. Modify `Sources/MarkViewCore/template.html`
2. Run full test suite — template changes affect rendering tests

**Run Playwright e2e tests:**
1. `make playwright` — builds MarkViewHTMLGen, generates fixtures, runs 66 Playwright tests, installs MarkView.app
2. Tests live in `tests/` (Node.js/Playwright, Chromium)
3. After any `HTMLPipeline.swift` change, always use `make playwright` not `--no-build`

**Run adoption metrics:**
1. `bash scripts/metrics.sh` — fetches npm download stats for `mcp-server-markview`
2. The npm package name is `mcp-server-markview` (NOT `markview-mcp`, `markview`, or `mcp-server-markview-mcp`). Never curl the npm registry with a guessed name — always run the script.

**Debug HTML pipeline issues:**
1. Set `PHK_DEBUG=1` before any swift run command for verbose injection logs
2. Use `swift run MarkViewHTMLGen --input file.md --output out.html` to inspect full pipeline output
