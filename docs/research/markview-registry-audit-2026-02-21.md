# MarkView MCP Registry Audit

**Date:** 2026-02-21
**Context:** Day 5 post-launch. npm published 2026-02-19. GitHub: 3 stars, 14 release downloads, 1,767 repo clones (338 unique), 82 page views (19 unique).

---

## Current State

**npm package:** `mcp-server-markview@1.1.3` — published 3 days ago, 1 version, no downloads tracked yet (npm API takes ~1 week to populate)

**npm keywords:** `mcp`, `mcp-server`, `model-context-protocol`, `markdown`, `markview`, `preview`, `macos`, `claude`

**GitHub topics:** `gfm`, `macos`, `markdown`, `markdown-preview`, `native-app`, `swift`, `swiftui` — notably missing: `mcp`, `model-context-protocol`

**Open issues:**
- #2: `TypeError: Object [object Object] has no method 'updateFrom'` — MCP protocol bug
- #3: `NSCocoaErrorDomain: Code: 260` — file not found error (affects user experience)
- #4: SwiftPM bootstrap self-test (internal dev task)

Issue #2 is the most concerning: it's an MCP-specific bug that will hit users trying the server. It surfaces quickly because the tool is only 2 tools deep.

---

## Registry Status

| Registry | Listed | Confirmed | Priority | Distribution |
|---|---|---|---|---|
| Official MCP Registry (registry.modelcontextprotocol.io) | **YES** | Verified via API | Tier 1 | Used by Claude Code auto-discovery |
| npm | **YES** | `npm view mcp-server-markview` | Tier 1 | Search discovery via keywords |
| Smithery.ai | No | Not found | High | ~250K+ devs, largest 3rd-party directory |
| Glama.ai | No | Not found in search | High | Synced with awesome-mcp-servers, has "claim" feature |
| PulseMCP | Likely No | Not surfaced in API search | High | 8,600+ servers, auto-scrapes official registry |
| mcp.so | No | Not found | Medium | 17,700+ servers, submit via GitHub issue |
| cursor.directory | No | Not found | Medium | 250K+ monthly active devs (Cursor users) |
| windsurf.run | No | Not found | Medium | Windsurf user community |
| awesome-mcp-servers (punkpeye) | No | Not found | Medium | ~30K GitHub stars, synced to glama/mcp.so |
| Cline MCP Marketplace | No | Not found | Medium | Requires logo PNG + GitHub URL |
| HiMCP.ai | No | Not found | Low | 1,600+ servers, user-submitted |
| LobeHub MCP Marketplace | No | Not found | Low | LLM-centric audience |

### Official Registry (Already Listed)

`io.github.paulhkang94/markview` is confirmed active in the official registry, published 2026-02-19. The `server.json` at `/Users/pkang/repos/markview/npm/server.json` matches the registry entry exactly. This is the most important listing — Claude Code uses this for discovery.

**Gap:** The description is minimal: "Preview Markdown in a native macOS app with live reload and GFM rendering." It doesn't mention: native Swift (no Electron), Quick Look extension, GFM tables/task lists, syntax highlighting, or the two tools by name (`preview_markdown`, `open_file`).

### PulseMCP

PulseMCP auto-scrapes the official MCP registry and npm, so it likely has MarkView by now — but the listing may be sparse. Manual submission at `pulsemcp.com/submit` would confirm and enrich it. PulseMCP explicitly syncs from `registry.modelcontextprotocol.io`.

### Smithery.ai

Not listed. Smithery is the highest-traffic independent MCP directory (~250K monthly developers). Submission uses `smithery publish` CLI:
```
smithery mcp publish https://github.com/paulhkang94/markview -n paulhkang94/markview
```
Smithery surfaces servers with install counts and compatibility info. macOS-only restriction will show clearly, which is actually a feature: it filters to the right audience.

### Glama.ai

Not listed. Glama syncs automatically from the official registry and awesome-mcp-servers, so it may auto-populate within days. Claiming ownership requires adding `glama.json` to the repo root:
```json
{
  "$schema": "https://glama.ai/mcp/schemas/server.json",
  "maintainers": ["paulhkang94"]
}
```
Claiming enables: editing the description, Docker config, usage reports, review notifications.

### awesome-mcp-servers (punkpeye/awesome-mcp-servers)

Not listed. This is the canonical community GitHub list (~30K stars). Getting listed here feeds into Glama, mcp.so, and dozens of derivative directories automatically. The list has a "Markdown" or "Developer Tools" section that MarkView fits.

PR format:
```markdown
- [MarkView](https://github.com/paulhkang94/markview) - Native macOS markdown preview with live reload, GFM, syntax highlighting, Quick Look, and MCP server integration. macOS only. 🍎
```

Category: "Markdown" or "Productivity" under the viewer/preview section.

### cursor.directory + windsurf.run

