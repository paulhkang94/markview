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
class PreviewProvider: QLPreviewProvider {

    private static let logger = Logger(subsystem: "dev.paulkang.MarkView.QuickLook", category: "preview")

    /// Extra tags injected into <head> to make the preview fill the QL panel.
    /// - viewport meta: tells the QL HTML renderer to use device width, not a fixed viewport
    /// - layout CSS: removes the template's max-width constraint so content fills the panel
    static let headInjection = """
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body { max-width: 100% !important; padding: 24px 32px !important; box-sizing: border-box; }</style>
    """

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL

        let markdown = try String(contentsOf: fileURL, encoding: .utf8)

        let html = MarkdownRenderer.renderHTML(from: markdown)
        let accessible = MarkdownRenderer.postProcessForAccessibility(html)
        var document = MarkdownRenderer.wrapInTemplate(accessible)

        // Inject viewport + layout CSS. Dark mode is handled by the template's existing
        // @media (prefers-color-scheme: dark) — the data-based QL renderer
        // respects system appearance, unlike WKWebView in extension sandbox.
        document = document.replacingOccurrences(of: "</head>", with: "\(Self.headInjection)</head>")

        guard let data = document.data(using: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // contentSize .zero = let QL determine the rendering size from the panel dimensions.
        // A fixed size (e.g. 1200x900) gets scaled down to fit, making content tiny.
        return QLPreviewReply(dataOfContentType: .html, contentSize: .zero) { _ in
            return data
        }
    }
}
