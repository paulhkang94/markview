import AppKit
import WebKit

/// Thread-safe mutable box for sharing state across isolation boundaries.
/// Safety is guaranteed by the caller (background thread spin-waits until main thread writes).
private final class SharedBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Renders HTML in an offscreen WKWebView and captures a screenshot as PNG data.
/// All WKWebView work happens on @MainActor. The public `renderToPNG` entry point
/// is nonisolated (called from background thread) and dispatches to main internally.
@MainActor
final class OffscreenRenderer: NSObject, WKNavigationDelegate, @unchecked Sendable {
    private let width: CGFloat
    private let height: CGFloat
    private var webView: WKWebView?
    private var completion: ((Result<Data, Error>) -> Void)?

    enum RenderError: Error, CustomStringConvertible {
        case navigationFailed(Error?)
        case snapshotFailed(Error?)
        case pngConversionFailed

        var description: String {
            switch self {
            case .navigationFailed(let e): return "Navigation failed: \(e?.localizedDescription ?? "unknown")"
            case .snapshotFailed(let e): return "Snapshot failed: \(e?.localizedDescription ?? "unknown")"
            case .pngConversionFailed: return "Failed to convert snapshot to PNG"
            }
        }
    }

    init(width: CGFloat = 900, height: CGFloat = 800) {
        self.width = width
        self.height = height
        super.init()
    }

    /// Render HTML string and return PNG screenshot data.
    /// Must be called from a background thread — dispatches to main actor internally
    /// and spin-waits for the result.
    nonisolated func renderToPNG(html: String) throws -> Data {
        assert(!Thread.isMainThread, "renderToPNG must be called from a background thread")

        let resultBox = SharedBox<Result<Data, Error>?>(nil)
        let doneBox = SharedBox<Bool>(false)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.renderAsync(html: html) { res in
                    resultBox.value = res
                    doneBox.value = true
                }
            }
        }

        // Spin-wait while pumping the main run loop from outside
        let deadline = Date().addingTimeInterval(30)
        while !doneBox.value && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        guard doneBox.value else {
            throw RenderError.navigationFailed(nil)
        }

        switch resultBox.value! {
        case .success(let data): return data
        case .failure(let error): throw error
        }
    }

    private func renderAsync(html: String, completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        wv.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Small delay to allow CSS layout to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            self.captureScreenshot(webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completion?(.failure(RenderError.navigationFailed(error)))
        completion = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completion?(.failure(RenderError.navigationFailed(error)))
        completion = nil
    }

    private func captureScreenshot(_ webView: WKWebView) {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(width))

        webView.takeSnapshot(with: config) { [self] image, error in
            guard let image = image else {
                self.completion?(.failure(RenderError.snapshotFailed(error)))
                self.completion = nil
                return
            }

            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                self.completion?(.failure(RenderError.pngConversionFailed))
                self.completion = nil
                return
            }

            self.completion?(.success(pngData))
            self.completion = nil
        }
    }
}

/// Inject forced dark-mode CSS into an HTML string (same approach as WebPreviewView.darkModeCSS)
func injectDarkMode(into html: String) -> String {
    let darkCSS = """
    <style id="forced-dark">
        body { color: #e6edf3; background: #0d1117; }
        :root { color-scheme: dark; }
        a { color: #58a6ff; }
        code:not([class*="language-"]) { background: #343942; color: #e6edf3; }
        pre { background: #161b22 !important; }
        th, td { border-color: #3d444d; }
        tr { background-color: #0d1117; border-top-color: #3d444db3; }
        tr:nth-child(2n) { background-color: #151b23; }
        blockquote { border-left-color: #3d444d; color: #8b949e; }
        hr { border-top-color: #3d444d; }
        h1, h2 { border-bottom-color: #3d444d; }
        h6 { color: #8b949e; }
    </style>
    """
    return html.replacingOccurrences(of: "</head>", with: "\(darkCSS)\n</head>")
}
