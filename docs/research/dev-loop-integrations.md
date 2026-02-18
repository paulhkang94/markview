# Dev Loop Integrations Research

> Automating the Design -> Iterate -> Validate -> Loop cycle for MarkView
> Date: 2026-02-17

## Current State Summary

| Component | Status |
|-----------|--------|
| GitHub CI | 5 jobs (build, verify, bundle, MCP tests, golden drift) + 2 extended (fuzz, diff) |
| Sentry | Wired — crashes, errors, breadcrumbs, 10% trace sampling |
| Signing | Developer ID + notarization via `scripts/notarize.sh` |
| Test suite | 336 unit + fuzz + differential + E2E + visual regression (custom runner, no XCTest) |
| Release | Manual `scripts/release.sh` (bump, test, bundle, install) |
| Distribution | Direct .app install to /Applications, CLI via `~/.local/bin/mdpreview` |

---

## 1. Error -> Issue Automation (Sentry -> GitHub Issues)

### What it does
Sentry's [GitHub integration](https://docs.sentry.io/organization/integrations/source-code-mgmt/github/) can automatically create GitHub Issues when alert rules fire. You add a "Create a GitHub Issue" action to your Sentry alert rules, and each new error type gets a linked GitHub issue with stack trace, breadcrumbs, and suggested assignee (via CODEOWNERS).

### How to configure
1. In Sentry: Settings -> Integrations -> GitHub -> Install on `paulhkang94/markview`
2. Create an Alert Rule: "When a new issue is first seen" -> Action: "Create a GitHub Issue"
3. Optionally add conditions: e.g., only if seen > 3 times in 1 hour (reduces noise)
4. Bidirectional sync: closing the GitHub issue resolves it in Sentry, and vice versa

### Signal-to-noise ratio
- **Good for**: Crash-type errors, unhandled exceptions, new error types
- **Noisy for**: Transient network errors, expected edge cases
- **Mitigation**: Use "first seen" + count threshold (e.g., 3 occurrences) to filter noise. Set up fingerprint rules in Sentry to group related errors. Ignore specific error types in Sentry's inbound filters.
- For a single-developer macOS app with low error volume, noise should be minimal

### Assessment

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Fully supported — Sentry Cocoa SDK is already integrated |
| **Effort** | 30 minutes (Sentry dashboard config, no code changes) |
| **Value** | **High** — closes the error-to-fix loop automatically |
| **Recommendation** | **Do now** |

### Implementation steps
```
1. sentry.io -> Settings -> Integrations -> GitHub -> Add Installation
2. Select paulhkang94/markview repo
3. Alerts -> Create Alert Rule:
   - Condition: "A new issue is created"
   - Filter: "The issue's category is equal to Error" (skip performance)
   - Action: "Create a GitHub Issue in paulhkang94/markview"
4. Test by triggering a test error via SentrySDK.capture(message:)
```

---

## 2. Release Automation

### 2a. GitHub Releases on Version Tag

**What it does**: A GitHub Actions workflow triggered on `v*` tag push that creates a GitHub Release with the built .app bundle (as a .tar.gz or .dmg artifact).

**How it works with current setup**: `scripts/release.sh` already bumps version, tests, builds, and installs. The missing piece is: commit, tag, push -> auto-create GitHub Release with artifacts.

#### Workflow addition (`release.yml`)

```yaml
name: Release
on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: swift-actions/setup-swift@v2
        with: { swift-version: "6.2" }
      - name: Build release bundle
        run: bash scripts/bundle.sh --notarize
        env:
          NOTARIZE_KEY_ID: ${{ secrets.NOTARIZE_KEY_ID }}
          NOTARIZE_ISSUER_ID: ${{ secrets.NOTARIZE_ISSUER_ID }}
          # Key file written from secret in a prior step
      - name: Create tarball
        run: tar czf MarkView-${GITHUB_REF_NAME}.tar.gz MarkView.app
      - uses: softprops/action-gh-release@v2
        with:
          files: MarkView-${{ github.ref_name }}.tar.gz
          generate_release_notes: true
```

#### Sentry release tracking

Add `sentry-cli` to the release workflow to associate commits with the Sentry release:

