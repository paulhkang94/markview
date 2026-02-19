# MarkView Launch Publicization Plan

**Repo**: https://github.com/paulhkang94/markview
**Updated**: 2026-02-19
**Status**: Ready to execute — all pre-launch items complete

---

## Pre-launch Checklist (all done)

- [x] Repo public with clean history
- [x] README with screenshots + demo GIF
- [x] MIT LICENSE
- [x] App icon
- [x] GitHub topics (7 topics set)
- [x] paulkang.dev live on Cloudflare Pages
- [x] Private contributions disabled on GitHub profile
- [x] Screenshots in docs/screenshots/
- [x] Homebrew cask: `brew install --cask markview` (via paulhkang94/homebrew-markview)
- [x] Apple notarized + Gatekeeper approved (v1.1.3)
- [x] Quick Look extension (preview .md in Finder)
- [x] MCP server for AI tool integration
- [x] 276 tests (unit + fuzz + differential + e2e)
- [x] CI green (6/6 jobs)

---

## Tier 1: Launch Morning (all at once, ~30 min)

**Best time**: Weekday, 8-10am ET. Tuesday-Thursday optimal for HN.

### 1. Hacker News — Show HN

**URL**: https://news.ycombinator.com/submit

**Title** (exact, 80 chars):
```
Show HN: MarkView – Native macOS Markdown Previewer in Swift (No Electron)
```

**URL field**: `https://github.com/paulhkang94/markview`

