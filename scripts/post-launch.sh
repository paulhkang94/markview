#!/usr/bin/env bash
# post-launch.sh — MarkView launch post helper
#
# Usage:
#   ./scripts/post-launch.sh           # display posts + open browser tabs
#   ./scripts/post-launch.sh --dry-run # display posts + print URLs only

set -euo pipefail

DRY_RUN=false
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

# ─── POST CONTENT ──────────────────────────────────────────────────────────────

read -r -d '' HN_TITLE <<'EOF' || true
Show HN: MarkView – native macOS markdown preview with MCP server (Swift, no Electron)
EOF
HN_TITLE="${HN_TITLE%$'\n'}"

read -r -d '' HN_BODY <<'EOF' || true
I built MarkView because every markdown preview tool I tried was either Electron
(heavy, slow) or a web server (friction to launch). MarkView is a native Swift/
SwiftUI app — instant launch, zero runtime dependencies, Quick Look integration
out of the box.

The part I'm most excited about: it ships an MCP server, so Claude Code can
render markdown in a native macOS window while it edits your files. When Claude
generates a Mermaid diagram or a structured doc, you see it live without leaving
your terminal workflow.

One-line install:
  claude mcp add markview --transport stdio -- npx -y mcp-server-markview

Features:
- GitHub Flavored Markdown with Mermaid diagram rendering
- Syntax highlighting for 20+ languages
- Live file watching (edits reflect instantly)
- Split-pane editor with bidirectional scroll sync
- Quick Look plugin — preview .md files in Finder with spacebar
- Zero config, no web server, no Electron

It's MIT licensed. The npm package (mcp-server-markview) has ~750 downloads.
Happy to answer questions on the MCP integration or the Swift rendering approach.

GitHub: https://github.com/paulhkang94/markview
EOF

read -r -d '' REDDIT_CLAUDEAI_TITLE <<'EOF' || true
I built a native macOS MCP server so Claude Code can render markdown in a real window while it writes
EOF
REDDIT_CLAUDEAI_TITLE="${REDDIT_CLAUDEAI_TITLE%$'\n'}"

read -r -d '' REDDIT_CLAUDEAI_BODY <<'EOF' || true
Every markdown preview option for Claude Code was either browser-based or Electron.
I wanted something that felt native, so I built MarkView — a Swift/SwiftUI app
with an MCP server that lets Claude open a preview window directly.

**What it actually enables:**

When Claude Code generates a Mermaid diagram, a structured README, or a doc with
tables — you get a live rendered preview in a native macOS window without switching
apps or running a separate server. Edit the file, the window updates instantly.

**Install (one line):**
```
claude mcp add markview --transport stdio -- npx -y mcp-server-markview
```

After that, Claude Code can call `open_preview` to pop open a native window for
any markdown file.

**Why native matters:**
- Instant launch, no warm-up
- Quick Look integration (spacebar preview in Finder)
- No web server running in the background
- Split-pane editor with bidirectional scroll sync
- Mermaid + syntax highlighting (20+ languages)

It's MIT, ~750 npm downloads so far. GitHub: https://github.com/paulhkang94/markview

Curious whether others have set up similar preview workflows with Claude Code —
what's your current setup?
EOF

read -r -d '' REDDIT_CURSOR_TITLE <<'EOF' || true
Built a native macOS MCP server for markdown preview — no Electron, works with Cursor
EOF
REDDIT_CURSOR_TITLE="${REDDIT_CURSOR_TITLE%$'\n'}"

read -r -d '' REDDIT_CURSOR_BODY <<'EOF' || true
MarkView is a Swift/SwiftUI markdown preview app with an MCP server. If you're
using Cursor with MCP, you can add it and get a native macOS preview window that
updates live as Cursor edits your files.

**Add to Cursor's MCP config:**
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

Renders GFM, Mermaid diagrams, and syntax highlighting for 20+ languages. Native
Swift — no Electron, no web server. Quick Look plugin included.

MIT licensed. https://github.com/paulhkang94/markview
EOF

read -r -d '' REDDIT_MACAPPS_TITLE <<'EOF' || true
MarkView – native Swift markdown preview for macOS with Quick Look and MCP server
EOF
REDDIT_MACAPPS_TITLE="${REDDIT_MACAPPS_TITLE%$'\n'}"

read -r -d '' REDDIT_MACAPPS_BODY <<'EOF' || true
Built a native Swift/SwiftUI markdown previewer because I was tired of Electron-
based alternatives. MarkView launches instantly, integrates with Quick Look
(spacebar in Finder), and has no background server to manage.

**Features:**
- GitHub Flavored Markdown
- Mermaid diagram rendering
- Syntax highlighting (20+ languages)
- Live file watching with split-pane editor
- Bidirectional scroll sync
- Quick Look plugin for Finder

It also ships an MCP server for Claude Code / Cursor integration, so AI tools
can open preview windows natively.

MIT, free. https://github.com/paulhkang94/markview — would love feedback on the
Quick Look plugin in particular, that part was surprisingly tricky.
EOF

# ─── DISPLAY ──────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  HACKER NEWS — Show HN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "TITLE: ${HN_TITLE}"
echo ""
echo "BODY:"
echo "${HN_BODY}"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  REDDIT — r/ClaudeAI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "TITLE: ${REDDIT_CLAUDEAI_TITLE}"
echo ""
echo "BODY:"
echo "${REDDIT_CLAUDEAI_BODY}"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  REDDIT — r/cursor"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "TITLE: ${REDDIT_CURSOR_TITLE}"
echo ""
echo "BODY:"
echo "${REDDIT_CURSOR_BODY}"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  REDDIT — r/macapps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "TITLE: ${REDDIT_MACAPPS_TITLE}"
echo ""
echo "BODY:"
echo "${REDDIT_MACAPPS_BODY}"
echo ""

# ─── URLs ─────────────────────────────────────────────────────────────────────

# URL-encode title strings (Python available on all macOS)
url_encode() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
}

HN_TITLE_ENC=$(url_encode "${HN_TITLE}")
CLAUDEAI_TITLE_ENC=$(url_encode "${REDDIT_CLAUDEAI_TITLE}")
CURSOR_TITLE_ENC=$(url_encode "${REDDIT_CURSOR_TITLE}")
MACAPPS_TITLE_ENC=$(url_encode "${REDDIT_MACAPPS_TITLE}")
REPO_ENC=$(url_encode "https://github.com/paulhkang94/markview")

HN_URL="https://news.ycombinator.com/submitlink?u=${REPO_ENC}&t=${HN_TITLE_ENC}"
CLAUDEAI_URL="https://www.reddit.com/r/ClaudeAI/submit?title=${CLAUDEAI_TITLE_ENC}"
CURSOR_URL="https://www.reddit.com/r/cursor/submit?title=${CURSOR_TITLE_ENC}"
MACAPPS_URL="https://www.reddit.com/r/macapps/submit?title=${MACAPPS_TITLE_ENC}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SUBMISSION URLS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "HN:         ${HN_URL}"
echo "r/ClaudeAI: ${CLAUDEAI_URL}"
echo "r/cursor:   ${CURSOR_URL}"
echo "r/macapps:  ${MACAPPS_URL}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo "🔎  Dry run — URLs printed above, no browser tabs opened."
else
  open "${HN_URL}"
  open "${CLAUDEAI_URL}"
  open "${CURSOR_URL}"
  open "${MACAPPS_URL}"
  echo "Posts drafted — browser tabs opening. Best window: Tue–Thu 8–10am ET"
fi

echo ""
