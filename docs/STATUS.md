# MarkView — Status & Architecture Reference

Living document. Updated each session. Source of truth for current state,
pending work, and key architectural decisions.

---

## Current Release

| | |
|---|---|
| **App version** | v1.7.0 (build 323) - latest released |
| **npm package** | mcp-server-markview v1.7.0 (published 2026-07-06) |
| **BINARY_VERSION** | 1.7.0 (synced) |
| **Homebrew cask** | 1.7.0 (`paulhkang94/markview/markview`) |
| **MCP registry** | `io.github.paulhkang94/markview` v1.7.0 - active |
| **Tag** | `v1.7.0` pushed 2026-07-06 |

### Releases since the 2026-05-07 refresh

- **v1.4.3** (2026-05-07), **v1.5.0** (2026-05-08), **v1.6.0** + **v1.6.1** (2026-07-04), **v1.7.0** (2026-07-06).
- Headline changes: tab system (MV-001 restore-all-tabs, MV-002 renderComplete, MV-003/MV-005 per-tab scroll restore, MV-007 ⌘T untitled tabs, MV-009 ⌃Tab cycling), release scripts → Python, npm OIDC trusted publishing + automatic MCP registry publish, dSYM upload to Sentry (v1.7.0 is the first release with symbolicated crash/hang reports).
- **Open issues**: 6 (as of 2026-07-13) - 5 are Sentry-auto-filed "App Hanging ≥2000 ms" reports (#30, #45-#48); triage + first fix: `docs/personal/item-713-hang-triage-2026-07-13.md`, branch `fix/item-713-js-bundle-cache`. The 6th is enhancement #26 (remember window position).

> **BINARY_VERSION contract**: `postinstall.js` BINARY_VERSION points to the last
> successfully notarized GitHub Release binary. npm patches (JS wrapper changes) do
> NOT bump BINARY_VERSION. App releases ALWAYS bump it: `release.sh --bump` updates
> it with the other five version files (the old opt-in `--bump-binary` flag is how
> the 1.6.0 stale-pin incident happened and was removed). Gates:
> `check_version_sync.py` (staleness, PR guard), `check_version_sync.py --expect-tag`
> (release.yml + preflight), `npm_publish_gate.py` (npm-publish.yml).

### v1.4.2 Changes (2026-04-08)
- **KaTeX fix**: Removed `$...$` inline delimiter — was garbling financial prose (`$10,000`). Kept `$$...$$`, `\(...\)`, `\[...\]`.
- **math.md fixture fix**: `\(...\)` and `\[...\]` examples now use raw HTML blocks to survive cmark-gfm backslash escape processing.
- **Regression test**: `katex.spec.ts` now asserts `$10,000` and `$500` render as plain text.
- **Stamp SSOT**: Consolidated `.last-render-verify-at` + `.last-verify-at` → single `.last-verify-at`. All gates read the same file.
- **Tracked pre-commit hook**: `scripts/pre-commit-hook.sh` committed as SSOT. `.git/hooks/pre-commit` is a thin shim.
- **Version sync**: Added `npm/server.json` as a 5th version file to `release.sh` and `check-version-sync.sh`.
- **Binary+npm re-sync**: Binary had drifted to 1.4.0, npm to 1.4.1. Both now at 1.4.2.

---

## Feature Set (v1.7.0)

### Rendering
| Feature | Status | Notes |
|---------|--------|-------|
| GitHub Flavored Markdown | ✅ | cmark-gfm, all extensions |
| Syntax highlighting | ✅ | Prism.js, 18+ languages |
| Mermaid diagrams | ✅ | 6 types: flowchart, sequence, class, Gantt, ER, pie — pan/zoom/reset/copy controls |
| KaTeX math | ✅ | `$$...$$`, `\(...\)`, `\[...\]`, MathML output. `$...$` removed (conflicts with financial prose) |
| GFM alerts (`> [!NOTE]`) | ✅ | All 5 types, dark mode, handles GitHub-standard format |
| TOC sidebar | ✅ | h1–h4, scroll-spy, ≥3 headings threshold |
| Quick Look (Finder spacebar) | ✅ | Full rendering pipeline |
| PDF / HTML export | ✅ | Via print dialog |
| Find & Replace in editor | ✅ | Cmd+F/H |
| Find in preview | ✅ | Cmd+F in preview pane |

### MCP Server (9 tools)
| Tool | Description |
|------|-------------|
| `preview_markdown` | Render content in native window |
| `open_file` | Open .md file with live reload |
| `lint_file` | 9-rule linter, returns line diagnostics |
| `lint_content` | Lint raw markdown string (no file path required) |
| `render_diff_file` | Run git diff on a repo and render with diff2html |
| `render_diff_raw` | Render raw unified diff string with diff2html |
| `get_changed_files` | List changed files in a git repo (staged/unstaged/untracked) |
| `get_word_count` | Return word/char/line counts for a markdown string or file |
| `outline` | Extract heading outline (TOC) from markdown content |
| **Resources** | `markview://preview/latest` — read back rendered content |

### App
| Feature | Status |
|---------|--------|
| Split-pane editor | ✅ |
| File watching (atomic save) | ✅ |
| Find & Replace | ✅ |
| Word count / stats | ✅ |
| CLI (`markview file.md`) | ✅ `scripts/markview-cli.sh` |
| Dark mode (system + manual) | ✅ |

---

## Test Pyramid

```
Tier 1 — Swift unit tests (cmark-gfm output)          294 tests  SPM, fast
Tier 2 — Golden HTML body snapshots                    8 fixtures  git-committed
Tier 3 — Full-pipeline structural tests (HTMLPipeline) 9 tests    extracted for testability Apr 2026
Tier 4 — MCP protocol tests (JSON-RPC)                91 tests   --skip-e2e in CI (covers 9 tools)
Tier 5 — Playwright DOM tests (post-JS DOM state)     154 tests   `make playwright`, Chromium
          alerts (7), mermaid (19), katex (6+), prism (5), controls (35), other (+)
Tier 2b — Script unit tests (metrics.py + check_traction) 19 tests  python3 scripts/test-metrics.py, no live API

MISSING (planned):
Tier 6 — DOM snapshot goldens (rendered/*.dom.json)    0 files    Step 2 below
```

**Critical gap closed Apr 4 2026**: `HTMLPipeline.swift` extracted from
`WebPreviewView.swift` (AppKit) into `MarkViewCore` (SPM-testable). The injection
pipeline (`injectPrism` → `injectMermaid` → `injectKaTeX`) is now unit-testable.
Previously 413 tests passed while the app rendered broken output.

**KaTeX delimiter fix Apr 8 2026**: `$...$` delimiter removed from auto-render config — conflicts with financial prose. cmark-gfm backslash escape processing destroys `\(...\)` in markdown source; fixture now uses raw HTML blocks. Playwright regression test added for `$10,000` plain-text assertion.

**Root cause of Apr 4 bugs (both missed by tests):**
1. `mermaid.min.js` bundles DOMPurify which contains `</body>` as a JS string literal.
   `replacingOccurrences(of: "</body>", ...)` replaced ALL occurrences → JS source
   rendered as visible text. Fix: `insertBeforeBodyClose` uses `.backwards` search.
2. GFM alerts JS regex `^\[!NOTE\]$` required the ENTIRE paragraph = just the marker.
   cmark-gfm puts content on the same line → alerts always showed as plain blockquotes.
   Fix: match at start, strip marker prefix from innerHTML.

---

## Pending Work: Testing Infrastructure

### Step 1 — Playwright fixture tests for client-side transforms ✅ DONE (2026-04-04)
```
tests/
  alerts.spec.js     — 7 tests: .alert-note exists, no raw [!NOTE] text
  mermaid.spec.js    — 19 tests: svg present, no JS source, pan/zoom/reset/copy controls
  katex.spec.js      — 5 tests: <math> elements or .katex spans present
  prism.spec.js      — 5 tests: .token spans in code blocks
  controls.spec.js   — 35 tests: diagram pan/zoom/reset/copy button behavior
```
66 Playwright tests total. `window.rendered` sentinel guards all async assertions.
Both Apr 4 bugs (mermaid injection, alert regex) would have been caught immediately.

### Step 2 — DOM snapshot goldens (P1, 1 day)
```
Tests/rendered/*.dom.json   — normalized DOM after JS execution
```
Committed to git. CI fails on unexpected structural diff.
Catches regressions that behavioral assertions miss.

### Step 3 — PostToolUse hook: render-verify gate (P2, 2 hours)
Extend `commit-gate.sh` with `.last-render-verify-at` stamp.
Any write to `template.html`, `WebPreviewView.swift`, or `*.min.js` resets it.
Gate blocks until Playwright render-verify runs clean.

### Step 4 — CL fingerprint for JS injection layer (P2, 1 hour)
Pattern: `template\.html|WebPreviewView\.swift|\.min\.js` → `render-verify-required`
Surfaces as cl-check warning on next tool call after edit.

### Step 5 — `make rendered` regeneration command (P3, 30 min)
Single command to update all DOM snapshots. Text-diffable in PRs.

---

## CI Architecture

### Hermetic vs Environment-Dependent (key design principle)

**Hermetic jobs** (run in any environment, no credentials, no installed artifacts):
- `build` — swift build + swift run MarkViewTestRunner
- `golden-check` — regenerate goldens, git diff
- `docs-audit` — shell script, ubuntu-latest

**Environment-dependent jobs** (require specific environment):
- `verify` — needs full git history (`fetch-depth: 0`) for tag checks
- `bundle` — needs Xcode signing certificate (GitHub Secret)
- `mcp` — needs to build the MCP binary
- `visual-smoke` — needs display context (advisory, `continue-on-error: true`)

**Rule**: Never mix hermetic and environment-dependent checks in the same job.
`verify.sh` originally mixed both → every push emailed a failure.

### Known CI Issues (resolved)

| Issue | Root cause | Fix | Status |
|-------|-----------|-----|--------|
| Verify fails every push | `fetch-tags:true` insufficient with shallow clone | `fetch-depth:0` | ✅ Fixed `5d5d33d` |
| stale-release.yml YAML error | Backtick JS template literals in YAML | Rewrite with gh CLI | ✅ Fixed `be6a83d` |
| MCP Tests: isError on CI | `preview_markdown` returned error when app not installed | Return success, add note | ✅ Fixed `be2bff7` |
| release.sh BINARY_VERSION not updated | Sed pattern `const VERSION` vs `const BINARY_VERSION` | Add `--bump-binary` flag | ✅ Fixed `71cccf5` |
| Verify mktemp template | `.md` before `XXXXX` suffix invalid on macOS | Use `$(mktemp ...)".md"` | ✅ Fixed |

### Notification policy
- GitHub Actions → "On GitHub, failed workflows only" (set by user Apr 4 2026)
- With hermetic/env separation, only genuine new bugs generate notifications

---

## Distribution Channels

| Channel | Status | Notes |
|---------|--------|-------|
| GitHub releases | ✅ | v1.7.0 latest (2026-07-06) |
| Homebrew cask | ✅ | `paulhkang94/markview/markview` v1.7.0 |
| npm | ✅ | mcp-server-markview v1.7.0 (OIDC trusted publishing since v1.6.1) |
| Official MCP registry | ✅ | `io.github.paulhkang94/markview` v1.7.0 (auto-published from npm-publish.yml) |
| Cloudflare Worker (`markview-mcp`) | ✅ | `workers/mcp/` - remote MCP Streamable HTTP endpoint, capability-listing mode only (tool calls return a "native macOS app" pointer). Built for Smithery/remote listing; deploys via `worker-deploy.yml` |
| awesome-mcp-servers | ✅ | PR #2139 merged 2026-03-14 |
| Glama.ai | ✅ | Listed |
| mcp.so | ⏳ | Submitted |
| Smithery | ⚠️ | Exists but `isDeployed: null` - Linux sandbox can't install npm pkg |

---

## Adoption Metrics

Run `bash scripts/metrics.sh` for current snapshot.

Last snapshot: 2026-07-13
- GitHub stars: **35** | Forks: 3 | Open issues: 6
- npm downloads: **3,833 all-time** | 1,317 last 30d | 421 last 7d (13.6x the May 7 weekly rate)
- Release-day spike: 553 npm downloads on 2026-07-04 (all-time single-day record)
- Organic baseline (non-release weeks): ~10-20/day, up from the 4-6/day May floor
- Top referrer: reddit.com
- Watch flag: 5 of 6 open issues are duplicate Sentry "App Hanging" reports filed around the Jul 4-6 releases (item-713 triage)
- Full analysis: `~/repos/docs/research/markview-adoption-metrics-2026-07-13.md`

Previous snapshot: 2026-05-07
- Stars: 26 | npm: 2,107 all-time | Organic: 4-6/day | Open issues: 3
- Full analysis: `~/repos/docs/research/markview-adoption-metrics-2026-05-07.md`

---

## Mobile (iOS + Android)

> Full state and blockers: **[docs/MOBILE.md](MOBILE.md)**

| Platform | Version | State | Key Blocker |
|----------|---------|-------|-------------|
| iOS | v1.0.0/build 2 | Functional on real iPad | Distribution cert + XCUITest suite |
| Android | v1.0.0/build 2 | Functional on Galaxy S25 Ultra | Play identity verification (pending) |

**Decision (2026-04-11): SHIP to both stores.** Android first.
See MOBILE.md for per-platform blocker lists and release plan.

---

## Key Files

| File | Purpose |
|------|---------|
| `Sources/MarkViewCore/HTMLPipeline.swift` | Injection pipeline (extracted for testability Apr 2026) |
| `Sources/MarkViewHTMLGen/main.swift` | CLI fixture generator for Playwright tests |
| `tests/` | Playwright e2e test suite (Node.js, Chromium, 66 tests) |
| `Sources/MarkViewCore/MarkdownRenderer.swift` | cmark-gfm wrapper |
| `Sources/MarkViewCore/MarkdownLinter.swift` | 9-rule linter |
| `Sources/MarkViewCore/Resources/template.html` | HTML template: CSS, alert/TOC JS |
| `Sources/MarkViewMCPServer/main.swift` | MCP server: 3 tools + resources endpoint |
| `Tests/TestRunner/Fixtures/golden-corpus.md` | Visual QA fixture — all features |
| `scripts/metrics.sh` | Unified traction tracking |
| `scripts/release.sh` | Release automation (`--ship` flag; always bumps all 6 version files) |
| `scripts/check-version-sync.sh` | Version contract verification |
| `docs/personal/` | Strategy, adoption, competitive docs (gitignored) |