```bash
sentry-cli releases new "$VERSION"
sentry-cli releases set-commits "$VERSION" --auto
sentry-cli releases finalize "$VERSION"
```

This makes Sentry show which commits are in each release and powers the "suspect commits" feature.

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Straightforward — builds on existing `bundle.sh` and `notarize.sh` |
| **Effort** | 2-3 hours (workflow + secrets setup + sentry-cli integration) |
| **Value** | **High** — automates artifact creation, enables reproducible releases |
| **Recommendation** | **Do now** |

### 2b. Sparkle Auto-Update Framework

**What it does**: [Sparkle](https://github.com/sparkle-project/Sparkle) is the standard macOS framework for in-app auto-updates. It checks an appcast XML feed for new versions, downloads, verifies signatures (EdDSA + code signing), and installs.

**SPM support**: Sparkle 2.x has native SPM support. Add to `Package.swift`:
```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
```

**What's involved**:
1. Add Sparkle dependency to Package.swift and the MarkView target
2. Generate an EdDSA keypair for update signing (`generate_keys` tool)
3. Create an appcast.xml feed (can be hosted on GitHub Pages or as a GitHub Release artifact)
4. Add `SUFeedURL` to Info.plist pointing to the appcast
5. Wire up `SPUStandardUpdaterController` in SwiftUI (5-10 lines)
6. Add "Check for Updates" menu item
7. On each release: sign the .app with EdDSA, update appcast.xml

**Is it worth it?**
- **Yes, eventually**: For a public-facing app, auto-update is table stakes. Users who install via .app bundle won't know about new versions otherwise.
- **Not yet**: While distribution is direct-install only and user base is small, the overhead of maintaining the appcast feed and signing keys isn't justified.
- **Prerequisite**: Automated GitHub Releases (2a) should come first — Sparkle's appcast can reference GitHub Release assets.

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Good — Sparkle 2 has SPM support, well-documented for SwiftUI |
| **Effort** | 4-6 hours (SPM dep, SwiftUI wiring, EdDSA keys, appcast hosting, release script changes) |
| **Value** | **High** (once distributing to users), **Low** (while personal-use only) |
| **Recommendation** | **Do later** — after public launch, when there are users to update |

---

## 3. Performance Monitoring

### Current state
Sentry tracing is enabled at 10% sample rate. No custom transactions are instrumented yet.

### Recommended transactions to instrument

| Transaction | How to measure | Why it matters |
|-------------|---------------|----------------|
| **App launch** | `SentrySDK.span` from `init()` to first `onAppear` | Users judge apps by launch speed; regression detection |
| **File open** | Span from `filePath` change to render complete | Core UX metric — how long until content is visible |
| **Render** | Span around `MarkdownRenderer.renderHTML()` | Catches perf regressions in the parser/renderer |
| **QL preview render** | Span in Quick Look extension `preparePreviewOfFile` | Quick Look has strict timeouts; slow renders = blank preview |
| **Export PDF/HTML** | Span around export operations | Users wait synchronously for these |

### Implementation pattern

```swift
// In MarkViewApp.init(), after SentrySDK.start:
let appLaunchSpan = SentrySDK.startTransaction(name: "app.launch", operation: "app.lifecycle")

// In ContentView.onAppear:
appLaunchSpan.finish()

// For file open:
let span = SentrySDK.startTransaction(name: "file.open", operation: "file.load")
// ... load and render ...
span.finish()
```

### Alerting on performance regressions

Sentry supports performance alerts: "When P95 of transaction X exceeds Y ms, alert." This is configurable in the Sentry dashboard.

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Fully supported — Sentry Cocoa SDK already has tracing enabled |
| **Effort** | 1-2 hours (add 4-5 spans in existing code + configure alerts) |
| **Value** | **Medium** — catches regressions before users complain |
| **Recommendation** | **Do now** — low effort, high signal |

---

## 4. Code Quality Gates

### 4a. SwiftLint in CI

**What it does**: Static analysis for Swift style and correctness issues.

**Current gap**: No linter in CI. Swift 6's strict concurrency checking covers some correctness, but not style.

**Implementation**: Add a SwiftLint step to the CI workflow:
```yaml
- name: SwiftLint
  run: |
    brew install swiftlint
    swiftlint lint --strict --reporter github-actions-logging
```

**Consideration**: SwiftLint can be slow to install via Homebrew in CI. Use the [lukka/run-cmake](https://github.com/realm/SwiftLint)-style caching or the pre-built binary.

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Easy — standard macOS CI tool |
| **Effort** | 1 hour (add CI step + create `.swiftlint.yml` config) |
| **Value** | **Medium** — consistency, catches common issues |
| **Recommendation** | **Do later** — Swift 6 strict concurrency is already a strong guardrail |

### 4b. Code Coverage with Custom Test Runner

**The challenge**: MarkView uses a custom `MarkViewTestRunner` executable, not XCTest. Standard `swift test --enable-code-coverage` won't work.

**Solution**: LLVM's source-based coverage works with any executable, not just XCTest. The Swift compiler can instrument any binary.

**Steps**:
1. Build with coverage flags:
   ```bash
   swift build -c debug \
     -Xswiftc -profile-generate \
     -Xswiftc -profile-coverage-mapping
   ```
2. Run the test runner — when it exits, it writes a `.profraw` file
3. Merge and export:
   ```bash
   xcrun llvm-profdata merge -sparse default.profraw -o coverage.profdata
   xcrun llvm-cov export .build/debug/MarkViewTestRunner \
     -instr-profile coverage.profdata \
     -format lcov > coverage.lcov
   ```
4. Upload to a service (Codecov, Coveralls) or generate HTML reports locally

**Caveat**: The `MarkViewTestRunner` tests `MarkViewCore`, not the full app. Coverage will reflect library code, not UI code. This is actually fine — UI code is covered by E2E and visual regression tests.

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Possible but requires custom build flags and post-processing |
| **Effort** | 3-4 hours (build flags, profdata pipeline, CI integration, coverage service) |
| **Value** | **Medium** — useful for identifying untested code paths |
| **Recommendation** | **Do later** — the existing test suite is comprehensive; coverage metrics would be informational, not gatekeeping |

### 4c. Dependabot for SPM Vulnerabilities

**What it does**: [Dependabot](https://docs.github.com/en/code-security/dependabot/dependabot-alerts) scans `Package.resolved` for known vulnerabilities and creates PRs to update.

**SPM support status**: GitHub added Dependabot support for Swift Package Manager. It works with `Package.swift` and `Package.resolved`.

**Setup**: Add `.github/dependabot.yml`:
```yaml
version: 2
updates:
  - package-ecosystem: "swift"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
```

**Current dependencies**: swift-cmark (Apple), swift-sdk (MCP), sentry-cocoa (Sentry). All are well-maintained with security response teams.

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Native GitHub feature, zero code changes |
| **Effort** | 10 minutes (add config file) |
| **Value** | **Medium** — security hygiene, catches transitive dependency issues |
| **Recommendation** | **Do now** — trivial to set up |

---

## 5. User Feedback Loop

### 5a. Sentry User Feedback Widget

**macOS support**: The Sentry Cocoa SDK [supports user feedback on macOS](https://docs.sentry.io/platforms/apple/guides/macos/user-feedback/). As of SDK 8.46+, there's a built-in widget that appears in the bottom corner of the screen.

**Configuration**:
```swift
SentrySDK.start { options in
    // ... existing config ...
    options.configureUserFeedback = { config in
        config.onFormOpen = { /* optional: pause file watcher */ }
        config.tags = ["app_version": Bundle.main.shortVersion]
    }
}
```

**Alternative — API-only approach**: If the widget UI doesn't fit the macOS native aesthetic, use `SentrySDK.capture(feedback:)` with your own SwiftUI sheet:
```swift
let feedback = SentryFeedback(message: userMessage, name: nil, email: nil)
SentrySDK.capture(feedback: feedback)
```

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Supported — Sentry macOS SDK has the feature |
| **Effort** | 1-2 hours (widget config) or 3-4 hours (custom SwiftUI form) |
| **Value** | **High** — direct user feedback closes the design loop |
| **Recommendation** | **Do later** — add when distributing to external users |

### 5b. Crash Report Dialog

**What it does**: Show a dialog after a crash on next launch, asking the user what they were doing.

**Implementation**: Sentry already captures crashes. On next launch, check `SentrySDK.crashedLastRun` and show a feedback prompt:
```swift
if SentrySDK.crashedLastRun {
    // Show "Sorry, we crashed. What were you doing?" dialog
    // Capture feedback attached to the crash event
}
```

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | `crashedLastRun` API exists in Sentry Cocoa SDK |
| **Effort** | 1-2 hours |
| **Value** | **Medium** — crash context is valuable but crashes should be rare |
| **Recommendation** | **Do later** — after user feedback infrastructure is in place |

---

## 6. Deployment Pipeline

### 6a. DMG Creation Automation

**What it does**: Create a polished `.dmg` with drag-to-Applications UI for distribution.

**Tools**:
- [`create-dmg`](https://github.com/create-dmg/create-dmg) (shell script, Homebrew-installable)
- [`sindresorhus/create-dmg`](https://github.com/sindresorhus/create-dmg) (Node.js)

**Integration with release workflow**:
```bash
create-dmg \
  --volname "MarkView" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "MarkView.app" 150 180 \
  --app-drop-link 450 180 \
  "MarkView-${VERSION}.dmg" \
  "MarkView.app"
```

**Note**: The DMG must also be notarized. `notarize.sh` currently handles .app — extend it to handle .dmg:
```bash
xcrun notarytool submit MarkView.dmg --wait ...
xcrun stapler staple MarkView.dmg
```

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Well-established tooling |
| **Effort** | 2-3 hours (script + CI integration + notarization for .dmg) |
| **Value** | **High** (for distribution), **Low** (while personal-use) |
| **Recommendation** | **Do later** — when preparing for public distribution |

### 6b. Homebrew Cask Formula

**What it does**: `brew install --cask markview` for easy installation.

**Requirements** (as of Homebrew 5.0, 2025):
- App MUST be codesigned with Developer ID (already done)
- App MUST be notarized (already supported via `--notarize`)
- App must be distributed via a stable URL (GitHub Releases work)
- Need a tap repository: `paulhkang94/homebrew-tap`

**Cask formula** (`markview.rb`):
```ruby
cask "markview" do
  version "1.1.1"
  sha256 "abc123..."

  url "https://github.com/paulhkang94/markview/releases/download/v#{version}/MarkView-v#{version}.dmg"
  name "MarkView"
  desc "Markdown previewer for macOS"
  homepage "https://github.com/paulhkang94/markview"

  app "MarkView.app"
end
```

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Fully supported — app is already signed + notarizable |
| **Effort** | 1-2 hours (create tap repo, write formula, test) |
| **Value** | **Medium** — developer-friendly distribution channel |
| **Recommendation** | **Do later** — after GitHub Releases + DMG automation are in place |

### 6c. Auto-Notarization in CI

**Current state**: `notarize.sh` works locally with App Store Connect API key. Needs secrets in CI.

**Required GitHub Secrets**:
- `NOTARIZE_KEY_ID` — API Key ID
- `NOTARIZE_ISSUER_ID` — Issuer ID
- `NOTARIZE_KEY_BASE64` — Base64-encoded .p8 key file

**CI step** (decode key, then run notarize):
```yaml
- name: Decode notarization key
  run: |
    mkdir -p ~/.private_keys
    echo "${{ secrets.NOTARIZE_KEY_BASE64 }}" | base64 -d > ~/.private_keys/AuthKey_${{ secrets.NOTARIZE_KEY_ID }}.p8
  env:
    NOTARIZE_KEY_ID: ${{ secrets.NOTARIZE_KEY_ID }}
- name: Notarize
  run: bash scripts/notarize.sh MarkView.app
  env:
    NOTARIZE_KEY_ID: ${{ secrets.NOTARIZE_KEY_ID }}
    NOTARIZE_ISSUER_ID: ${{ secrets.NOTARIZE_ISSUER_ID }}
```

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Fully supported — `notarize.sh` already uses `notarytool` with API key auth |
| **Effort** | 1 hour (upload secrets, add CI steps) |
| **Value** | **High** — eliminates manual notarization step from releases |
| **Recommendation** | **Do now** — pairs with release automation (2a) |

---

## 7. Monitoring & Alerting

### 7a. Sentry Alerts -> Slack/Email

**Setup**: Sentry supports email alerts out of the box (enabled by default). For Slack:
1. Sentry -> Settings -> Integrations -> Slack -> Install
2. Alert Rule -> Action: "Send a Slack notification to #markview-alerts"

**Recommended alert rules**:
- **New issue first seen**: Email immediately (already default)
- **Issue regression** (resolved issue reappears): Email immediately
- **Error spike**: > 10 events in 1 hour -> alert
- **Performance regression**: P95 of `file.open` > 500ms -> alert

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Built-in Sentry feature |
| **Effort** | 15 minutes (dashboard config) |
| **Value** | **High** — immediate awareness of production issues |
| **Recommendation** | **Do now** |

### 7b. GitHub Actions Failure Notifications

**Current state**: GitHub sends email on workflow failure by default if you have notifications enabled.

**Enhancement options**:
- Slack notification on CI failure via `slackapi/slack-github-action`
- Branch protection requiring all CI jobs to pass before merge (likely already in place)

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | Built-in GitHub feature |
| **Effort** | 10 minutes (verify notification settings) |
| **Value** | **Low** — likely already working via GitHub email notifications |
| **Recommendation** | **Skip** — default notifications are sufficient for solo dev |

### 7c. MCP Server Uptime Monitoring

**Current state**: MCP server is a local stdio process, not a deployed service. It runs on the user's machine, launched by the AI client (Claude, etc.).

**Assessment**: Uptime monitoring is not applicable for a local stdio server. If the MCP server were deployed as a network service, monitoring would matter — but that's not the current architecture.

| Dimension | Rating |
|-----------|--------|
| **Feasibility** | N/A — local process, not a service |
| **Effort** | N/A |
| **Value** | **None** for current architecture |
| **Recommendation** | **Skip** |

---

## Priority Matrix

### Do Now (this week)

| Integration | Effort | Impact |
|-------------|--------|--------|
| Sentry -> GitHub Issues alert rule | 30 min | Errors auto-create trackable issues |
| Dependabot for SPM | 10 min | Automated vulnerability scanning |
| Sentry performance spans (4-5 transactions) | 1-2 hrs | Regression detection for core UX |
| Sentry alert rules (email) | 15 min | Immediate awareness of production issues |
| Auto-notarization in CI (secrets setup) | 1 hr | Unblocks automated releases |
| GitHub Release workflow (`release.yml`) | 2-3 hrs | Reproducible, artifact-bearing releases |

**Total: ~5-7 hours**

### Do Later (before public launch)

| Integration | Effort | Depends On |
|-------------|--------|------------|
| Sparkle auto-update | 4-6 hrs | GitHub Releases |
| DMG creation automation | 2-3 hrs | Release workflow |
| Homebrew cask formula | 1-2 hrs | DMG + notarization |
| Sentry user feedback (widget or custom) | 2-4 hrs | -- |
| Crash report dialog | 1-2 hrs | User feedback |
| SwiftLint in CI | 1 hr | -- |
| Code coverage pipeline | 3-4 hrs | -- |

### Skip

| Integration | Reason |
|-------------|--------|
| GitHub Actions Slack notifications | Email notifications sufficient for solo dev |
| MCP server uptime monitoring | Local stdio process, not a deployed service |

---

## The Automated Loop (Target State)

```
  User opens file, uses app
           |
           v
  Sentry captures: errors, performance, crashes
           |
           v
  Alert rules fire: email + auto-create GitHub Issue
           |
           v
  Developer fixes issue, pushes to main
           |
           v
  CI runs: build + 336 tests + verify + golden drift + SwiftLint
           |
           v
  Push version tag (v1.2.3)
           |
           v
  Release workflow: build -> notarize -> create GitHub Release
           |                                     |
           v                                     v
  Sentry release tracking            DMG artifact attached
  (commits associated)               Sparkle appcast updated
           |                                     |
           v                                     v
  Users auto-update via Sparkle       brew upgrade markview
           |
           v
  Sentry monitors new release for regressions
           |
           v
  Loop back to top
```