Both are maintained at `github.com/pontusab/directories`. MCP server submissions go via PR to that repo. These reach Cursor's 250K+ monthly active developer audience directly in their tool — arguably the highest-intent audience for an MCP server.

### mcp.so

Submit via GitHub issue at `github.com/chatmcp/mcp-directory/issues/1`. No format requirements — just drop the repo URL. Auto-indexes at 17,700+ servers.

### Cline MCP Marketplace

`github.com/cline/mcp-marketplace` — requires a 400x400 PNG logo and GitHub URL. MarkView doesn't have a standalone logo file yet (only used in README). This is a 20-minute asset creation task.

---

## README and Metadata Gaps

**MCP section discoverability:** The README MCP section is buried below Installation, Usage, Architecture. Users who land from an MCP registry hit the README and have to scroll. The MCP section should either be higher or have a direct anchor in the description.

**server.json description:** 62 characters. The official registry allows a longer description. Current: "Preview Markdown in a native macOS app with live reload and GFM rendering." Better: "Native macOS Markdown preview with live reload, GFM tables/task lists, syntax highlighting (18 languages), and Quick Look extension. Provides `preview_markdown` and `open_file` MCP tools."

**GitHub topics missing MCP:** The repo has no `mcp` or `model-context-protocol` topic. GitHub search for "mcp server" won't surface MarkView. This is a 30-second fix in the repo settings.

**npm keyword `macos`:** The npm keywords include `macos` but not `quicklook` or `github-flavored-markdown`. Users searching npm for markdown tools won't find it easily because the top-level search doesn't match on `markdown preview` as a phrase.

**No `glama.json`:** Needed to claim ownership on Glama.

**No 400x400 logo:** Blocks Cline marketplace submission.

---

## Open Issues That Block Adoption

**Issue #2 — `TypeError: updateFrom`** is the most urgent. A user who installs via `npx mcp-server-markview`, adds it to Claude Code, and hits this error will uninstall and never return. This should be fixed before any significant promotion push. The error suggests a JSON-RPC response shape mismatch — likely the MCP server is returning something the client doesn't expect, or the `open_file` / `preview_markdown` tool response format is wrong.

**Issue #3 — NSCocoaErrorDomain Code 260** (file not found) is a UX-level error, but less blocking than #2 since it's triggered by a bad path, not a protocol bug.

---

## Quick Wins (Under 1 Hour Total)

**1. Add GitHub topics — 2 minutes.** Go to `github.com/paulhkang94/markview` → gear icon next to "About" → add topics: `mcp`, `model-context-protocol`, `mcp-server`. This makes the repo appear in GitHub search for MCP tools and is a prerequisite for most directories that scrape GitHub metadata.

**2. Submit to awesome-mcp-servers — 15 minutes.** Fork `punkpeye/awesome-mcp-servers`, add one line to README, open PR. This single PR cascades into Glama, mcp.so, and multiple derivative directories automatically. Higher ROI than any individual submission.

**3. Submit to Smithery — 10 minutes.** `npm install -g @smithery/cli && smithery login && smithery publish`. Smithery has the highest developer traffic of any independent MCP directory and surfaces install counts publicly.

---

## Highest-Priority Single Change

Fix issue #2 (`TypeError: updateFrom`) before any promotion. Every new user who hits this bug is a lost install. The three quick wins above are 27 minutes of work that multiply reach, but they send users to a broken experience if #2 is unresolved.

If #2 is already fixed (or was a transient issue), the highest-leverage promotion action is the **awesome-mcp-servers PR** — one 15-minute PR that automatically propagates to 5+ downstream directories.

---

## Prioritized Action List

| Priority | Action | Time | Impact |
|---|---|---|---|
| P0 | Fix issue #2 (TypeError updateFrom MCP bug) | 1-2h | Unblocks all adoption |
| P1 | Add GitHub topics: `mcp`, `model-context-protocol`, `mcp-server` | 2 min | GitHub search visibility |
| P1 | PR to awesome-mcp-servers | 15 min | Cascades to 5+ directories |
| P1 | Submit to Smithery via CLI | 10 min | Highest-traffic indie MCP directory |
| P2 | Submit to PulseMCP via pulsemcp.com/submit | 5 min | Confirms/enriches auto-scraped listing |
| P2 | Add `glama.json` to repo root | 5 min | Claim Glama ownership, edit description |
| P2 | Update server.json description (more specific) | 5 min | Better official registry listing |
| P3 | PR to cursor.directory / windsurf.run (pontusab/directories) | 20 min | Cursor/Windsurf user audience |
| P3 | Submit to mcp.so via GitHub issue | 5 min | Large directory, low friction |
| P3 | Create 400x400 logo PNG, submit to Cline marketplace | 30 min | Cline user audience |
| P4 | Submit to HiMCP.ai | 5 min | Long tail |
