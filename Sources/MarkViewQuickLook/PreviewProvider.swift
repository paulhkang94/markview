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
/// window sizing via preferredContentSize. Signals completion only after the
/// WKWebView finishes loading, preventing Quick Look from showing a blank/tiny preview.
class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController, WKNavigationDelegate {

    private static let logger = Logger(subsystem: "dev.paulkang.MarkView.QuickLook", category: "preview")

    /// CSS override that removes the main app's max-width constraint so the
    /// rendered markdown fills the entire Quick Look panel.
    static let quickLookCSS = """
        <style>
            body { max-width: 100% !important; padding: 24px 48px !important; }
        </style>
    """

    private var webView: WKWebView!
    private var completionHandler: ((Error?) -> Void)?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        webView.autoresizingMask = [.height, .width]
        webView.navigationDelegate = self
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 1200, height: 900)
    }

    // MARK: - QLPreviewingController (callback-based API)

    /// Uses the callback-based API so we can signal completion AFTER WKWebView
    /// finishes loading. The async version returns immediately, before the webview
    /// renders, causing Quick Look to display a tiny/blank preview.
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        self.completionHandler = handler

        let markdown: String
        do {
            markdown = try String(contentsOf: url, encoding: .utf8)
        } catch {
            Self.logger.error("Quick Look failed to read \(url.path): \(error.localizedDescription)")
            handler(error)
            return
        }

        let html = MarkdownRenderer.renderHTML(from: markdown)
        let accessible = MarkdownRenderer.postProcessForAccessibility(html)
        var document = MarkdownRenderer.wrapInTemplate(accessible)
        // Inject QL-specific CSS before </head> to override max-width
        document = document.replacingOccurrences(
            of: "</head>",
            with: "\(Self.quickLookCSS)</head>"
        )

        webView.isHidden = true // prevent flicker before content loads
        webView.loadHTMLString(document, baseURL: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Signal completion only after WKWebView finishes rendering
        if let handler = completionHandler {
            handler(nil)
            completionHandler = nil
        }
        // Brief delay to prevent resize flicker (same technique as QLMarkdown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.webView.isHidden = false
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let handler = completionHandler {
            handler(error)
            completionHandler = nil
            webView.isHidden = false
        }
    }
}
