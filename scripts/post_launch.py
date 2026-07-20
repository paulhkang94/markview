#!/usr/bin/env python3
"""
post_launch.py — MarkView launch post helper.

Prints ready-to-copy launch post copy (Hacker News + Reddit) and opens
prefilled submission URLs in the browser.

Usage:
    python3 scripts/post_launch.py             # display posts + open browser tabs
    python3 scripts/post_launch.py --dry-run   # display posts + print URLs only
    bash scripts/post-launch.sh                # thin wrapper
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import urllib.parse
from dataclasses import dataclass

REPO_URL = "https://github.com/paulhkang94/markview"

HN_TITLE = (
    "Show HN: MarkView – native macOS markdown preview + MCP server for Claude Code"
)
HN_BODY = """\
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

GitHub: https://github.com/paulhkang94/markview"""

REDDIT_CLAUDEAI_TITLE = (
    "Built a native MCP server so Claude Code can open live markdown previews "
    "while it writes — no browser, no Electron"
)
REDDIT_CLAUDEAI_BODY = """\
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

What's your current markdown preview setup with Claude Code?"""

REDDIT_CURSOR_TITLE = "Built a native macOS MCP server for markdown preview — no Electron, works with Cursor"
REDDIT_CURSOR_BODY = """\
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

MIT licensed. https://github.com/paulhkang94/markview"""

REDDIT_MACAPPS_TITLE = (
    "MarkView – native Swift markdown preview for macOS with Quick Look and MCP server"
)
REDDIT_MACAPPS_BODY = """\
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
Quick Look plugin in particular, that part was surprisingly tricky."""


@dataclass(frozen=True)
class Post:
    section: str
    title: str
    body: str
    url_template: str  # {title} placeholder for the url-encoded title


POSTS: tuple[Post, ...] = (
    Post(
        "HACKER NEWS — Show HN",
        HN_TITLE,
        HN_BODY,
        "https://news.ycombinator.com/submitlink?u={repo}&t={title}",
    ),
    Post(
        "REDDIT — r/ClaudeAI",
        REDDIT_CLAUDEAI_TITLE,
        REDDIT_CLAUDEAI_BODY,
        "https://www.reddit.com/r/ClaudeAI/submit?title={title}",
    ),
    Post(
        "REDDIT — r/cursor",
        REDDIT_CURSOR_TITLE,
        REDDIT_CURSOR_BODY,
        "https://www.reddit.com/r/cursor/submit?title={title}",
    ),
    Post(
        "REDDIT — r/macapps",
        REDDIT_MACAPPS_TITLE,
        REDDIT_MACAPPS_BODY,
        "https://www.reddit.com/r/macapps/submit?title={title}",
    ),
)


def url_encode(text: str) -> str:
    return urllib.parse.quote(text)


def build_url(post: Post) -> str:
    return post.url_template.format(
        repo=url_encode(REPO_URL), title=url_encode(post.title)
    )


def build_urls(posts: tuple[Post, ...] = POSTS) -> dict[str, str]:
    return {post.section: build_url(post) for post in posts}


SEPARATOR = "━" * 74


def print_report(posts: tuple[Post, ...] = POSTS) -> None:
    for post in posts:
        print()
        print(SEPARATOR)
        print(f"  {post.section}")
        print(SEPARATOR)
        print()
        print(f"TITLE: {post.title}")
        print()
        print("BODY:")
        print(post.body)
        print()

    urls = build_urls(posts)
    print(SEPARATOR)
    print("  SUBMISSION URLS")
    print(SEPARATOR)
    print()
    for post in posts:
        print(f"{post.section}: {urls[post.section]}")
    print()


def open_urls(urls: dict[str, str]) -> None:
    for url in urls.values():
        subprocess.run(["open", url])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print URLs only, don't open browser tabs",
    )
    args = parser.parse_args(argv)

    print_report()

    if args.dry_run:
        print("🔎  Dry run — URLs printed above, no browser tabs opened.")
    else:
        open_urls(build_urls())
        print("Posts drafted — browser tabs opening. Best window: Tue–Thu 8–10am ET")

    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
