# MarkView — Session Resume (2026-04-04)

Use this file to resume the next session. Start with `/catchup` then paste the Resume Prompt below.

---

## Resume Prompt

```
/catchup

Context: We just finished a major MarkView session covering Playwright Tier 5
infrastructure, Mermaid diagram controls (pan/zoom/copy/reset), SVG icons,
responsive clamp() sizing, scroll fix, image regression tests, and PHK debug
logging. Full plan exists for find/search and v1.4.0 (diff viewer, etc.).

Read first:
- /Users/pkang/repos/markview/docs/STATUS.md     ← living architecture doc
- /Users/pkang/repos/markview/SESSION-RESUME.md  ← this file

Current state:
- v1.3.0 live. 350 tests (284 Swift + 66 Playwright). All CI green.
- Diagram controls shipped: pan/zoom/copy/reset, SVG icons, responsive clamp()
- Find/search: PLAN COMPLETE (see below), NOT YET IMPLEMENTED — start here
- v1.4.0 features: diff viewer, show_changed_files, stream_markdown — planned

PRIORITY ORDER for this session:
1. Implement find/search (plan fully vetted, ready to code)
2. Continue v1.4.0: diff2html bundle, render_diff + show_changed_files MCP tools
3. SVG icon quality review (open diagrams, check all 8 icons look right)
```

---

## Prioritized Action Items

### P0 — Implement Find/Search (plan complete, ~1 day)

Full plan approved. Architecture: native SwiftUI find bar overlay at bottom
of preview pane, using `WKWebView.find()` (macOS 14+) for highlighting +
JS for match count.

**New files:**
- `Sources/MarkView/FindBarView.swift` — SwiftUI find bar (TextField, count, Aa toggle, next/prev, close)

**Modified files:**
- `Sources/MarkView/ContentView.swift` — ZStack overlay at bottom, @State find props, Notification receivers
- `Sources/MarkView/WebPreviewView.swift` — Coordinator receives notifications, calls `webView.find()` + JS count
- `Sources/MarkView/MarkViewApp.swift` — rewire existing Find CommandGroup, new Notification names
- `Sources/MarkView/Strings.swift` — find bar labels
- `Tests/E2ETester/main.swift` — 8 E2E test cases

**Key design decisions:**
- Find bar: `[ 🔍 ] [ Find... ] [ 3 of 12 ] [ Aa ] [ < ] [ > ] [ ✕ ]`
- Position: BOTTOM of preview (Chrome/Firefox/VS Code convention)
- Animation: slide up from bottom, 0.2s ease, `.regularMaterial` background
- Keyboard: Cmd+F open, Esc close, Cmd+G next, Shift+Cmd+G prev
- Match count: `WKFindResult.matchFound` (Bool only) + JS `innerText.match(/regex/gi).length`
- Works identically in preview-only AND split-pane modes
- StatusBar bottom padding: add `.padding(.bottom, showFindBar ? 36 : 0)` animated
- V1 EXCLUDES: find+replace, regex mode, whole-word, highlight-all

**Implementation order:**
1. Notification names in MarkViewApp.swift (no behavior change)
2. FindBarView.swift (new file, no wiring yet)
3. Coordinator notification observers in WebPreviewView.swift
4. @State + overlay in ContentView.swift
5. Rewire Find CommandGroup in MarkViewApp.swift
6. Strings.swift additions
7. StatusBar bottom padding
8. E2ETester tests

**Tricky parts:**
- `webView.find("")` to clear highlights (undocumented but works)
- Esc key: if TextField has focus, SwiftUI fires .onKeyPress before global menu command → natural priority
- WKWebView may intercept Cmd+F on some macOS versions — CommandGroup replacement takes priority
- Current match index: WKFindResult has no index; track locally with incrementing counter

---

### P0 — v1.4.0: diff2html MCP Tools (~1.5 days)

Full plan exists (from plan agent, 2026-04-04 session). Key warnings:
- `test-mcp.sh` line 140 asserts `exactly 3 tools` — **must update to 6** when adding new tools
- All 5 Playwright fixture HTMLs will grow ~100KB (diff2html bundle) — need regeneration

