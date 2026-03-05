import SwiftUI
import AppKit

/// A markdown editor backed by NSTextView for native find/replace, undo/redo, and text editing.
///
/// Scroll sync: The editor reports its visible top source line to ScrollSyncController,
/// and accepts scrollToLine commands from the preview pane — all bypassing SwiftUI.
///
/// Text integrity: The coordinator owns the "source of truth" flag (`isUserEditing`) to prevent
/// SwiftUI's updateNSView from overwriting NSTextView content during active typing. This avoids
/// the classic NSViewRepresentable race condition where binding updates lag behind the native view.
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

        // Editor colors: use system label color on system background for proper contrast
        // in both light and dark mode. drawsBackground = true so the editor pane is opaque.
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor

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

        // Non-contiguous layout: allows the layout manager to skip unneeded regions
        // of large documents. Without this, frame resizes trigger a full layout pass
        // from glyph 0 to the last visible glyph, causing getLineStart:forRange: to
        // be called with an out-of-bounds range on large files (1000+ lines).
        textView.layoutManager?.allowsNonContiguousLayout = true

        // Disable inline prediction and auto-correction.
        // When these are active, macOS can hold "marked text" (a tentative inline suggestion)
        // inside the NSTextView input context. If updateNSView replaces textView.string and
        // then calls setSelectedRanges, AppKit's _NSClearMarkedRange fires to flush the pending
        // suggestion. That triggers the undo system to snapshot the affected range against the
        // OLD string — which has already been replaced — causing substringFromIndex: to receive
        // an out-of-bounds index → EXC_BREAKPOINT. Disabling these features prevents marked
        // text from accumulating in the first place.
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Initial content
        textView.string = text

        // Apply settings (includes font + colors)
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

        // CRITICAL: If the coordinator just set the binding from textDidChange, the NSTextView
        // already has the correct content. Overwriting it would cause cursor jumps, character
        // corruption, and undo stack damage. Only push text into NSTextView when it was changed
        // externally (file reload, programmatic edit, etc.).
        if !context.coordinator.isUserEditing, textView.string != text {
            let textLength = (text as NSString).length
            // Clamp saved selection ranges to the new text length to avoid out-of-bounds crashes.
            // On file-watcher reloads this preserves cursor position; on initial load the old
            // selectedRanges will be empty so we fall through to the default.
            let clampedRanges: [NSValue] = textView.selectedRanges.compactMap { rangeValue in
                let range = rangeValue.rangeValue
                // Bug #20: location == textLength is OOB. NSTextView calls characterAtIndex:location
                // when positioning the cursor; valid indices are 0..<textLength (0-indexed). An
                // insertion point at EOF must use location = textLength - 1 at most, or be dropped.
                guard range.location < textLength else { return nil }
                let loc = range.location
                // Bug #21: A corrupted NSRange can carry a negative length (e.g., 18446744073709551613
                // = -3 as Int64). Swift's min() is signed, so min(-3, textLength - loc) = -3, and
                // NSRange(length: -3) is interpreted by AppKit as UInt.max - 2 → substringWithRange OOB.
                guard range.length >= 0 else { return nil }
                let len = min(range.length, textLength - loc)
                return NSValue(range: NSRange(location: loc, length: len))
            }
            // Flush any pending marked (inline prediction) text BEFORE touching selectedRanges
            // or replacing string content. If marked text is present when setSelectedRanges is
            // called, AppKit's _NSClearMarkedRange will insert it via _insertText:replacementRange:,
            // which triggers the undo system to snapshot a range against the already-replaced
            // string → substringFromIndex: OOB → EXC_BREAKPOINT. unmarkText() clears the input
            // context state synchronously with no undo side-effects.
            textView.unmarkText()
            // Reset selection to {0,0} BEFORE replacing content.
            // During textView.string = text, NSTextView internally calls setSelectedRanges:
            // with the current (old) selection to update cursor position after the replacement.
            // If the old selection points past the end of the new (shorter) text, NSLayoutManager
            // tries to compute the cursor blink rect for an out-of-bounds character range and
            // NSBigMutableString.getCharacters:range: throws → EXC_BREAKPOINT.
            // Resetting to {0,0} first ensures the internal setSelectedRanges: call uses a
            // position that is valid in any non-empty string.
            textView.selectedRanges = [NSValue(range: NSRange(location: 0, length: 0))]
            textView.string = text
            // Default cursor: beginning of document, NOT end-of-file.
            // Placing cursor at textLength forced the layout manager to compute layout for the
            // entire large document immediately. On frame resize, sizeToFit then calls
            // getLineStart:forRange: with an out-of-bounds range → SIGTRAP on 1000+ line files.
            // allowsNonContiguousLayout (set in makeNSView) is the primary fix; cursor-at-0
            // ensures new file opens start at the top rather than forcing full layout upfront.
            //
            // HANG FIX: Defer cursor restoration one runloop cycle.
            // When setSelectedRanges is called with a non-zero position synchronously inside
            // updateNSView, AppKit calls _invalidateDisplayForChangeOfSelection which forces
            // NSLayoutManager to generate ALL glyphs up to the cursor position to correctly
            // render the selection highlight. On large files this blocks the main thread 2s+
            // (_NSFastFillAllGlyphHolesForCharacterRange). Deferring via async lets the current
            // runloop cycle complete (string replacement + layout invalidation settle), then
            // restores the cursor cheaply after AppKit has already processed the content change.
            // The synchronous {0,0} reset above MUST remain synchronous to prevent the
            // NSLayoutManager OOB crash (old selection pointing past end of new shorter string).
            let capturedRanges = clampedRanges
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                textView.selectedRanges = capturedRanges.isEmpty
                    ? [NSValue(range: NSRange(location: 0, length: 0))]
                    : capturedRanges
            }
            context.coordinator.rebuildLineOffsets(from: text)
        }
        // Reset the flag — the next updateNSView call from a non-typing source should apply
        context.coordinator.isUserEditing = false

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

        // Typing attributes must include foreground color to ensure new text has proper contrast.
        // Without this, newly typed text can inherit transparent/low-contrast attributes.
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

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
        /// Set to true during textDidChange to prevent updateNSView from overwriting NSTextView.
        /// This is the core fix for the text corruption bug. The flag is set in textDidChange
        /// (before the binding propagates) and cleared in updateNSView (after it skips the write).
        var isUserEditing = false
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
            // Set the flag BEFORE updating the binding. When SwiftUI processes the binding
            // change and calls updateNSView, it will see isUserEditing=true and skip the
            // text replacement — NSTextView already has the correct content.
            isUserEditing = true
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
