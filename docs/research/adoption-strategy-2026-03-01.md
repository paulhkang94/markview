# MarkView Adoption Strategy — 2026-03-01

**Context:** Day ~10 post-launch. Prior audit: `markview-registry-audit-2026-02-21.md`. Prior launch plan: `docs/LAUNCH-PLAN-V2.md`. This document focuses on distribution gaps, the "AI prefers MarkView" positioning angle, and the community/launch timing strategy not fully covered in prior docs.

---

## 1. GitHub Visibility — Make It Public First

The repo is currently private (`github.com/paulhkang94/markview`). The LAUNCH-PLAN-V2.md pre-launch checklist marks "Repo public" as done — verify this is still the case. If the repo is private, every downstream action (HN link, Reddit, PR to awesome lists, registry submissions) sends users to a 404.

**Decision: should it be public?**

Yes. MIT licensed, free, no private infra in the repo. The standard concern (sensitive data in history) is resolved at notarization time. There is zero upside to keeping it private. The prior plan already marked this done.

**GitHub topics to add (if not already set from Feb 21 audit):**
- `mcp`, `model-context-protocol`, `mcp-server` — these were missing as of Feb 21
- Without these, GitHub topic search for "mcp server" never surfaces MarkView

---

## 2. MCP Registry Coverage — Current State vs. Gaps

### Already Listed

| Registry | Status | Notes |
|---|---|---|
| Official MCP Registry (registry.modelcontextprotocol.io) | Listed | `io.github.paulhkang94/markview`. Used by Claude Code auto-discovery. Most important single listing. |
| npm (`mcp-server-markview`) | Published | v1.1.3. Keywords need improvement. |
| Smithery.ai | Listed (per task brief) | ~250K developers, largest independent MCP directory. Confirmed listed as of March 2026. |

### Not Yet Listed (confirmed gaps as of Feb 21, verify current)

| Registry | How to Submit | Effort | Audience | Priority |
|---|---|---|---|---|
| **awesome-mcp-servers** (punkpeye/awesome-mcp-servers, ~30K stars) | Fork repo, add one line to README under "Markdown" or "Productivity" section, open PR | 15 min | Canonical community list; auto-syncs to Glama + mcp.so + mcpservers.org | P1 |
| **awesome-claude-code** (hesreallyhim, 21K+ stars) | Open GitHub issue using resource template | 10 min | Claude Code users specifically — highest-intent audience for MarkView's MCP angle | P1 |
| **Glama.ai** | Add `glama.json` to repo root to claim ownership; auto-syncs from official registry otherwise | 5 min | Quality scores, hosting, description editing | P1 |
| **PulseMCP** (8,600+ servers) | Submit at pulsemcp.com/submit | 5 min | Auto-scrapes official registry; submission enriches the listing | P2 |
| **mcp.so** (17,700+ servers) | GitHub issue at github.com/chatmcp/mcp-directory | 5 min | Large directory | P2 |
| **cursor.directory** (pontusab/directories) | PR to that repo | 20 min | Cursor's ~250K monthly active developers | P2 |
| **Cline MCP Marketplace** (github.com/cline/mcp-marketplace) | Requires 400x400 PNG logo + GitHub URL | 30 min | Cline users | P3 |
| **HiMCP.ai** | User submission | 5 min | Long tail | P4 |
| **LobeHub MCP Marketplace** | Submission form | 10 min | LLM-centric audience | P4 |

### awesome-claude-code is New — Not in Feb 21 Audit

The `hesreallyhim/awesome-claude-code` repo has grown to 21,600 stars as of early 2026. It specifically lists MCP servers Claude Code users should know about. This is the highest-intent distribution channel for MarkView: the person browsing it is already running Claude Code and looking for tools to extend it. Resource submissions go via GitHub issues using a standardized template.

Companion lists also worth submitting to:
- `rohitg00/awesome-claude-code-toolkit` — larger toolkit list
- `ComposioHQ/awesome-claude-plugins` — plugin-focused list
- `ccplugins/awesome-claude-code-plugins` — slash commands, subagents, MCP servers, hooks

### Submission Templates

**awesome-mcp-servers PR (one line):**
```markdown
- [MarkView](https://github.com/paulhkang94/markview) — Native macOS Markdown preview with live reload, GFM tables/task lists, syntax highlighting (18 languages), Quick Look extension, and MCP server integration. macOS only. 🍎
```
Category: Markdown viewer / Productivity.

