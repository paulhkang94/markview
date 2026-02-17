# E2E & Performance Testing Approaches for MarkView

**Date:** 2026-02-16
**Scope:** Measure scroll sync latency between NSTextView editor and WKWebView preview, test single/double pane layouts, measure FPS/frame drops.

---

## Approach Analysis

### 1. Playwright

**What it can do:**
- Test web content rendered inside a standalone WebKit browser engine
- Excellent for pure web app E2E testing

**What it cannot do for MarkView:**
- Cannot attach to a WKWebView embedded inside a native macOS app. Playwright drives its own bundled browser instances; it has no mechanism to connect to an in-process WKWebView.
- Cannot interact with NSTextView or any native AppKit/SwiftUI controls
- Cannot measure cross-pane latency (editor scroll → preview scroll) because it has no visibility into the native side
- Cannot measure FPS or frame drops in the native compositor

**Verdict: Not viable.** Playwright is designed for web apps in a browser, not native macOS apps with embedded web views. The existing pending tasks (#7, #8, #9) for Playwright-based scroll sync tests should be reconsidered.

---

### 2. XCUITest (Apple's UI Testing Framework)

**What it can do:**
- Launch the app, interact with all native UI elements via accessibility
- Simulate scroll gestures on both the editor pane and preview pane using `XCUIElement.swipeUp()`, `scroll(byDeltaX:deltaY:)`, etc.
- Test single-pane vs double-pane layout by tapping the toolbar toggle button and asserting element existence
- Use `XCTOSSignpostMetric` to measure custom signpost intervals (see hybrid approach below)
- Use built-in `scrollDecelerationMetric` / `scrollingAndDecelerationMetric` for scroll hitch detection (but these target UIKit `UIScrollView`, not AppKit `NSScrollView`)

**What it cannot do:**
- **Cannot evaluate JavaScript inside WKWebView.** XCUITest sees WKWebView content through the accessibility tree only — it can find static text elements and buttons rendered by the web view, but cannot call `evaluateJavaScript` or read `window.scrollY`.
- **Cannot precisely control scroll velocity** — `swipeUp()` has a fixed speed, making it hard to reproduce consistent scroll scenarios. `scroll(byDeltaX:deltaY:)` gives pixel-level control but no velocity control.
- **macOS scroll hitch metrics are limited.** `XCTOSSignpostMetric.scrollDecelerationMetric` and the hitch-rate metrics from WWDC20 are UIKit/iOS-focused. On macOS with AppKit views, these may not fire correctly for NSScrollView.
- **Cannot directly measure the time delta** between "editor scrolled to line X" and "preview arrived at line X" without app-side instrumentation.

**Verdict: Good for layout testing and driving interactions, but insufficient alone for latency/FPS measurement.**

---

### 3. Accessibility-Based Automation (AppleScript / AXUIElement)

**What it can do:**
- Query the accessibility tree of the running app
- Verify pane existence (editor visible / hidden)
- Read accessibility values from elements
- Perform basic actions (press buttons, set values)

**What it cannot do:**
- **Cannot simulate smooth scroll gestures.** AppleScript/AXUIElement can set scroll positions but not simulate continuous scroll events at a controlled rate.
- **Cannot measure timing with any precision.** No integration with signposts or Instruments.
- **Cannot interact with WKWebView content** beyond what's exposed in the accessibility tree.
- **Fragile and slow** compared to XCUITest.

**Verdict: Not recommended as primary approach. Could supplement XCUITest for specific accessibility checks.**

---

### 4. Instruments / os_signpost (In-App Instrumentation)

**What it can do:**
- Emit precise timestamps at every stage of the scroll sync pipeline:
  - `editorDidScrollToLine` entry/exit
  - `previewDidScrollToLine` entry/exit
  - `scrollToSourceLine` (JS evaluation sent)
  - JS `scrollTo` executed (via `WKScriptMessageHandler` callback)
- Measure end-to-end latency: time from NSScrollView bounds change to WKWebView scroll completion
- Integrate with `XCTOSSignpostMetric` in performance tests for automated regression detection
- Visualize in Instruments for manual profiling sessions
- Measure frame timing via `CVDisplayLink` (macOS equivalent of `CADisplayLink`) to detect dropped frames during scroll sync

**What it cannot do:**
- **Cannot drive the app.** Signposts are passive instrumentation — they need something else to generate scroll events.
- **Cannot verify visual correctness** (e.g., that the right content is visible at the right scroll position).

**Verdict: Essential for measurement, but needs a driver.**

---

### 5. CVDisplayLink Frame Rate Monitor (In-App)

**What it can do:**
- Register a callback on every display refresh (16.6ms at 60Hz, 8.3ms at 120Hz)
- Detect frame drops by comparing expected vs actual callback timestamps
- Run alongside scroll sync to measure actual FPS during scrolling
- Can be compiled out of release builds with `#if DEBUG`

**What it cannot do:**
- Same as signposts — passive measurement, needs a driver.

---

## Recommended Approach: Hybrid (XCUITest + os_signpost + CVDisplayLink)

The best approach combines three layers:

### Layer 1: App-Side Instrumentation (os_signpost + CVDisplayLink)

Add signposts to `ScrollSyncController` to bracket the full sync cycle:

```swift
import os

extension ScrollSyncController {
    static let signpostLog = OSLog(subsystem: "dev.paulkang.markview", category: "ScrollSync")

    func editorDidScrollToLine(_ line: Int) {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "EditorToPreviewSync", signpostID: signpostID, "line:%d", line)
        // ... existing logic ...
        // In the async dispatch where previewCoordinator?.scrollToSourceLine is called:
        os_signpost(.end, log: Self.signpostLog, name: "EditorToPreviewSync", signpostID: signpostID)
    }
}
```

Add a `FrameRateMonitor` using `CVDisplayLink` that tracks frame timing during active scroll sync and reports drops.

### Layer 2: XCUITest for Driving & Layout Verification

```swift
// MarkViewUITests.swift
import XCTest

final class ScrollSyncTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        app.launchArguments = ["--ui-testing"]
        app.launch()
        // Open a test markdown file
    }

    // MARK: - Layout Tests

    func testSinglePaneLayout() {
        // Verify preview-only mode (default)
        XCTAssertTrue(app.webViews.firstMatch.exists)
        // Editor should not be visible
    }

    func testDoublePaneLayout() {
        // Toggle editor with Cmd+E
        app.typeKey("e", modifierFlags: .command)
        // Verify both panes exist
        XCTAssertTrue(app.textViews.firstMatch.exists)  // NSTextView
        XCTAssertTrue(app.webViews.firstMatch.exists)    // WKWebView
    }

    // MARK: - Scroll Sync Performance

    func testScrollSyncLatency() throws {
        app.typeKey("e", modifierFlags: .command)  // Open editor

        let editor = app.scrollViews.firstMatch

        // Use custom signpost metric
        let metric = XCTOSSignpostMetric(
            subsystem: "dev.paulkang.markview",
            category: "ScrollSync",
            name: "EditorToPreviewSync"
        )

        measure(metrics: [metric]) {
            editor.scroll(byDeltaX: 0, deltaY: -200)
            // Wait for sync to complete (signpost end fires)
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}
```

### Layer 3: In-App FPS Reporting (for CI)

For CI pipelines where Instruments isn't available, the app can write a JSON perf report when launched with `--ui-testing --perf-report /tmp/perf.json`:

```swift
// FrameRateMonitor writes:
{
    "scrollSyncEvents": [
        {"editorLine": 42, "latencyMs": 12.3, "droppedFrames": 0},
        {"editorLine": 85, "latencyMs": 18.7, "droppedFrames": 1}
    ],
    "averageLatencyMs": 15.5,
    "p99LatencyMs": 23.1,
    "averageFPS": 58.2,
    "totalDroppedFrames": 3
}
```

The XCUITest reads this file after the scroll test and asserts against thresholds.

---

## Why This Hybrid Approach Wins

| Requirement | Playwright | XCUITest alone | AppleScript | os_signpost alone | **Hybrid** |
|---|---|---|---|---|---|
| Drive scroll on NSTextView | No | Yes | Partial | No | **Yes** |
| Drive scroll on WKWebView | No | Yes (gesture) | No | No | **Yes** |
| Measure sync latency | No | Partial | No | Yes | **Yes** |
| Measure FPS/drops | No | iOS only | No | Yes | **Yes** |
| Test layout toggle | No | Yes | Partial | No | **Yes** |
| CI-compatible | Yes | Yes | Fragile | No (needs Instruments) | **Yes** |
| Read WKWebView scroll pos | Yes (wrong context) | No | No | Yes (via JS bridge) | **Yes** |

---

## Implementation Priority

1. **Add os_signpost instrumentation to ScrollSyncController** — 1-2 hours, immediately useful for manual profiling in Instruments
2. **Add XCUITest target with layout tests** — 2-3 hours, catches regressions in single/double pane toggle
3. **Add XCTOSSignpostMetric scroll sync perf tests** — 2-3 hours, automated latency regression detection
4. **Add CVDisplayLink frame monitor** — 3-4 hours, FPS/drop measurement for CI
5. **Add CI perf report JSON output** — 2 hours, makes perf data actionable in CI

Total estimated effort: ~2 days for full coverage.

---

## Key Risks & Mitigations

- **XCTOSSignpostMetric on macOS AppKit**: The scroll hitch metrics are documented for UIKit. Custom signpost metrics work on macOS, but the built-in `scrollDecelerationMetric` may not. Mitigation: use custom signposts exclusively, don't rely on built-in scroll metrics.
- **WKWebView JS execution timing**: The signpost `.end` fires when `evaluateJavaScript` is called, not when the browser compositor renders the scroll. Mitigation: have JS post back a confirmation message via `WKScriptMessageHandler` and end the signpost on receipt.
- **XCUITest scroll precision**: `scroll(byDeltaX:deltaY:)` gives pixel control but not velocity. For consistent benchmarks, use fixed delta values and multiple iterations. `measure(metrics:)` handles statistical aggregation.

## Sources

- [XCTOSSignpostMetric docs](https://developer.apple.com/documentation/xctest/xctossignpostmetric)
- [WWDC20: Eliminate animation hitches with XCTest](https://developer.apple.com/videos/play/wwdc2020/10077/)
- [WWDC18: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/)
- [OSSignposter docs](https://developer.apple.com/documentation/os/ossignposter)
- [XCMetrics scroll signpost example](https://github.com/SoaurabhK/XCMetrics/blob/master/XCMetricsUITests/XCSignpostScrollMetricsUITests.swift)
- [Kyle Sherman: Measuring iOS scroll performance](https://thisiskyle.me/posts/measuring-ios-scroll-performance-is-tough-use-this-to-make-it-simple-and-automated.html)
- [Playwright: does not support native app testing](https://www.restack.io/p/playwright-answer-does-playwright-support-native-mobile-app-testing)
