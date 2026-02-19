# MarkView Launch — Implementation TODO

**Date:** 2026-02-19
**Source docs:** `docs/markview/launch-plan.md`, `markview/docs/LAUNCH-PLAN.md`, `markview/docs/personal/competitor-channels.md`, `markview/docs/personal/monetization-research.md`

---

## Status: What's Done

- [x] Repo public, clean history, MIT license
- [x] README with demo GIF + screenshots
- [x] v1.1.3 released — Apple notarized + Gatekeeper approved
- [x] Homebrew cask: `brew install --cask paulhkang94/markview/markview`
- [x] MCP server published on registry: `io.github.paulhkang94/markview`
- [x] npm package: `mcp-server-markview@1.1.3`
- [x] 276 tests, CI green (6/6 jobs)
- [x] Quick Look extension
- [x] HN Show HN posted: https://news.ycombinator.com/item?id=46632879
- [x] paulkang.dev live on Cloudflare Pages

## Current Metrics (Day 4)

| Metric | Value |
|--------|-------|
| Stars | 2 |
| Unique page viewers | 16 |
| Release downloads | 11 |
| Organic search referrals | 2 (Google + DuckDuckGo) |

---

## Phase 1: Zero-Cost Setup (30 min total)

### 1.1 Create FUNDING.yml
- [ ] Create `.github/FUNDING.yml` in markview repo
```yaml
github: paulhkang94
buy_me_a_coffee: paulkang
```
- [ ] Verify GitHub Sponsors is enabled at https://github.com/sponsors/paulhkang94/dashboard
- [ ] If not set up: https://github.com/sponsors/paulhkang94 → "Get started"

### 1.2 Add Buy Me a Coffee
- [ ] Create account at https://www.buymeacoffee.com (use `paulkang` handle)
- [ ] Add link to README.md Support section

### 1.3 Update README version references
- [ ] Verify README references v1.1.3 (not v1.1.1)
- [ ] Verify Homebrew cask sha256 matches v1.1.3 release

---

## Phase 2: Tier 1 Launch Posts (Day 1 — pick a Tue/Wed)

**Best time: 8-10am ET.** All copy is pre-written below (vetted from launch-plan.md).