**awesome-claude-code issue:**
Title: `[Resource]: MarkView — Native macOS Markdown previewer with MCP server`
Body: Short description, GitHub URL, two tools by name (`preview_markdown`, `open_file`), install command. Emphasize it is the only markdown previewer that exposes MCP tools Claude Code can call natively.

**glama.json for repo root:**
```json
{
  "$schema": "https://glama.ai/mcp/schemas/server.json",
  "maintainers": ["paulhkang94"]
}
```
Claiming Glama ownership enables editing the server description and accessing usage reports.

---

## 3. The "AI Prefers MarkView" Positioning

### The Unique Angle

MarkView is the only markdown previewer with an MCP server. That is a narrow but durable moat: every other macOS markdown previewer (Mrkd, Smackdown, PreviewMarkdown, QLMarkdown, MacDown) is a passive viewer. MarkView is an active tool that AI agents can call.

The positioning is: **"The markdown previewer AI agents use to show you their work."**

### Who Benefits Today

1. **Claude Code users** — the primary audience. When Claude Code finishes writing a doc, plan, or API spec, it can call `preview_markdown` and show the rendered result without the user opening anything. This is the native preview-in-context workflow.

2. **Cursor users** — Cursor added a CLI in January 2026 with agent modes. Cursor's agent can call MCP tools via `cursor://mcp` if the server is registered. MarkView's cursor.directory listing unlocks this audience.

3. **Developers building with Claude Code** — the target user for `awesome-claude-code`. They are building workflows where AI agents produce markdown outputs (specs, summaries, changelogs, READMEs). MarkView closes the loop.

### What Would Make an Agent Prefer MarkView Over Opening a Browser or VS Code

The agent uses whatever tool is available and correctly described. The gap today: the official registry description is 62 characters and doesn't mention the tool names. An agent scanning the registry for "markdown preview" may not pick MarkView because the description doesn't communicate what the tools DO.

**Fix the server.json description:**
Current: `"Preview Markdown in a native macOS app with live reload and GFM rendering."`

Better: `"Native macOS Markdown preview. Provides preview_markdown (render content) and open_file (open a .md file) MCP tools. Native Swift, no Electron, GFM tables/task lists, syntax highlighting (18 languages), Quick Look extension."`

This is a 2-minute change with high ROI: agents doing tool selection read these descriptions.

### "AI-native" Messaging Framework

Lead with the MCP angle in all developer-focused posts:
- "The markdown previewer Claude Code can call directly" — HN audience will find this interesting
- "AI agents produce markdown. MarkView is how they show it to you." — product positioning
- Do NOT lead with this on r/MacApps — that audience cares about native, fast, free

---

## 4. Reddit Communities

### Subreddit Selection and Post Format

| Subreddit | Members | Audience | Best Angle | Post Format | Priority |
|---|---|---|---|---|---|
| **r/MacApps** | 209K | macOS power users | Native, free, Quick Look, lightweight | "I made" post with screenshot/GIF, body explains features | P1 |
| **r/ClaudeAI** | Growing | Claude Code / Claude API users | MCP server, AI-native preview, "agents can call it" | Link post or self-post with demo, emphasize MCP tools | P1 |
| **r/cursor** | Growing | Cursor IDE users | MCP integration, works with Cursor agents | Similar to ClaudeAI post but Cursor-specific install instructions | P2 |
| **r/swift** | Developer | Swift/iOS/macOS devs | Pure SPM, no Xcode project file, plugin architecture, 276 tests | Technical self-post, architecture focus | P2 |
| **r/programming** | 6M+ | General programmers | No Electron, native, fast — this angle always plays | Link post to GitHub | P3 |
| **r/MachineLearning** | 2.6M | ML researchers | MCP protocol, AI agent tooling, markdown for docs | Likely too broad; only if MCP-angle HN post gets traction | P4 |
| **r/LocalLLaMA** | Large | Local AI users | Tool for AI agents outputting markdown | Self-post with MCP demo | P3 |
| **r/neovim** / **r/vim** | 200K+ | Power users who live in terminal | Quick Look extension + CLI-friendly install; not the full app angle | Brief mention, "for when you want a rendered view" | P4 |