**Step 1: Download diff2html bundle (already extracted to /tmp/package/)**
```bash
# Bundle already downloaded:
ls /tmp/package/bundles/js/diff2html.min.js  # 77KB
ls /tmp/package/bundles/css/diff2html.min.css  # 17KB
# Copy to resources:
cp /tmp/package/bundles/js/diff2html.min.js ~/repos/markview/Sources/MarkViewCore/Resources/
# Combine CSS into JS as const (injected via <style> tag):
node -e "const css = require('fs').readFileSync('/tmp/package/bundles/css/diff2html.min.css','utf8'); const js = require('fs').readFileSync('/tmp/package/bundles/js/diff2html.min.js','utf8'); require('fs').writeFileSync('Sources/MarkViewCore/Resources/diff2html.min.js', 'const __diff2htmlCSS=' + JSON.stringify(css) + ';\n' + js);"
```

**Step 2: Package.swift** — add `.process("Resources/diff2html.min.js"),`

**Step 3: HTMLPipeline.swift** — add `diff2htmlJS: String?` property, `injectDiff2HTML()` method, update `assemble()` and `loadFromBundle()`

**Step 4: New MCP tools in main.swift:**
- `render_diff` — params: `path` (runs git diff) OR `diff` (raw unified diff), `format` (side-by-side|line-by-line)
- `show_changed_files` — params: `path` (repo dir), runs git status --porcelain
- `preview_markdown` update — add `append: Bool` param for streaming support

**Step 5: tests, fixtures, version bump to 1.4.0**

---

### P1 — Diagram Controls Visual QA

Open MarkView with golden-corpus.md and verify all 8 SVG icons render correctly:
- ↑↓←→ arrows (filled triangles)
- ↺ reset (circular arc with arrowhead)
- ＋ zoom in (filled plus cross)
- － zoom out (filled minus bar)
- ⎘ copy (two overlapping rectangles)
- ✓ copy feedback (stroke checkmark, replaces copy icon after click)

Check at: normal window size, split-pane, full-screen.
Controls should scale from 32px (normal) to 42px (full screen) via clamp().

---

### P1 — Infra Swarm Results (write to docs)

The paulkang-dev + markview infra inventory agent hit write restrictions.
Key findings inline (not written to file):
- markview's standalone test runner pattern (no XCTest) is reusable
- paulkang-dev's `?freeze` Playwright pattern (disable animations for deterministic snapshots)
- 12-step markview release automation is extractable template

**TODO:** Dispatch a `general-purpose` agent (not `Explore`) to write this to:
`~/repos/docs/research/infra-inventory-markview-paulkangdev.md`

---

### P2 — LOOP Template Sync

After the learnings agents complete (running in background), sync the generalized
LOOP template with the patterns from this session:
- Per-repo verify stamp paths (two separate gates)
- Auto-install after playwright passes pattern
- Render-verify gate (pre-commit hook with stamp)

---

### P3 — iOS + Android Apps

Update iOS and Android apps based on latest MarkView feature state.
Note in memory: `project-markview-mobile.md`

---

## Session Commits (2026-04-04)

| Hash | Description |
|------|-------------|
| `b3c9e49` | feat(test): Playwright DOM tests (Tier 5) + render-verify gate |
| `8b6b910` | fix(debug+ci): PHK debug logs + stale-release.yml YAML fix |
| `4cacbcc` | fix(fixtures): correct image paths in golden-corpus.md |
| `8bd0f6a` | refactor(images): inlineLocalImages → MarkViewCore + 4 regression tests |
| `bfe41a1` | feat(mermaid): diagram pan/zoom/copy controls (GitHub parity) |
| `0639e8b` | chore(workflow): auto-install after playwright passes |
| `dda7fbd` | fix(mermaid-controls): responsive sizing per SOTA research |
| `ca1b0d8` | fix(mermaid-controls): plain scroll passes through |
| `ce6e74c` | fix(mermaid-controls): clamp() responsive + ↺ reset icon |
| `c4472dc` | feat(mermaid-controls): SVG icons replacing Unicode |

