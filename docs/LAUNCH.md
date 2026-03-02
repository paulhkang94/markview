# MarkView Launch — Status & Distribution Plan

**Last updated:** 2026-03-01
**Current phase:** Distribution (Tier 1 posts queued for Tuesday 3/3)

---

## Part 1: What's Complete (V1 Status)

### Application Ship ✓
- **v1.1.3 released** — Apple notarized + Gatekeeper approved
- **382 tests** across 5 tiers: unit, fuzz (10K random inputs), differential (vs cmark-gfm), visual, E2E
- **CI pipeline**: 6/6 jobs green
- **MIT licensed** with comprehensive README + demo GIF
- **GitHub topics**: 10 topics added (mcp, mcp-server, model-context-protocol as of 3/1)

### Core Features ✓
- **Live markdown preview** with split-pane editor
- **GitHub Flavored Markdown** (tables, task lists, strikethrough)
- **Syntax highlighting** for 18 languages via Prism.js
- **Built-in linter** with 9 rules and auto-fix
- **Quick Look extension** for Finder spacebar preview
- **File watching** via DispatchSource (handles atomic saves from Vim/VS Code)
- **Export to HTML and PDF**
- **Dark mode** with system/light/dark options
- **18 configurable settings**

### Distribution Infrastructure ✓
- **Homebrew cask**: `brew install --cask paulhkang94/markview/markview`
  - Formula (CLI) + Cask (.app) both verified on v1.1.3
  - paulhkang94/homebrew-markview tap active with 7 commits
- **paulkang.dev live** on Cloudflare Pages
- **App signing & notarization** automated in CI
- **MCP server shipped** — `preview_markdown` + `open_file` tools, 29-test suite
  - Listed on: official MCP registry, Smithery, Glama

### Marketing Collateral ✓
- **HN Show HN already posted** (2/26, id: 46632879)
- **Distribution drafts written** for r/ClaudeAI, r/MacApps, awesome lists → docs/personal/distribution-drafts-2026-03-01.md
- **README audit complete** — ground truth verified against 382 lines of source code (9 undocumented features identified, 4 detail corrections)
- **Screenshots & demo GIF** in docs/screenshots/

---

## Part 2: Active Distribution Plan (Tier 1-3)

### Tier 1: Launch Morning — Tuesday 3/3, 9-11AM ET

**Pre-launch checklist:**
- [x] App notarized (v1.1.3)
- [x] Homebrew cask working
- [x] MCP registry updated with tool names
- [x] README finalized
- [x] Draft posts written → docs/personal/distribution-drafts-2026-03-01.md
- [ ] Monday 3/2: Review and finalize all drafts

**Channels to post (in this order):**

1. **awesome-claude-code GitHub Issue** (mar-009, due 3/3)
   - Target: `hesreallyhim/awesome-claude-code` (21.6K stars)
   - Lead with: Only markdown previewer with MCP server. Tools: `preview_markdown`, `open_file`.

2. **awesome-mcp-servers PR** (mar-011, due 3/3)
   - Target: `punkpeye/awesome-mcp-servers`
   - Add one line under Markdown category
   - Auto-cascades to Glama + mcp.so + mcpservers.org

3. **r/ClaudeAI** (mar-012, due 3/3)
   - Lead with MCP angle — this audience uses Claude Code already
   - Do NOT lead with "No Electron" here

4. **r/MacApps** (mar-014, due 3/3)
   - Lead with native/free/Swift
   - Zero MCP jargon

### Tier 2: Follow-up (Days 2-4)

**Defer to week 2:**
- Show HN (Sunday 3/8 7-9AM ET or Tuesday 3/10 9AM ET)
- Dev.to blog post
- Mastodon cross-post
- Swift Forums
- r/swift (if time permits)
- iOS Dev Weekly submission

### Tier 3: Long-tail (Week 2+)

- awesome-mac PR
- awesome-swift PR
- Product Hunt (optional, only if HN/Reddit generate traction)
- Ongoing thread replies on Mac Power Users, MacRumors, Apple Community

---

## Part 3: Success Metrics & Decision Tree

### Realistic First-30-Day Targets (for a niche OSS tool)

| Metric | Baseline | Target | Stretch |
|--------|----------|--------|---------|
| GitHub stars | 3 | 50-200 | 500+ |
| Homebrew installs | 0 | 20-50 | 100+ |
| HN upvotes | 0 | 30-100 | 200+ |
| GitHub issues filed | 0 | 5-15 | 20+ |
| MCP registry adds | 0 | 5-10 | 20+ |

### Decision Logic