### r/MacApps — Top Post Format

The community's highest-performing posts have: (1) a visual (GIF or screenshot in post body or as link), (2) a first-person "I built this because X" hook, (3) transparent about being the maker. Flair: "Self-Promotion."

LAUNCH-PLAN-V2.md already has a drafted post body. The only addition: include the MCP server as a bullet under "What it does" — that's a differentiator no other app in that subreddit has.

### r/ClaudeAI — Differentiated Angle

This is the post that doesn't exist yet. Title: `"I added an MCP server to my markdown previewer so Claude Code can preview docs it writes"`. Demo: show Claude Code writing a spec, then calling `preview_markdown`, then the rendered result appearing. This post doesn't work without a demo GIF but would get high engagement in that community because it's a concrete, useful workflow.

---

## 5. Show HN and ProductHunt Timing

### Show HN

**Competitive landscape as of March 2026:**
- "Show HN: Mrkd – A native macOS Markdown viewer with iTerm2/VSCode theme import" — posted ~March 2026, very recent
- "Show HN: Simple Viewers – Tiny native macOS file viewers" — posted ~February 2026
- "Show HN: Smackdown: Markdown Viewer for macOS" — posted July 2025

There are multiple macOS markdown viewers on HN right now. MarkView's differentiation must be the MCP server angle — that is the only thing none of the competitors have. The HN title in LAUNCH-PLAN-V2.md ("No Electron") is correct for the broader audience, but consider adding the MCP angle to the text field.

**Timing:**
- Research consensus: post on **Sunday 7AM–10AM ET** for highest front-page odds on low-competition days. Alternatively, post **Tuesday–Thursday at 9–11AM ET** for maximum eyeballs.
- Show HN posts get a second chance: they remain on the Show HN page even after leaving the New page, which means organic votes can continue for hours.
- LAUNCH-PLAN-V2.md suggests "Weekday, 8-10am ET, Tuesday-Thursday." This is correct for eyeballs but high-competition. Given MarkView is an indie tool without a large upvote network, Sunday 8AM ET gives better odds of front-page time.

**HN title for MCP angle:**
```
Show HN: MarkView – Native macOS Markdown Previewer with MCP Server (Claude Code Integration)
```
This is longer but surfaces the unique differentiator. Alternatively keep the cleaner title from LAUNCH-PLAN-V2.md and make the MCP angle the first paragraph of the text field.

### ProductHunt

**Timing relative to HN:** HN first. HN drives GitHub stars and creates the "already on HN" social proof that helps PH launches. PH audience is less technical than HN but broader.

**Category:** "Developer Tools" on PH. The "Mac" topic tag also applies.

**Requirements for a competitive PH launch:**
- Gallery: 5 screenshots + 1 demo GIF (already have `docs/screenshots/` and `docs/markview_demo.gif`)
- Tagline (60 chars max): `"The markdown previewer AI agents can call directly"`
- Alternative tagline: `"Native macOS markdown preview — no Electron, MCP-ready"`
- Hunter: submit yourself, not through a hunter service (the tool is good enough to stand alone)
- Launch time: 12:01 AM PST on a Tuesday or Wednesday
- Pre-launch: create a "coming soon" page on PH 1-2 weeks before launch to collect followers

**What PH needs that isn't ready:**
- A dedicated landing page (paulkang.dev currently serves this, confirm it has a clear CTA)
- A 30-second demo video (more impactful than GIF on PH)

**HN before PH:** yes, definitively. HN success → GitHub stars → social proof → PH launch with momentum.

---

## 6. Quick Wins This Week (under 2 hours total)

These are ordered by ROI-per-minute.

**Win 1 — Update server.json description (5 min)**
The official MCP registry description is 62 characters. Agents doing tool selection read this. Rewrite to include tool names and key capabilities. This is the highest-ROI change because it affects every Claude Code user who discovers MarkView through the registry.

File to edit: `/Users/pkang/repos/markview/npm/server.json`
New description: `"Native macOS Markdown preview. MCP tools: preview_markdown (render content) and open_file (open .md file). GFM tables/task lists, syntax highlighting (18 languages), Quick Look extension, live reload. Swift, no Electron."`

