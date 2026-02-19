# MarkView MCP Integration Guide (Template)

Shared setup guide for integrating MarkView markdown previewer with Claude Code via MCP (Model Context Protocol). MarkView is a native macOS markdown preview app with live editing, file watching, and built-in AI tool support.

## Quick Start

MarkView works immediately for local markdown file preview:

```bash
# Install
brew install --cask paulhkang94/markview/markview

# Use
mdpreview README.md          # Open a markdown file
mdpreview                    # Open empty editor
open -a MarkView docs/*.md   # Open multiple files
```

No additional configuration needed. The app auto-watches files for changes from any editor (VS Code, Vim, Neovim, etc.).

## MCP Server Setup (AI Integration)

To enable Claude Code to directly preview and manipulate markdown through MarkView:

**1. Add MarkView MCP to your config:**

Global setup (affects all projects) — add to `~/.claude/mcp.json`:
```json
{
  "mcpServers": {
    "markview": {
      "command": "/Applications/MarkView.app/Contents/MacOS/markview-mcp-server"
    }
  }
}
```

Or project-level setup (affects only current repo) — add to `.claude/mcp.json`:
```json
{
  "mcpServers": {
    "markview": {
      "command": "/Applications/MarkView.app/Contents/MacOS/markview-mcp-server"
    }
  }
}
```

If you already have an `mcp.json` with other servers, merge the `markview` key into the existing `mcpServers` object.

**2. Verify installation:**

Test that the MCP server binary exists:
```bash
/Applications/MarkView.app/Contents/MacOS/markview-mcp-server --version
```

After restarting Claude Code, you should see two new tools in conversations:
- `preview_markdown` — Write temporary markdown and open in MarkView
- `open_file` — Open an existing `.md` file in MarkView

## Available Tools

### `preview_markdown(content: string)`

Create a temporary markdown file and open it in MarkView for preview. Useful for:
- Drafting documentation before committing
- Visualizing generated markdown (from agents or transforms)
- Previewing formatted output
- Testing markdown rendering (GitHub Flavored Markdown, syntax highlighting, etc.)

Example:
```
Claude: I'll draft the API documentation and preview it in MarkView.

User prompt → Claude generates markdown → preview_markdown() → Opens in MarkView
```

### `open_file(path: string)`

Open an existing markdown file in MarkView. Useful for:
- Reviewing docs during development
- Checking structure before major edits
- Live preview while editing in editor (file watching)

Example:
```
# While editing docs/API.md in VS Code, keep a MarkView window open
open_file("docs/API.md")  # MarkView auto-refreshes as you save
```

## MarkView Features (for Reference)

- **Live preview** — Editor + preview split-pane (15 configurable width options)
- **File watching** — Auto-refreshes when files change from external editors
- **GitHub Flavored Markdown** — Tables, strikethrough, autolinks, task lists via swift-cmark
- **Syntax highlighting** — 18 languages via Prism.js
- **Markdown linting** — 9 built-in rules with real-time diagnostics
- **Dark mode** — System/light/dark theme support
- **Export** — HTML and PDF export
- **Multi-format** — CSV and HTML preview via plugin architecture
- **HTML sanitizer** — XSS prevention (strips scripts, event handlers, javascript: URIs)

## Limitations & Workarounds

| Limitation | Workaround |
|-----------|-----------|
| MCP server requires MarkView.app (macOS only) | Use on macOS; for cross-platform, fall back to VS Code preview |
| Temp files not persisted | If you need to keep the draft, save manually or use `preview_markdown()` result as file content |
| No auto-scroll sync to editor | Open file in editor + MarkView side-by-side instead |
| Single-threaded MCP process | Avoid 100KB+ previews; clip to <50KB for responsive feedback |

## Why MarkView for AI Workflows

- **Native macOS performance** — No Electron overhead, fast rendering via WKWebView
- **Purpose-built** — Made for markdown workflows, not a generic browser
- **File watching** — Works seamlessly with any editor (VS Code, Vim, etc.)
- **AI-native** — MCP server designed for AI assistants, not bolt-on integration
- **Open source** — Full source on GitHub, MIT licensed

## Comparison to Other Options

| Tool | Strengths | Weaknesses | AI Integration |
|------|-----------|-----------|-----------------|
| **MarkView** | Native, fast, file watching, MCP built-in | macOS only | ✓ MCP server included |
| **VS Code Preview** | Ubiquitous, works everywhere | Electron overhead, requires extension config | ✓ via markdown-it extension |
| **Quick Look** | System built-in, instant | Limited formatting, not live-editable | ✗ None |
| **Typora** | Live editing, beautiful | Commercial, closed-source, no MCP | ✗ None |
| **Obsidian** | Powerful for wikis, vault-aware | Overkill for single-file preview, no MCP | ✗ None |

## Installation Troubleshooting

**MCP server not found:**
```bash
# Verify MarkView is installed in /Applications
ls -la /Applications/MarkView.app

# Check if MCP binary exists
ls -la /Applications/MarkView.app/Contents/MacOS/markview-mcp-server

# If missing, rebuild and reinstall
brew reinstall --cask paulhkang94/markview/markview
```

**MCP server fails to start:**
```bash
# Run directly to see error output
/Applications/MarkView.app/Contents/MacOS/markview-mcp-server --help

# Check Claude Code logs
claude config logs
```

**File not opening in MarkView:**
```bash
# Verify MarkView is the default handler for .md files
duti -s dev.paulkang.markview com.apple.web.markdown owner

# Or manually set via Finder:
# Right-click .md file → Open With → MarkView → Change All
```

## Next Steps

1. Install MarkView: `brew install --cask paulhkang94/markview/markview`
2. Add MCP config to `~/.claude/mcp.json` or `.claude/mcp.json`
3. Restart Claude Code
4. Try: "Preview this documentation in MarkView" → Claude will use `preview_markdown()` automatically
