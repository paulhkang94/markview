import SwiftUI
import AppKit

/// A markdown editor backed by NSTextView for native find/replace, undo/redo, and text editing.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let onChange: (String) -> Void
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

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update text if it actually changed (avoid cursor reset)
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
        }

        applySettings(to: textView)
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

        init(text: Binding<String>, onChange: @escaping (String) -> Void) {
            self.text = text
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            text.wrappedValue = newText
            onChange(newText)
        }
    }
}