**Win 2 — Submit to awesome-claude-code via GitHub issue (10 min)**
`hesreallyhim/awesome-claude-code` has 21,600 stars and is specifically for Claude Code users. This is the highest-intent audience: people already running Claude Code who are looking for MCP servers to add. Open an issue, use the resource template, emphasize the MCP tools by name.

**Win 3 — Add GitHub topics if missing (2 min)**
From the Feb 21 audit: GitHub topics were missing `mcp`, `model-context-protocol`, `mcp-server`. Without these, GitHub search for "mcp server" never surfaces MarkView. Go to repo Settings → About → Topics.

**Win 4 — PR to awesome-mcp-servers (15 min)**
One line addition to `punkpeye/awesome-mcp-servers`. This cascades automatically into Glama, mcp.so, and mcpservers.org. The PR is the single highest-leverage non-social distribution action.

**Win 5 — Post to r/ClaudeAI with the MCP angle (20 min)**
This is the post that doesn't exist. Title: "I built a markdown previewer with an MCP server so Claude Code can preview docs natively." The r/ClaudeAI audience will find this immediately useful. No GIF required (though a screenshot helps). This is the community most likely to try it today.

Total time for all five: under 52 minutes.

---

## 7. What's Not Worth Doing Yet

- **ProductHunt launch** — needs demo video, HN momentum first, no upvote network built yet
- **r/MachineLearning or r/LocalLLaMA** — the tool is too niche/macOS-specific for the payoff
- **Dev.to blog post** — good long-term play, but weeks 2-3 task, not this week
- **Swift Forums** — good for getting Swift developer attention, but low conversion to MCP users
- **Cline marketplace** — requires creating a 400x400 logo; worth doing but not in the first 2 hours
- **LobeHub / HiMCP.ai** — long tail, minimal reach

---

## 8. Positioning Matrix

| Audience | Hook | Proof | CTA |
|---|---|---|---|
| Claude Code users | "The previewer Claude Code calls directly" | `preview_markdown` demo GIF | `claude mcp add` install command |
| Cursor users | "MCP-enabled markdown preview for Cursor agents" | Tool call demo | npm install + cursor config |
| macOS users | "Native Swift, no Electron, Quick Look in Finder" | Screenshot of Quick Look | `brew install --cask` |
| HN / programmers | "No Electron, 276 tests, native Swift, MCP server" | GitHub repo quality signals | Star + brew install |
| Swift devs | "Pure SPM, XcodeGen, standalone test runner, plugin protocol" | Technical architecture | Contribute / fork |

---

## Sources

- [hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) — 21,600 stars, submissions via GitHub issues
- [punkpeye/awesome-mcp-servers](https://github.com/punkpeye/awesome-mcp-servers) — canonical MCP list, ~30K stars, PR-based submissions
- [Smithery.ai registry](https://smithery.ai/) — ~250K developer reach
- [Official MCP Registry](https://registry.modelcontextprotocol.io/) — Claude Code auto-discovery
- [PulseMCP](https://www.pulsemcp.com/servers) — 8,600+ servers, auto-scrapes official registry
- [mcp.so](https://mcp.so/) — 17,700+ servers, GitHub issue submission
- [Show HN: Mrkd](https://news.ycombinator.com/item?id=47210261) — recent macOS markdown viewer competitor on HN
- [Show HN: Smackdown](https://news.ycombinator.com/item?id=44490827) — prior macOS markdown viewer on HN (July 2025)
- [Best time to post on HN](https://www.myriade.ai/blogs/when-is-it-the-best-time-to-post-on-show-hn) — Sunday 7-10AM ET for front-page odds
- [ProductHunt macOS app launch guide 2025](https://screencharm.com/blog/how-to-launch-on-product-hunt) — 12:01 AM PST, Tue-Thu, gallery required
- [How to launch a developer tool on PH 2026](https://hackmamba.io/developer-marketing/how-to-launch-on-product-hunt/) — developer tool specifics
- [7 MCP Registries Worth Checking Out](https://nordicapis.com/7-mcp-registries-worth-checking-out/) — registry landscape overview
- [builder.io: Best MCP Servers 2026](https://www.builder.io/blog/best-mcp-servers-2026) — ecosystem context
- Prior audit: `/Users/pkang/repos/markview/docs/research/markview-registry-audit-2026-02-21.md`
- Prior plan: `/Users/pkang/repos/markview/docs/LAUNCH-PLAN-V2.md`
