import Foundation
import AppKit
import WebKit
import os

/// Direct coordinator-to-coordinator scroll sync using source-line mapping.
///
/// Architecture:
///   - Editor scrolls → reads visible top line from NSTextView → tells controller
///   - Controller stores pending target → CADisplayLink fires on next vsync
///   - Display link callback applies pending scroll to the other pane
///   - Exactly one scroll update per display frame — no coalescing hacks needed
///
/// Uses CADisplayLink (macOS 14+) for frame-perfect sync. Signpost instrumentation
/// enables profiling in Instruments and automated perf testing via XCTOSSignpostMetric.
@MainActor
final class ScrollSyncController {
    weak var editorCoordinator: EditorView.Coordinator?
    weak var previewCoordinator: WebPreviewView.Coordinator?

    /// Which pane initiated the current scroll, to suppress echo.
    private var activeSource: Source?
    /// Timestamp-based suppression to prevent rapid echo.
    private var suppressUntil: Date = .distantPast
    private static let suppressDuration: TimeInterval = 0.05

    /// Pending scroll targets — set by scroll events, consumed by display link.
    private var pendingEditorLine: Int?
    private var pendingPreviewLine: Int?

    /// Display link for frame-synced updates.
    private var displayLink: CADisplayLink?

    // MARK: - Signpost instrumentation

    private static let signpostLog = OSLog(subsystem: "dev.paulkang.MarkView", category: "ScrollSync")
    static let syncSignpostName: StaticString = "ScrollSyncCycle"

    enum Source { case editor, preview }

    // MARK: - Public API

    /// Called by EditorView.Coordinator when the user scrolls the editor.
    func editorDidScrollToLine(_ line: Int) {
        guard line > 0 else { return }

        // Suppress echo from preview-initiated sync
        if activeSource == .preview, Date() < suppressUntil { return }

        activeSource = .editor
        suppressUntil = Date().addingTimeInterval(Self.suppressDuration)

        os_signpost(.begin, log: Self.signpostLog, name: Self.syncSignpostName, "editor→preview line=%d", line)
        pendingPreviewLine = line
        ensureDisplayLinkRunning()
    }

    /// Called by WebPreviewView.Coordinator when the user scrolls the preview.
    func previewDidScrollToLine(_ line: Int) {
        guard line > 0 else { return }

        // Suppress echo from editor-initiated sync
        if activeSource == .editor, Date() < suppressUntil { return }

        activeSource = .preview
        suppressUntil = Date().addingTimeInterval(Self.suppressDuration)

        os_signpost(.begin, log: Self.signpostLog, name: Self.syncSignpostName, "preview→editor line=%d", line)
        pendingEditorLine = line
        ensureDisplayLinkRunning()
    }

    /// Reset on document change.
    func reset() {
        activeSource = nil
        suppressUntil = .distantPast
        pendingEditorLine = nil
        pendingPreviewLine = nil
        stopDisplayLink()
    }

    // MARK: - CADisplayLink

    private func ensureDisplayLinkRunning() {
        guard displayLink == nil else { return }
        // On macOS, CADisplayLink is obtained from an NSView or NSScreen.
        guard let view = editorCoordinator?.scrollView ?? previewCoordinator?.webView else { return }
        let link = view.displayLink(target: self, selector: #selector(displayLinkFired))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Called exactly once per display frame. Applies any pending scroll targets.
    @objc private func displayLinkFired() {
        var didWork = false

        if let line = pendingEditorLine {
            pendingEditorLine = nil
            editorCoordinator?.scrollToLine(line)
            os_signpost(.end, log: Self.signpostLog, name: Self.syncSignpostName, "applied to editor")
            didWork = true
        }

        if let line = pendingPreviewLine {
            pendingPreviewLine = nil
            previewCoordinator?.scrollToSourceLine(line)
            os_signpost(.end, log: Self.signpostLog, name: Self.syncSignpostName, "applied to preview")
            didWork = true
        }

        // Stop the display link when there's no pending work — saves energy.
        if !didWork {
            stopDisplayLink()
        }
    }
}