### 2.1 HN Re-assess
- [x] Show HN already posted (https://news.ycombinator.com/item?id=46632879)
- [ ] Check HN post performance: https://hn.algolia.com/?q=markview
- [ ] If <10 upvotes: eligible for repost in 1 week with updated title from `docs/markview/launch-plan.md`
- **Updated title** (from launch-plan.md):
  ```
  Show HN: MarkView – Native macOS Markdown Previewer in Swift (No Electron)
  ```
- **URL field**: `https://github.com/paulhkang94/markview`

### 2.2 Reddit r/macapps — 12:00 PM ET
- [ ] Post to https://www.reddit.com/r/macapps/submit
- **Title:**
  ```
  MarkView: Free, native macOS markdown previewer with GFM, syntax highlighting, Quick Look, and Homebrew install
  ```
- **Body:** Copy from `docs/markview/launch-plan.md` Section "Tier 1 → 2. Reddit → r/macapps"

### 2.3 Reddit r/neovim — 10:00 AM ET
- [ ] Post to https://www.reddit.com/r/neovim/submit
- **Title:**
  ```
  MarkView – free native macOS markdown previewer with live reload (no plugins needed)
  ```
- **Body:** Copy from `markview/docs/LAUNCH-PLAN.md` Section "2. r/neovim"

### 2.4 Reddit r/vim — 10:15 AM ET
- [ ] Post to https://www.reddit.com/r/vim/submit
- **Title:**
  ```
  MarkView – free native macOS markdown previewer with live reload (works with any editor, no plugins)
  ```
- **Body:** Same as r/neovim, adjusted per LAUNCH-PLAN.md Section "3. r/vim"

### 2.5 Twitter/X Thread
- [ ] Post 5-tweet thread from `markview/docs/LAUNCH-PLAN.md` Section "9. Twitter/X"
- [ ] Attach demo GIF to tweet 1: `markview/docs/markview_demo.gif`
- [ ] Attach screenshot to tweet 3: `markview/docs/screenshots/editor-preview.png`

---

## Phase 3: Tier 2 Posts (Days 2-4)

### 3.1 Reddit r/ClaudeAI — Day 2, 10:00 AM ET
- [ ] Post to https://www.reddit.com/r/ClaudeAI/submit
- **Title:**
  ```
  Built a native macOS app almost entirely with Claude Code — 294 tests, Quick Look extension, Homebrew tap, no Xcode
  ```
- **Body:** Copy from `markview/docs/LAUNCH-PLAN.md` Section "5. r/ClaudeAI"
- **Note:** This is the ONLY channel where mentioning Claude Code is appropriate

### 3.2 Reddit r/ClaudeCode — Day 2, 10:30 AM ET
- [ ] Post to https://www.reddit.com/r/ClaudeCode/submit
- **Title:**
  ```
  Shipped a production macOS app built entirely in Claude Code — lessons learned
  ```
- **Body:** Copy from `markview/docs/LAUNCH-PLAN.md` Section "6. r/ClaudeCode"

### 3.3 Reddit r/swift + Swift Forums — Day 2, afternoon
- [ ] Post to https://www.reddit.com/r/swift/submit
- [ ] Post to https://forums.swift.org/c/related-projects/7
- **Body:** Copy from `markview/docs/LAUNCH-PLAN.md` Section "7. r/swift + Swift Forums"

### 3.4 Lobsters — Day 2-3
- [ ] Check if you have a Lobsters account (invite-only)
- [ ] If yes: post to https://lobste.rs/stories/new
- **Title:**
  ```
  Show: MarkView – Native macOS markdown previewer (Swift, SPM-only, no Electron)
  ```

### 3.5 Reddit r/commandline — Day 3
- [ ] Post to https://www.reddit.com/r/commandline/submit
- **Body:** Copy from `markview/docs/LAUNCH-PLAN.md` Section "13. r/commandline"

### 3.6 Mastodon — Day 2
- [ ] Cross-post Tweet 1 content to https://mastodon.social/publish (or your instance)

---

## Phase 4: Awesome Lists & Directories (Days 3-7)

### 4.1 awesome-mac PR
- [ ] Fork https://github.com/jaywcjlove/awesome-mac
- [ ] Add to Markdown Tools section (alphabetically):
  ```markdown
  * [MarkView](https://github.com/paulhkang94/markview) - Native macOS markdown previewer with live reload, GFM, syntax highlighting, Quick Look extension. No Electron. ![Open-Source Software][OSS Icon] ![Freeware][Freeware Icon]
  ```
- [ ] PR title: `Add MarkView to Markdown Tools`

### 4.2 awesome-swift PR
- [ ] Fork https://github.com/matteocrippa/awesome-swift
- [ ] Add to App (macOS) section:
  ```markdown
  - [MarkView](https://github.com/paulhkang94/markview) - Native macOS markdown previewer with GFM, syntax highlighting, linting, Quick Look extension. SPM-only, no Xcode.
  ```
- [ ] PR title: `Add MarkView — native markdown previewer`

### 4.3 open-source-mac-os-apps PR
- [ ] Fork https://github.com/serhii-londar/open-source-mac-os-apps
- [ ] Add to Markdown section:
  ```markdown
  - [MarkView](https://github.com/paulhkang94/markview) - Native markdown previewer with live reload, GFM, syntax highlighting for 18 languages, linting, and Quick Look extension.  ![swift_icon]
  ```

### 4.4 awesome-markdown PRs (2 repos)
- [ ] https://github.com/BubuAnabelas/awesome-markdown — add under Tools/Viewers
- [ ] https://github.com/mundimark/awesome-markdown-editors — add under macOS

### 4.5 awesome-macOS + awesome-native-macosx-apps
- [ ] https://github.com/iCHAIT/awesome-macOS
- [ ] https://github.com/open-saas-directory/awesome-native-macosx-apps

### 4.6 Markdown Guide tools directory
- [ ] Fork https://github.com/mattcone/markdown-guide
- [ ] Add entry to `_tools/` following YAML frontmatter format (see Marked 2 entry as template)

### 4.7 AlternativeTo listing
- [ ] Submit at https://alternativeto.net
- [ ] Tag as alternative to: MacDown, Marked 2, Typora, Glow

### 4.8 Slant
- [ ] Add to "Best alternatives to MacDown" and "Best alternatives to Typora" pages at https://slant.co

---

## Phase 5: Forum Replies (Ongoing)

Reply to existing threads where users ask for markdown previewers:

### 5.1 MPU Talk (Mac Power Users)
- [ ] New topic at https://talk.macpowerusers.com
- [ ] Reply to existing threads:
  - https://talk.macpowerusers.com/t/current-state-of-markdown-editors/38770
  - https://talk.macpowerusers.com/t/anybody-have-suggestions-for-a-single-file-markdown-editor/36106
  - https://talk.macpowerusers.com/t/markdown-editor-again/40410

### 5.2 MacRumors
- [ ] Reply to:
  - https://forums.macrumors.com/threads/alternative-to-macdown.2411390/
  - https://forums.macrumors.com/threads/advise-please-on-a-choosing-a-markdown-editor-for-mac.2308534/

### 5.3 Apple Community
- [ ] Reply to: https://discussions.apple.com/thread/255993123

---

## Phase 6: Content (Week 2)

### 6.1 Dev.to blog post
- [ ] Publish at https://dev.to/new
- **Title:** `Building a native macOS app with 294 tests and zero Xcode`
- **Tags:** `swift`, `macos`, `opensource`, `testing`
- **Outline:** in `markview/docs/LAUNCH-PLAN.md` Section "11. Dev.to Blog Post"

### 6.2 iOS Dev Weekly submission
- [ ] Submit at https://iosdevweekly.com/submit
- [ ] Submit GitHub repo URL

---

## Phase 7: App Store (when ready)

### 7.1 Prerequisites
- [ ] Register bundle ID `com.markview.app` in Apple Developer Portal
- [ ] Create App Store Connect record
- [ ] Decide: ship without Quick Look (v1) or fix Quick Look sandbox crash first
  - Quick Look fix research: `markview/docs/research/ql-webview-sandbox-analysis.md`
  - Recommendation: ship without QL, add in update

### 7.2 App Store Submission
- [ ] Screenshots (5.5" + 6.7" equivalent for Mac, or 1280x800 + 2560x1600)
- [ ] App description (reuse README feature list)
- [ ] Privacy policy URL (paulkang.dev/privacy or simple GitHub-hosted page)
- [ ] Set price: $6.99 (per monetization research)
- [ ] Category: Developer Tools
- [ ] Submit for review

---

## Monitoring

Run after each post:
```bash
bash ~/repos/markview/scripts/check-traction.sh
```

Check engagement:
| Platform | URL |
|----------|-----|
| HN | https://hn.algolia.com/?q=markview |
| Reddit | Check your post history |
| GitHub | `bash scripts/check-traction.sh` |
| Cloudflare | https://dash.cloudflare.com → paulkang.dev → Analytics |

---

## Decision Tree (from launch-plan.md)

```
Post Tier 1 (HN + Reddit + Twitter)
    │
    ├── >50 stars in 48h?
    │   ├── YES → Execute Tier 2 immediately
    │   └── NO  → Still do Tier 2, space out over a week
    │
    └── After Tier 2
        ├── >100 stars? → Product Hunt + all awesome-* PRs
        └── <100 stars? → Focus on content (blog posts, Swift Forums)
```

---

## Key Rules

1. **Never mention** Claude Code, AI-assisted development, LOOP/Flow, development timeline, or cost — except in r/ClaudeAI and r/ClaudeCode posts
2. **Always reply** to comments within 2-3 hours on launch day
3. **Don't ask friends to upvote** HN (voting ring detection)
4. **Own the niche** — "it does one thing and tries to do it well"
5. **Don't be defensive** about feedback — thank people and file issues
