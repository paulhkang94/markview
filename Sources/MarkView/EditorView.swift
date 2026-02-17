import SwiftUI
import AppKit

/// A markdown editor backed by NSTextView for native find/replace, undo/redo, and text editing.
///
/// Scroll sync: The editor reports its visible top source line to ScrollSyncController,
/// and accepts scrollToLine commands from the preview pane — all bypassing SwiftUI.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let onChange: (String) -> Void
    /// Direct reference to the scroll sync controller (not a SwiftUI binding).
    var syncController: ScrollSyncController?
    @ObservedObject private var settings = AppSettings.shared

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.drawsBackground = false

        // Find bar
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Layout
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        // Initial content
        textView.string = text

        // Apply settings
        applySettings(to: textView)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.syncController = syncController
        context.coordinator.rebuildLineOffsets(from: text)

        // Register coordinator with the sync controller for direct calls
        syncController?.editorCoordinator = context.coordinator

        // Observe scroll position changes on the clip view (contentView).
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update text if it actually changed (avoid cursor reset)
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
            context.coordinator.rebuildLineOffsets(from: text)
        }

        applySettings(to: textView)

        // Keep sync controller reference up to date
        context.coordinator.syncController = syncController
        syncController?.editorCoordinator = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onChange: onChange)
    }

    private func applySettings(to textView: NSTextView) {
        let font = NSFont.monospacedSystemFont(ofSize: settings.editorFontSize, weight: .regular)
        textView.font = font
        textView.typingAttributes = [.font: font]

        // Word wrap
        if settings.wordWrap {
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
        }

        // Spell check
        textView.isContinuousSpellCheckingEnabled = settings.spellCheck
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let onChange: (String) -> Void
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        weak var syncController: ScrollSyncController?
        /// When true, the next scroll event is from a programmatic scroll and should be ignored.
        var suppressNextScroll = false
        /// Last reported line to avoid redundant sync calls.
        private var lastReportedLine: Int = 0
        /// Cached line→character-index table. Rebuilt on text change. O(1) lookup per scroll.
        private var lineOffsets: [Int] = [0]  // lineOffsets[i] = char index of line i+1

        init(text: Binding<String>, onChange: @escaping (String) -> Void) {
            self.text = text
            self.onChange = onChange
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            text.wrappedValue = newText
            onChange(newText)
            rebuildLineOffsets(from: newText)
        }

        /// Build line offset table: lineOffsets[i] = character index where line (i+1) starts.
        func rebuildLineOffsets(from text: String) {
            var offsets = [0]
            for (i, ch) in text.utf16.enumerated() {
                if ch == 0x0A { // newline
                    offsets.append(i + 1)
                }
            }
            lineOffsets = offsets
        }

        // MARK: - Scroll Sync: Report visible line

        /// Called when the editor's scroll view content bounds change (i.e., user scrolled).
        @MainActor @objc func scrollViewDidScroll(_ notification: Notification) {
            if suppressNextScroll {
                suppressNextScroll = false
                return
            }
            guard let textView = textView else { return }

            let line = visibleTopLine(in: textView)
            guard line != lastReportedLine, line > 0 else { return }
            lastReportedLine = line

            syncController?.editorDidScrollToLine(line)
        }

        /// Get the 1-based line number of the first visible line in the text view.
        /// Uses binary search on cached line offsets — O(log n) per frame.
        @MainActor private func visibleTopLine(in textView: NSTextView) -> Int {
            guard let scrollView = scrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return 1 }

            let visibleRect = scrollView.contentView.bounds
            let topPoint = NSPoint(x: 0, y: visibleRect.origin.y + textView.textContainerInset.height)

            let glyphIndex = layoutManager.glyphIndex(for: topPoint, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            // Binary search the line offset table
            var lo = 0, hi = lineOffsets.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineOffsets[mid] <= charIndex {
                    lo = mid
                } else {
                    hi = mid - 1
                }
            }
            return lo + 1  // 1-based
        }

        // MARK: - Scroll Sync: Accept line from preview

        /// Scroll the editor to show the given 1-based source line.
        /// Uses cached line offsets for O(1) lookup.
        @MainActor func scrollToLine(_ line: Int) {
            guard let textView = textView,
                  let scrollView = scrollView else { return }
            guard !lineOffsets.isEmpty else { return }

            let lineIndex = min(line - 1, lineOffsets.count - 1)
            guard lineIndex >= 0 else { return }
            let nsCharIndex = lineOffsets[lineIndex]

            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            // Ensure layout is computed for the target region before scrolling.
            let textLength = (textView.string as NSString).length
            let charRange = NSRange(location: min(nsCharIndex, textLength), length: min(1, textLength - nsCharIndex))
            guard charRange.length > 0 else { return }
            layoutManager.ensureLayout(forCharacterRange: charRange)

            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            // Suppress the scroll notification that will fire
            suppressNextScroll = true
            lastReportedLine = line

            scrollView.contentView.scroll(to: NSPoint(x: 0, y: lineRect.origin.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
