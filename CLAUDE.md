# MarkView — AI Development Guide

## Quick Reference
- **Build**: `swift build`
- **Test**: `swift run MarkViewTestRunner` (276 tests)
- **Verify all**: `bash verify.sh`
- **App bundle**: `bash scripts/bundle.sh --install`
- **MCP tests**: `bash scripts/test-mcp.sh`

## Architecture

**Hybrid SPM + Xcode (XcodeGen)** — `.xcodeproj` is gitignored, regenerate with `xcodegen generate`.

| Target | Type | Purpose |
|--------|------|---------|
| `MarkViewCore` | SPM library | Rendering, file watching, linting — no UI deps |
| `MarkView` | Xcode app | SwiftUI app with WKWebView preview |
| `MarkViewQuickLook` | Xcode extension | Quick Look preview provider |
| `MarkViewMCPServer` | SPM executable | MCP server for AI tool integration |
| `MarkViewTestRunner` | SPM executable | Full test suite (no XCTest dependency) |

**Key files:**
- `Sources/MarkViewCore/MarkdownRenderer.swift` — core GFM rendering via swift-cmark
- `Sources/MarkViewCore/template.html` — preview HTML template with Prism.js
- `Sources/MarkViewMCPServer/main.swift` — MCP server (tools: `preview_markdown`, `open_file`)
- `Sources/MarkViewApp/` — SwiftUI views
- `project.yml` — XcodeGen config (source of truth for Xcode targets)

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
- Run `bash scripts/bundle.sh --install && qlmanage -r` after any app change

## Testing
```bash
swift run MarkViewTestRunner          # Unit + integration (276 tests)
swift run MarkViewFuzzTester          # 10K random inputs
swift run MarkViewDiffTester          # Compare vs cmark-gfm CLI
swift run MarkViewE2ETester           # UI tests (requires .app + AX permissions)
bash scripts/test-mcp.sh              # MCP protocol tests (29 tests)
```

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