---

## Key Infrastructure Notes

### Verify Stamp Paths (two different files!)
- **Commit-gate** (claude-loop): `~/repos/claude-loop/.claude/memory/.last-verify-at`
- **Render-verify** (markview pre-commit): `~/repos/markview/.last-render-verify-at`

To stamp both manually after running tests:
```bash
date +%s > ~/repos/markview/.last-render-verify-at
date +%s > ~/repos/claude-loop/.claude/memory/.last-verify-at
```

### Playwright Fixtures Must Be Rebuilt After HTMLPipeline Changes
```bash
# WRONG (uses stale release binary):
bash scripts/gen-playwright-fixtures.sh --no-build

# CORRECT after any HTMLPipeline.swift change:
swift build -c release --product MarkViewHTMLGen
bash scripts/gen-playwright-fixtures.sh --no-build
```

### PHK Debug Logging
- Swift side: `PHK_DEBUG=1 swift run MarkViewHTMLGen input.md`
- JS side: `page.evaluate(() => window._PHK_DEBUG = true)` before setContent
- Logs: `[PHK] loadFromBundle() done — prism:true mermaid:true katex:true`
- Mermaid: `[PHK] mermaid.run() resolved — rendered=true (path: mermaid.then)`
- Controls: `[PHK] mermaid controls: adding to N diagrams`

### Auto-Install
`make playwright` now rebuilds + installs MarkView.app after tests pass.

### Test Count
- Swift: 284 (`swift run MarkViewTestRunner`)
- Playwright: 66 (`cd Tests/playwright && npx playwright test --project=chromium`)
- Total: 350

---

## Find/Search Research Summary (for implementation session)

**WKWebView.find() API (macOS 14+):**
- `WKWebView.find(_:configuration:completionHandler:)` — highlights match, scrolls to it
- `WKFindConfiguration` — `backwards`, `caseSensitive`, `wraps`
- `WKFindResult` — only `matchFound: Bool` (NO count, NO index)

**Match count (JS workaround):**
```swift
let js = """
(function() {
    var text = document.body.innerText;
    var regex = new RegExp(escapeRegex(query), caseSensitive ? 'g' : 'gi');
    return (text.match(regex) || []).length;
})()
"""
webView.evaluateJavaScript(js) { count, _ in ... }
```

**Clear highlights:**
```swift
// Undocumented but works:
webView.find("", configuration: WKFindConfiguration()) { _ in }
```

**Notification names to add in MarkViewApp.swift:**
```swift
static let openFindBar = Notification.Name("openFindBar")
static let performFind = Notification.Name("performFind")
static let clearFind = Notification.Name("clearFind")
static let findResultUpdated = Notification.Name("findResultUpdated")
```

---

## v1.4.0 Diff Viewer Key Notes

**diff2html bundle location:** `/tmp/package/bundles/` (downloaded this session)
- `/tmp/package/bundles/js/diff2html.min.js` (77KB)
- `/tmp/package/bundles/css/diff2html.min.css` (17KB)
- COMBINE into single resource file with CSS as JS const

**Critical:** `test-mcp.sh` line 140 asserts `exactly 3 tools` — update to 6!

**diff2html injection pattern (mirrors injectMermaid):**
- Detect `pre code.language-diff` blocks
- Parse with `Diff2Html.parse(diffStr)`
- Replace with `Diff2Html.html(diff, {outputFormat: 'side-by-side', drawFileList: false})`
- Add `<div class="d2h-wrapper">` container

**`render_diff` MCP tool:**
```swift
// Parameters: path (runs git diff) OR diff (raw string)
// git diff via Process+Pipe: new pattern — first time subprocess captures stdout
// Wraps result in ```diff\n...\n``` markdown, writes to cache, opens MarkView
```

**`show_changed_files` MCP tool:**
```swift
// git -C path status --porcelain --short
// Parse: XY filename (X=staged, Y=unstaged, M/A/D/?/R)
// Output: markdown with HTML table, status badges, file emoji icons
// No new JS needed — cmark-gfm passes HTML through
```
