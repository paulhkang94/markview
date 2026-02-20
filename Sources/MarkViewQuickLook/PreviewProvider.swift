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

            guard let attributed = NSAttributedString(
                html: htmlData,
                baseURL: url.deletingLastPathComponent(),
                documentAttributes: nil
            ) else {
                handler(CocoaError(.fileReadCorruptFile))
                return
            }

            // NSAttributedString(html:) renders with small default fonts (~12px).
            // Scale all fonts up by 1.35x to match the app's 16px base / WKWebView rendering.
            let scaled = Self.scaleFonts(in: attributed, by: 1.35)
            textView.textStorage?.setAttributedString(scaled)

            // Match system appearance for dark mode
            updateAppearance()

            handler(nil)
        } catch {
            Self.logger.error("Preview failed: \(error.localizedDescription)")
            handler(error)
        }
    }

    /// Scale all fonts in an attributed string by a multiplier.
    private static func scaleFonts(in attrString: NSAttributedString, by scale: CGFloat) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attrString)
        mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let scaled = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * scale) ?? font
            mutable.addAttribute(.font, value: scaled, range: range)
        }
        return mutable
    }

    private func updateAppearance() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        textView.backgroundColor = isDark ? NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1) : .white
        scrollView.backgroundColor = textView.backgroundColor
    }
}
