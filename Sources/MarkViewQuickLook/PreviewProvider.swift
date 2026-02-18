import AppKit
import Foundation
import MarkViewCore
import QuickLookUI
import WebKit
import os

// MARK: - Extension entry point

/// Calls NSExtensionMain() to start the XPC service loop.
/// macOS loads this binary, calls main, which starts the extension hosting runtime.
/// The runtime then instantiates NSExtensionPrincipalClass from Info.plist.
@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

@main
enum ExtensionMain {
    static func main() {
        exit(NSExtensionMain())
    }
}

// MARK: - Quick Look Preview Controller

/// Quick Look preview extension for Markdown files.
/// Uses QLPreviewingController (view-controller path) with WKWebView for reliable
/// window sizing via preferredContentSize. This replaces the data-based QLPreviewProvider
/// approach where contentSize was merely a hint that macOS cached and often ignored.
class PreviewViewController: NSViewController, QLPreviewingController {

    private static let logger = Logger(subsystem: "dev.paulkang.MarkView.QuickLook", category: "preview")

    /// CSS override that removes the main app's max-width constraint so the
    /// rendered markdown fills the entire Quick Look panel.
    static let quickLookCSS = """
        <style>
            body { max-width: 100% !important; padding: 24px 48px !important; }
        </style>
    """

    private var webView: WKWebView!

    override func loadView() {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900))
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 1200, height: 900)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let markdown: String
        do {
            markdown = try String(contentsOf: url, encoding: .utf8)
        } catch {
            Self.logger.error("Quick Look failed to read \(url.path): \(error.localizedDescription)")
            markdown = ""
        }
        let html = MarkdownRenderer.renderHTML(from: markdown)
        let accessible = MarkdownRenderer.postProcessForAccessibility(html)
        var document = MarkdownRenderer.wrapInTemplate(accessible)
        // Inject QL-specific CSS before </head> to override max-width
        document = document.replacingOccurrences(
            of: "</head>",
            with: "\(Self.quickLookCSS)</head>"
        )
        webView.loadHTMLString(document, baseURL: nil)
    }
}
