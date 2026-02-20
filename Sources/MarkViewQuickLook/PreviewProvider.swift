import Foundation
import MarkViewCore
import QuickLookUI
import UniformTypeIdentifiers
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

// MARK: - Quick Look Preview Provider

/// Data-based Quick Look preview for Markdown files.
/// Returns rendered HTML directly — no WKWebView, no sandbox issues.
class PreviewProvider: QLPreviewProvider, @preconcurrency QLPreviewingController {

    private static let logger = Logger(subsystem: "dev.paulkang.MarkView.QuickLook", category: "preview")

    /// Layout CSS for Quick Look preview pane.
    static let layoutCSS = """
        body { max-width: 100% !important; padding: 24px 48px !important; }
    """

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL

        let markdown = try String(contentsOf: fileURL, encoding: .utf8)

        let html = MarkdownRenderer.renderHTML(from: markdown)
        let accessible = MarkdownRenderer.postProcessForAccessibility(html)
        var document = MarkdownRenderer.wrapInTemplate(accessible)

        // Inject layout CSS. Dark mode is handled by the template's existing
        // @media (prefers-color-scheme: dark) — the data-based QL renderer
        // respects system appearance, unlike WKWebView in extension sandbox.
        let css = "<style>\(Self.layoutCSS)</style>"
        document = document.replacingOccurrences(of: "</head>", with: "\(css)</head>")

        guard let data = document.data(using: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 1200, height: 900)) { _ in
            return data
        }
    }
}
