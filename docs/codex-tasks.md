# MarkView — Codex-Assignable Tasks

Tasks suitable for OpenAI Codex agents. Each includes context, acceptance criteria, and verification steps.

## Setup Context

MarkView is a native macOS markdown previewer (SwiftUI + WebKit) with an MCP server, Quick Look extension, npm package, and Homebrew tap. Build: `swift build`. Test: `swift run MarkViewTestRunner` (276 tests). Full verify: `bash verify.sh`.

---

## Trivial / Small Tasks

### mar-004: GitHub Actions secrets for CI notarization
Add repository secrets (`NOTARIZE_KEY_ID`, `NOTARIZE_ISSUER_ID`, `APPLE_CERT_BASE64`, `APPLE_CERT_PASSWORD`) to the GitHub Actions workflow so CI can notarize release builds.

**Files:** `.github/workflows/release.yml`
**Verify:** `gh secret list` shows all 4 secrets configured. Workflow reference matches secret names.

---

### mar-009: Submit MarkView MCP to PulseMCP
Submit the MCP server to PulseMCP registry. Follow their submission process at https://pulsemcp.com.

**Files:** None (external submission)
**Verify:** Listing appears on PulseMCP search results.

---

### mar-010: PR to modelcontextprotocol/servers
Create a PR adding MarkView to the official MCP servers repository at https://github.com/modelcontextprotocol/servers.

**Files:** Fork + PR to external repo. Follow their CONTRIBUTING.md format.
**Verify:** PR opened, CI passes on their repo.

---

### mar-014: Double-click title bar toggles fullscreen
Double-clicking the title bar should toggle between fullscreen and the original dynamic window size.

**Files:** `MarkView/AppDelegate.swift` or `MarkView/ContentView.swift`
**Verify:** `swift build` succeeds. Manual test: double-click title bar toggles fullscreen. `bash verify.sh` passes.

---

### mar-006: Register MarkView MCP on official registry
Register the MCP server on the official MCP registry (if one exists beyond modelcontextprotocol/servers).

**Files:** External registration
**Verify:** MCP server discoverable via registry search.

---

## Medium Tasks

### mar-013: Multi-window/tab support
Investigate and implement multi-window or tab support so users can preview multiple markdown files simultaneously.

**Files:** `MarkView/AppDelegate.swift`, `MarkView/ContentView.swift`, potentially new `WindowManager.swift`
**Acceptance:** Opening a second file creates a new window/tab instead of replacing the current preview. Each window tracks its own file. Window state persists across app restarts.
**Verify:** `bash verify.sh` passes. Manual test: open 2+ files, each in its own window.

---

### mar-011: Enable App Sandbox
Enable App Sandbox entitlement for Mac App Store compatibility. MarkView needs read access to user-selected files and network access for MCP.

**Files:** `MarkView/MarkView.entitlements`, `project.yml`
**Acceptance:** App runs correctly with sandbox enabled. File access works via Open dialog and drag-and-drop. MCP server still functions.
**Verify:** `codesign -d --entitlements :- MarkView.app` shows sandbox entitlement. `bash verify.sh` passes. App opens files correctly.

---

### mar-012: Mac App Store submission prep
Prepare MarkView for Mac App Store submission: App Store Connect metadata, screenshots, privacy policy, category selection.

**Files:** `MarkView/Info.plist`, screenshots, App Store Connect configuration
**Acceptance:** All required metadata filled in App Store Connect. Screenshots for required display sizes. Privacy policy URL configured.
**Verify:** App Store Connect shows "Ready for Review" status.

---

### mar-003: Visual regression testing
Set up Playwright-based visual regression testing for the rendered markdown output.

**Files:** New `tests/visual/` directory, `playwright.config.ts`, baseline screenshots
**Acceptance:** Tests capture screenshots of rendered markdown and compare against baselines. CI runs visual regression on PRs. Baseline update mechanism exists.
**Verify:** `npx playwright test` passes with baseline screenshots. Intentional CSS change triggers a visual diff.
