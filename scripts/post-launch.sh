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
Show HN: MarkView – native macOS markdown preview + MCP server for Claude Code
EOF
HN_TITLE="${HN_TITLE%$'\n'}"

read -r -d '' HN_BODY <<'EOF' || true
I use Claude Code heavily for writing docs, READMEs, and architecture notes. The
feedback loop was broken: Claude would generate markdown, I'd have to open a
browser or VS Code to see it rendered. I built MarkView to close that loop.

MarkView is a native Swift/SwiftUI markdown previewer with an MCP server. Add it
to Claude Code in one line:

  claude mcp add markview --transport stdio -- npx -y mcp-server-markview

After that, when Claude generates a doc or diagram, it can call open_file and
you see it rendered in a native macOS window — no browser, no web server, no
context switch. Edit the file and the preview updates instantly via DispatchSource
file watching.

What I haven't seen anywhere else: every other macOS markdown tool (Marked 2,
MarkEdit, MacDown, Typora) has no AI integration path at all. The MCP server
angle genuinely seems unoccupied.

Other things it does:
- Quick Look extension — spacebar previews .md files in Finder without opening
  the app
- Mermaid diagram rendering (flowchart, sequence, Gantt, ER)
- Syntax highlighting for 20+ languages via Prism.js
- Markdown linting with 9 built-in rules + format-on-save
- Split-pane editor with CADisplayLink 60Hz scroll sync
- 403 tests including 10K fuzz runs and differential testing vs cmark-gfm

MIT licensed, ~750 npm downloads so far.

GitHub: https://github.com/paulhkang94/markview
EOF

read -r -d '' REDDIT_CLAUDEAI_TITLE <<'EOF' || true
Built a native MCP server so Claude Code can open live markdown previews while it writes — no browser, no Electron
EOF
REDDIT_CLAUDEAI_TITLE="${REDDIT_CLAUDEAI_TITLE%$'\n'}"

read -r -d '' REDDIT_CLAUDEAI_BODY <<'EOF' || true
When I'm using Claude Code to write docs or architecture notes, the feedback loop
was always broken. Claude generates the markdown, I context-switch to a browser or
VS Code to see it rendered. Built MarkView to fix that.

**One-line setup:**
```
claude mcp add markview --transport stdio -- npx -y mcp-server-markview
```

After that, Claude can call `open_file` to pop a native macOS preview window for
any markdown file it's editing. The window live-reloads on every save via
kernel-level file watching (DispatchSource, not polling).

**The thing I noticed while building this:** Marked 2, MarkEdit, Typora, MacDown
— none of them have any MCP integration. If you're writing docs with Claude Code,
there's genuinely nothing else in this category.

**What else it does:**
- Quick Look extension — spacebar in Finder previews .md without launching the app
- Mermaid diagrams (flowchart, sequence, Gantt, ER)
- 20+ language syntax highlighting
- Markdown linting + format-on-save

MIT, ~750 npm downloads. https://github.com/paulhkang94/markview

What's your current markdown preview setup with Claude Code?
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
