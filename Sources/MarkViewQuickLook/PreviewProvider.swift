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
/// window sizing via preferredContentSize. Writes HTML to a temp file and loads via
/// file URL for sandbox compatibility. Signals completion after WKWebView finishes.
class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController, WKNavigationDelegate {

    private static let logger = Logger(subsystem: "dev.paulkang.MarkView.QuickLook", category: "preview")

    /// CSS override that removes the main app's max-width constraint so the
    /// rendered markdown fills the entire Quick Look panel.
    /// Force dark mode styles in Quick Look since the QL panel always uses a dark
    /// background. The WKWebView in extension sandbox may not inherit the system
    /// appearance, causing light-mode colors (dark text on dark bg = unreadable).
    static let quickLookCSS = """
        <style>
            body {
                max-width: 100% !important;
                padding: 24px 48px !important;
                color: #e6edf3 !important;
                background: #0d1117 !important;
            }
            a { color: #58a6ff !important; }
            code:not([class*="language-"]) { background: #343942 !important; color: #e6edf3 !important; }
            pre { background: #161b22 !important; color: #e6edf3 !important; }
            th, td { border-color: #3d444d !important; color: #e6edf3 !important; }
            tr { background-color: #0d1117 !important; border-top-color: #3d444db3 !important; }
            tr:nth-child(2n) { background-color: #151b23 !important; }
            blockquote { border-left-color: #3d444d !important; color: #8b949e !important; }
            hr { border-top-color: #3d444d !important; }
            h1, h2, h3, h4, h5 { color: #e6edf3 !important; }
            h1, h2 { border-bottom-color: #3d444d !important; }
            h6 { color: #8b949e !important; }
            :focus-visible { outline-color: #58a6ff !important; }
        </style>
    """

    private var webView: WKWebView!
    private var completionHandler: ((Error?) -> Void)?
    private var tempFileURL: URL?

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
        // Use 90% of screen height for a tall preview panel
        let screen = NSScreen.main ?? NSScreen.screens.first
        let height = screen.map { $0.visibleFrame.height * 0.9 } ?? 900
        preferredContentSize = NSSize(width: 1200, height: height)
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
        document = document.replacingOccurrences(
            of: "</head>",
            with: "\(Self.quickLookCSS)</head>"
        )

        // Write to temp file and load via file URL — more reliable in sandboxed extensions
        // than loadHTMLString which can fail silently when WebContent process can't initialize.
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("ql-preview-\(UUID().uuidString).html")
        do {
            try document.write(to: tempFile, atomically: true, encoding: .utf8)
            tempFileURL = tempFile
            webView.loadFileURL(tempFile, allowingReadAccessTo: tempDir)
        } catch {
            Self.logger.error("Failed to write temp HTML: \(error.localizedDescription)")
            // Fallback to loadHTMLString
            webView.loadHTMLString(document, baseURL: nil)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let handler = completionHandler {
            handler(nil)
            completionHandler = nil
        }
        cleanupTempFile()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Self.logger.error("WKWebView didFail: \(error.localizedDescription)")
        if let handler = completionHandler {
            handler(error)
            completionHandler = nil
        }
        cleanupTempFile()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Self.logger.error("WKWebView didFailProvisionalNavigation: \(error.localizedDescription)")
        if let handler = completionHandler {
            handler(error)
            completionHandler = nil
        }
        cleanupTempFile()
    }

    private func cleanupTempFile() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }
}
