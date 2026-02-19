# mcp-server-markview

MCP (Model Context Protocol) server for [MarkView](https://github.com/paulhkang94/markview) — a native macOS Markdown previewer.

Lets AI assistants (Claude, etc.) preview Markdown files and open them in the MarkView app directly from the conversation.

## Requirements

- macOS (arm64 or x86_64)
- Node.js 18+
- MarkView.app (auto-fetched on install, or install manually from [Releases](https://github.com/paulhkang94/markview/releases))

## Quick Start

Run without installing:

```bash
npx mcp-server-markview
```

Or install globally:

```bash
npm install -g mcp-server-markview
mcp-server-markview
```

The binary is downloaded automatically during installation. If the download fails (e.g. offline install), the wrapper falls back to a locally installed MarkView.app at `/Applications` or `~/Applications`.

## Claude Code Configuration

Add to your Claude Code MCP config (usually `~/.claude/mcp.json` or via `claude mcp add`):

```json
{
  "mcpServers": {
    "markview": {
      "command": "npx",
      "args": ["-y", "mcp-server-markview"]
    }
  }
}
```

Or if you have installed it globally:

```json
{
  "mcpServers": {
    "markview": {
      "command": "mcp-server-markview"
    }
  }
}
```

### Using `claude mcp add`

```bash
claude mcp add markview -- npx -y mcp-server-markview
```

## Available Tools

### `preview_markdown`

Renders a Markdown string and opens a live preview in MarkView.

| Parameter | Type   | Description                     |
|-----------|--------|---------------------------------|
| `content` | string | Markdown source text to preview |
| `title`   | string | Optional window title           |

### `open_file`

Opens a Markdown file from disk in MarkView.

| Parameter | Type   | Description                          |
|-----------|--------|--------------------------------------|
| `path`    | string | Absolute path to the `.md` file      |

## Transport

The server uses **stdio transport** (JSON-RPC 2.0 over stdin/stdout), which is the standard MCP transport and compatible with all MCP clients.

## How It Works

1. `npm install` runs `scripts/postinstall.js`, which downloads the prebuilt `MarkView` release archive from GitHub and extracts the `markview-mcp-server` binary.
2. The binary is placed at `bin/markview-mcp-server-binary` inside the package.
3. `bin/mcp-server-markview` (the shell wrapper registered in `bin`) locates the binary and `exec`s it, preserving stdio.

## Troubleshooting

**Binary not found after install**

Re-run the postinstall script manually:

```bash
node "$(npm root -g)/mcp-server-markview/scripts/postinstall.js"
```

**Download failed (corporate proxy / offline)**

Install MarkView.app manually from the [Releases page](https://github.com/paulhkang94/markview/releases) and place it in `/Applications`. The wrapper will find it automatically.

**Permission denied**

```bash
chmod +x "$(npm root -g)/mcp-server-markview/bin/markview-mcp-server-binary"
chmod +x "$(npm root -g)/mcp-server-markview/bin/mcp-server-markview"
```

## License

MIT — see [LICENSE](https://github.com/paulhkang94/markview/blob/main/LICENSE).
