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
/// Uses QLPreviewingController (view-controller path) with WKWebView for full-fidelity
/// rendering (CSS, Prism.js syntax highlighting, dark mode). Writes HTML to a temp file
/// and loads via file URL for sandbox compatibility.
class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController, WKNavigationDelegate {

    private static let logger = Logger(subsystem: "dev.paulkang.MarkView.QuickLook", category: "preview")

    /// Layout-only CSS injected into every preview. Color theming is handled by
    /// `darkModeCSS` / `lightModeCSS` which are selected at runtime based on
    /// the system appearance (WKWebView in extension sandbox doesn't inherit it).
    static let layoutCSS = """
        body { max-width: 100% !important; padding: 24px 48px !important; }
    """

    /// Dark mode overrides — matches the template's @media (prefers-color-scheme: dark) block.
    /// Duplicated here because WKWebView's WebContent process in the extension sandbox
    /// does not receive the host system's appearance, so media queries don't fire.
    static let darkModeCSS = """
        body { color: #e6edf3 !important; background: #0d1117 !important; }
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
    """

    /// Light mode — the template defaults are light, so only layout overrides needed.
    static let lightModeCSS = ""

    private var webView: WKWebView!
    private let request = QuickLookPreviewRequest()
    private var tempFileURL: URL?
    private var preparationTask: Task<Void, Never>?
    private var activeRequest = 0
    private var activeNavigation: WKNavigation?

    /// Detect whether the system is in dark mode.
    private var isDarkMode: Bool {
        NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

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
        let screen = NSScreen.main ?? NSScreen.screens.first
        let height = screen.map { $0.visibleFrame.height * 0.9 } ?? 900
        preferredContentSize = NSSize(width: 1200, height: height)
    }

    // MARK: - QLPreviewingController (callback-based API)

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        preparationTask?.cancel()
        preparationTask = nil
        activeNavigation = nil
        webView?.stopLoading()
        cleanupTempFile()
        let generation = request.begin(completion: handler)
        guard request.isCurrent(generation) else { return }
        activeRequest = generation
        _ = view // Ensure WKWebView exists before handing it a prepared document.
        let colorCSS = isDarkMode ? Self.darkModeCSS : Self.lightModeCSS
        let css = "\(Self.layoutCSS)\n\(colorCSS)"
        let temporaryDirectory = FileManager.default.temporaryDirectory

        preparationTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let document = try await QuickLookDocumentRenderer.shared.prepare(
                    fileURL: url, css: css, temporaryDirectory: temporaryDirectory
                )
                guard let self, self.request.isCurrent(generation), !Task.isCancelled else {
                    if let file = document.fileURL { try? FileManager.default.removeItem(at: file) }
                    return
                }
                self.preparationTask = nil
                self.tempFileURL = document.fileURL
                if let file = document.fileURL {
                    self.activeNavigation = self.webView.loadFileURL(file, allowingReadAccessTo: temporaryDirectory)
                } else {
                    Self.logger.error("Failed to write temp HTML: \(document.writeError ?? "unknown error")")
                    self.activeNavigation = self.webView.loadHTMLString(document.html, baseURL: nil)
                }
                if self.activeNavigation == nil {
                    self.completeCurrent(NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError))
                }
            } catch {
                guard let self, self.request.isCurrent(generation) else { return }
                self.preparationTask = nil
                Self.logger.error("Quick Look failed to prepare \(url.path): \(error.localizedDescription)")
                self.completeCurrent(error)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation, let activeNavigation, navigation === activeNavigation else { return }
        completeCurrent(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let navigation, let activeNavigation, navigation === activeNavigation else { return }
        Self.logger.error("WKWebView didFail: \(error.localizedDescription)")
        completeCurrent(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let navigation, let activeNavigation, navigation === activeNavigation else { return }
        Self.logger.error("WKWebView didFailProvisionalNavigation: \(error.localizedDescription)")
        completeCurrent(error)
    }

    private func completeCurrent(_ error: Error?) {
        let generation = activeRequest
        activeNavigation = nil
        cleanupTempFile()
        request.finish(generation, error: error)
    }

    deinit {
        preparationTask?.cancel()
        if let file = tempFileURL { try? FileManager.default.removeItem(at: file) }
    }

    private func cleanupTempFile() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }
}
