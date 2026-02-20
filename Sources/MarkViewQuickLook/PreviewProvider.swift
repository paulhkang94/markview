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

    override func viewDidLoad() {
        super.viewDidLoad()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        preferredContentSize = NSSize(width: screen.width * 0.5, height: screen.height)
    }

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
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
            var processed = Self.scaleFonts(in: attributed, by: 1.6)

            // NSAttributedString(html:) parses CSS at creation time — it doesn't respect
            // @media (prefers-color-scheme: dark). In dark mode, the template's light-mode
            // colors (dark text #1f2328 on white) produce invisible text on our dark background.
            // Fix: rewrite foreground colors to light equivalents.
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                processed = Self.applyDarkModeColors(to: processed)
            }

            textView.textStorage?.setAttributedString(processed)
            textView.backgroundColor = isDark ? NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1) : .white
            scrollView.backgroundColor = textView.backgroundColor

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

    /// Rewrite foreground colors for dark mode. NSAttributedString(html:) bakes in the
    /// template's light-mode CSS colors, so we remap dark text to light text.
    private static func applyDarkModeColors(to attrString: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attrString)
        let lightText = NSColor(red: 0.90, green: 0.93, blue: 0.95, alpha: 1) // ~#e6edf3
        let linkColor = NSColor(red: 0.34, green: 0.65, blue: 1.0, alpha: 1)  // ~#58a6ff
        let fullRange = NSRange(location: 0, length: mutable.length)

        // Set ALL text to light color. NSAttributedString(html:) bakes in CSS colors
        // at parse time in an unpredictable color space — brightness checks are unreliable.
        // Since the entire preview is dark mode, just force all text to light.
        mutable.addAttribute(.foregroundColor, value: lightText, range: fullRange)

        // Fix link colors
        mutable.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            if value != nil {
                mutable.addAttribute(.foregroundColor, value: linkColor, range: range)
            }
        }

        // Remove all background colors — NSAttributedString(html:) bakes in the template's
        // light-mode backgrounds (white #fff, light gray #f6f8fa for table rows). Color space
        // conversion makes brightness checks unreliable, so strip them all in dark mode.
        mutable.enumerateAttribute(.backgroundColor, in: fullRange) { value, range, _ in
            if value != nil {
                mutable.removeAttribute(.backgroundColor, range: range)
            }
        }

        return mutable
    }
}
