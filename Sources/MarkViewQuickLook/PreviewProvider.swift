import AppKit
import MarkViewCore
import QuickLookUI
import os

// MARK: - Extension entry point

@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

@main
enum ExtensionMain {
    static func main() {
        exit(NSExtensionMain())
    }
}

// MARK: - Quick Look Preview Controller

/// View-based Quick Look preview for Markdown files.
/// Uses NSAttributedString(html:) in an NSTextView — no WKWebView, no sandbox issues,
/// and fills the entire Quick Look panel (unlike data-based QLPreviewProvider which
/// renders as a thumbnail in Finder column view).
class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {

    private static let logger = Logger(subsystem: "dev.paulkang.MarkView.QuickLook", category: "preview")

    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        self.view = scrollView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)

            let bodyHTML = MarkdownRenderer.renderHTML(from: markdown)
            let accessible = MarkdownRenderer.postProcessForAccessibility(bodyHTML)
            let document = MarkdownRenderer.wrapInTemplate(accessible)

            guard let htmlData = document.data(using: .utf8) else {
                handler(CocoaError(.fileReadCorruptFile))
                return
            }

            let attributed = NSAttributedString(
                html: htmlData,
                baseURL: url.deletingLastPathComponent(),
                documentAttributes: nil
            )

            if let attributed = attributed {
                textView.textStorage?.setAttributedString(attributed)
            }

            // Match system appearance for dark mode
            updateAppearance()

            handler(nil)
        } catch {
            Self.logger.error("Preview failed: \(error.localizedDescription)")
            handler(error)
        }
    }

    private func updateAppearance() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        textView.backgroundColor = isDark ? NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1) : .white
        scrollView.backgroundColor = textView.backgroundColor
    }
}