```
Post Tier 1 (awesome-claude-code + awesome-mcp-servers + r/ClaudeAI + r/MacApps)
    │
    ├── >50 stars in 48h?
    │   ├── YES → Execute Tier 2 immediately, write Dev.to post
    │   └── NO  → Still do Tier 2, but space out over a week
    │
    └── After Tier 2
        ├── >100 stars? → Execute Tier 3 (awesome-*, Product Hunt)
        └── <100 stars? → Focus on content (blog posts, Swift Forums, MCP registries)
```

---

## Part 4: Messaging Strategy

### The Hook
> I use Vim/Neovim on macOS and couldn't find a good live markdown previewer, so I built one. Native Swift, ~1MB, Apple notarized. Works with Claude Desktop via MCP.

### Core Story
1. **Problem**: Markdown preview options are either slow (Electron), bloated (full editors), or missing GFM support
2. **Why MarkView**: Native Swift, instant launch, live preview, linting, Quick Look integration
3. **Who it's for**: Terminal users, macOS enthusiasts, AI tool users (MCP integration)
4. **What makes it unique**: Only markdown previewer with built-in MCP server + native UI

### Audience-Specific Angles

| Audience | Lead with | Avoid |
|----------|-----------|-------|
| r/ClaudeAI | MCP server, `preview_markdown` tool, AI-native workflow | "No Electron" (irrelevant) |
| awesome-claude-code | Only previewer with MCP server, tool names | Generic features |
| HN/programmers | Fast, well-tested, no Electron, open source, pure Swift | AI, development process |
| r/MacApps | Native, Finder integration, lightweight, notarized | MCP, architecture details |
| Swift developers | Pure SPM, no .xcodeproj, plugin architecture, testability | User-facing features |
| Markdown users | GFM fidelity, Mermaid support, linting, syntax highlighting | Implementation details |

### What NOT to Say
- Don't claim it's better than VS Code (it's not, for most people)
- Don't oversell audience size — own the niche
- Don't lead with test counts or CI stats in non-technical channels
- Don't hide that it's a personal project — own it
- Don't be defensive about feedback
- **Never mention** Claude Code, AI-assisted development, LOOP/Flow, or development timeline (except in r/ClaudeAI + r/ClaudeCode)

---

## Part 5: Post-Launch Roadmap

After the initial announcement wave, these features would expand audience reach:

| Priority | Feature | Audience unlock |
|----------|---------|-----------------|
| P1 | Homebrew core submission (not just tap) | Broader Homebrew discovery |
| P1 | MCP full feature set: `render_to_pdf`, `lint_markdown` | Claude Desktop power users |
| P2 | App Store submission | Users who won't bypass Gatekeeper |
| P2 | LaTeX/math rendering | Academic users |
| P3 | Custom CSS themes | Design-conscious users |
| P3 | Theme gallery + community contributions | Community building |

---

## Part 6: Rollback Plan

If critical issues surface after announcing:

```bash
# Don't hide the repo — fix forward instead
gh issue create --title "Known issue: ..." --body "Workaround: ..."

# Push a fix, then release a patch
bash scripts/release.sh --bump patch
git add -A && git commit -m "Release vX.X.X — hotfix for ..."
git tag vX.X.X && git push origin main --tags

# Update Homebrew formula + cask with new sha256
# (paulhkang94/homebrew-markview)
```

---

## Part 7: Monitoring & Traction Tracking

Run after each post:
```bash
bash ~/repos/markview/scripts/check-traction.sh
```

Check engagement by platform:

| Platform | URL |
|----------|-----|
| HN | https://hn.algolia.com/?q=markview |
| Reddit | Check your post history |
| GitHub | `bash scripts/check-traction.sh` |
| Cloudflare Analytics | https://dash.cloudflare.com (paulkang.dev zone) |

---

## Key Learnings

- **MCP adoption is accelerating** — official Agentic AI Foundation backing (Anthropic, Block, OpenAI, Google, Microsoft, AWS)
- **No existing markdown MCP server** with native UI — MarkView fills a gap
- **"AI writes markdown → MarkView opens" workflow is genuinely delightful** — this is the killer differentiator
- **macOS developers are hungry for native alternatives** to Electron — resonates across Swift, macOS, and terminal communities
- **Test quality sells** — 382 tests including fuzz + differential testing is a genuine signal to technical audiences

---

## Files to Delete (After Launch)

These docs were research/planning artifacts:
- `docs/LAUNCH-PLAN.md` (V1 plan, complete)
- `docs/LAUNCH-PLAN-V2.md` (V2 distribution plan, superseded by this doc)
- `docs/LAUNCH-TODO.md` (implementation checklist, all items tracked or complete)
- `docs/readme-audit-2026-03-01.md` (moved to `docs/personal/`)
- `docs/personal/mcp-feasibility.md` (research complete, MCP shipped)
- `docs/personal/mcp-implementation-context.md` (context doc for implementation, now complete)

Run: `bash docs/TO-DELETE.sh && git rm --force <files>`