**Text field** (leave blank — URL submissions don't get text on HN, but if it converts to text post):
```
I kept reaching for Markdown preview and finding the options either slow (Electron), bloated (full editors when I just want preview), or missing GFM support.

So I built MarkView: a native Swift/SwiftUI app (~1MB) that renders GitHub Flavored Markdown with live preview. Apple notarized, installs via Homebrew.

- 276 tests including fuzz testing (10K random inputs, zero crashes)
- Plugin architecture (Markdown, CSV, HTML renderers)
- Built-in linter with 9 rules
- Quick Look extension — preview .md files in Finder
- No Xcode required — pure Swift Package Manager

brew install --cask paulhkang94/markview/markview

Free, MIT licensed.
```

---

### 2. Reddit (3 posts)

#### r/macapps
**URL**: https://www.reddit.com/r/macapps/submit

**Title**:
```
MarkView: Free, native macOS markdown previewer with GFM, syntax highlighting, Quick Look, and Homebrew install
```

**Body**:
```
I built a lightweight markdown previewer because the Electron-based ones felt heavy for what I needed.

**What it does:**
- Native Swift/SwiftUI — ~1MB, instant launch
- GitHub Flavored Markdown (tables, task lists, strikethrough)
- Syntax highlighting for 18 languages
- Built-in linter (9 rules — broken links, unclosed fences, etc.)
- Quick Look extension — preview .md right in Finder
- Split-pane editor with live reload
- Dark mode + 17 configurable settings

**Install:**
```
brew install --cask paulhkang94/markview/markview
```

Apple notarized, no Gatekeeper warnings.

GitHub: https://github.com/paulhkang94/markview
```

#### r/swift
**URL**: https://www.reddit.com/r/swift/submit

**Title**:
```
Built a macOS markdown previewer with pure SPM — no Xcode project file needed
```

**Body**:
```
MarkView is a native macOS markdown previewer I built entirely with Swift Package Manager for the core library + XcodeGen for the app target. No checked-in .xcodeproj.

Some technical details that might be interesting:
- **MarkViewCore** is a pure SPM library — MarkdownRenderer, FileWatcher, Linter, Plugins, all testable without UI
- **276 tests** including a standalone test runner executable (no XCTest dependency)
- **Fuzz tester**: 10K random markdown inputs, differential testing against cmark-gfm
- **Plugin architecture**: `LanguagePlugin` protocol for CSV, HTML, and future format support
- **Quick Look extension** using QLPreviewingController + WKWebView
- File watching via DispatchSource (handles atomic saves from VS Code/Vim)

The whole thing builds with just `swift build` for the library, or `xcodegen generate && xcodebuild` for the app.

GitHub: https://github.com/paulhkang94/markview (MIT)
```

#### r/programming
**URL**: https://www.reddit.com/r/programming/submit

Use **Link** post type:
- **Title**: `MarkView — Native macOS Markdown previewer in Swift, no Electron (~1MB, 276 tests, Apple notarized)`
- **URL**: `https://github.com/paulhkang94/markview`

---

### 3. Twitter/X Thread

**URL**: https://x.com/compose/post

**Tweet 1** (< 280 chars):
```
Built a native macOS markdown previewer because Electron ones felt slow.

MarkView: ~1MB, instant launch, GitHub Flavored Markdown, syntax highlighting for 18 langs, built-in linter.

Free + open source + Apple notarized.

brew install --cask paulhkang94/markview/markview

https://github.com/paulhkang94/markview
```

**Tweet 2** (reply):
```
Some details I'm happy with:

- 276 tests (including 10K random input fuzz testing — zero crashes)
- Plugin architecture (Markdown, CSV, HTML renderers)
- Quick Look extension — preview .md right in Finder
- Pure Swift Package Manager — builds with just Command Line Tools
- MCP server for AI tool integration
```

**Tweet 3** (reply):
```
Right-click any .md → Quick Look → instant rendered preview. No app launch needed.

Or open in MarkView for the full split-pane editor with live reload.

[attach docs/screenshots/editor-preview.png]
```

---

## Tier 2: Follow-up (days 2-4)

### 4. Dev.to Blog Post

**URL**: https://dev.to/new

**Title**: `Building a native macOS app with pure Swift Package Manager (no Xcode project)`

**Tags**: `swift`, `macos`, `opensource`, `markdown`

**Content angle**: Technical deep-dive on the SPM + XcodeGen architecture. Interesting to Swift devs because most macOS apps require .xcodeproj. Cover:
- Why SPM-first (testability, CI simplicity, no merge conflicts on .pbxproj)
- XcodeGen for app targets that need entitlements/Info.plist
- Standalone test runner pattern (no XCTest dependency)
- Plugin protocol for extensible rendering
- Link back to GitHub repo

### 5. Mastodon

**URL**: https://mastodon.social/publish (or your instance)

Cross-post Tweet 1 content. Strong Swift/Apple community on Mastodon.

### 6. Swift Forums

**URL**: https://forums.swift.org/c/related-projects/7

**Title**: `MarkView — Native macOS markdown previewer built with SPM + SwiftUI`

Short post linking to repo, emphasizing the SPM-first architecture.

### 7. iOS Dev Weekly Submission

**URL**: https://iosdevweekly.com/submit

Submit the GitHub repo URL. Dave Verwer curates — he likes native Mac apps.

---

## Tier 3: Ongoing (week 2+)

### 8. awesome-macos PR

**Repo**: https://github.com/jaywcjlove/awesome-mac

```bash
# Fork + clone
gh repo fork jaywcjlove/awesome-mac --clone
cd awesome-mac

# Add entry under "Markdown Tools" section
# Find the right section and add alphabetically:
# - [MarkView](https://github.com/paulhkang94/markview) - Native macOS markdown previewer with GFM, syntax highlighting, linting, and Quick Look. ![Open-Source Software][OSS Icon] ![Freeware][Freeware Icon]

# Then:
git checkout -b add-markview
git add README.md
git commit -m "Add MarkView to Markdown Tools section"
gh pr create --title "Add MarkView — native macOS markdown previewer" --body "MarkView is a native Swift/SwiftUI markdown previewer with GFM support, syntax highlighting, built-in linter, and Quick Look extension. MIT licensed."
```

### 9. awesome-swift PR

**Repo**: https://github.com/matteocrippa/awesome-swift

Similar process — add under App / macOS section.

### 10. Product Hunt (optional, week 2+)

**URL**: https://www.producthunt.com/posts/new

Only if HN/Reddit generate interest. PH audience skews toward GUI/consumer — less technical.

---

## Key Messaging (reference card)

| Audience | Lead with | Avoid |
|----------|-----------|-------|
| HN/programmers | No Electron, fast, well-tested, open source | AI, Claude, development process |
| Mac users | Native, Finder integration, lightweight, notarized | SPM, architecture details |
| Swift devs | Pure SPM, no Xcode, plugin protocol, testability | User-facing features |
| Markdown users | GFM fidelity, linting, syntax highlighting | Implementation details |

**Never mention**: Claude Code, AI-assisted development, LOOP/Flow, development timeline, cost.

---

## Automated Validation Script

Run before and after each post to track traction:

```bash
#!/bin/bash
# Save as scripts/check-traction.sh in markview repo
echo "=== MarkView Traction Check ==="
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# GitHub stats
REPO_DATA=$(gh api repos/paulhkang94/markview --jq '{stars: .stargazers_count, forks: .forks_count, watchers: .subscribers_count, open_issues: .open_issues_count}')
echo "GitHub: $REPO_DATA"

# Clone traffic (last 14 days)
CLONES=$(gh api repos/paulhkang94/markview/traffic/clones --jq '{total: .count, unique: .uniques}')
echo "Clones (14d): $CLONES"

# View traffic (last 14 days)
VIEWS=$(gh api repos/paulhkang94/markview/traffic/views --jq '{total: .count, unique: .uniques}')
echo "Views (14d): $VIEWS"

# Top referrers
echo "Referrers:"
gh api repos/paulhkang94/markview/traffic/popular/referrers --jq '.[] | "  \(.referrer): \(.count) (\(.uniques) unique)"'

# Release download counts
echo "Downloads:"
gh api repos/paulhkang94/markview/releases --jq '.[] | "  \(.tag_name): \([.assets[].download_count] | add // 0) downloads"'
```

---

## Post-Launch Monitoring

After posting, check these URLs for engagement:

| Platform | Check URL |
|----------|-----------|
| HN | Search: https://hn.algolia.com/?q=markview |
| Reddit | Search your username's posts |
| GitHub | `bash scripts/check-traction.sh` |
| Cloudflare | https://dash.cloudflare.com → paulkang.dev → Analytics |

---

## Decision Tree

```
Post to HN + Reddit + Twitter (Tier 1)
        │
        ├── Gets traction (>50 stars in 48h)?
        │   ├── YES → Execute Tier 2 immediately, write Dev.to post
        │   └── NO  → Still do Tier 2, but space out over a week
        │
        └── After Tier 2
            ├── >100 stars? → Product Hunt + awesome-* PRs
            └── <100 stars? → Focus on content (blog posts, Swift Forums)
```
