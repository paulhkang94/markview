import AppKit
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

/// Quick Look preview extension for Markdown files.
/// Renders `.md` files as styled HTML using MarkViewCore's renderer.
class PreviewProvider: QLPreviewProvider {

    private static let logger = Logger(subsystem: "dev.paulkang.MarkView.QuickLook", category: "preview")

    /// Large content size hint so Quick Look opens a generously-sized window.
    /// NSScreen.main is nil in the sandboxed extension process, so we use a
    /// fixed size that signals "this content wants a big window."
    private static let preferredContentSize = CGSize(width: 1200, height: 900)

    /// CSS override that removes the main app's max-width constraint so the
    /// rendered markdown fills the entire Quick Look panel.
    private static let quickLookCSS = """
        <style>
            body { max-width: 100% !important; padding: 24px 48px !important; }
        </style>
    """

    func providePreview(
        for request: QLFilePreviewRequest,
        _ handler: @escaping (QLPreviewReply?, Error?) -> Void
    ) {
        let contentType = UTType.html
        let reply = QLPreviewReply(
            dataOfContentType: contentType,
            contentSize: Self.preferredContentSize
        ) { replyToUpdate -> Data in
            let markdown: String
            do {
                markdown = try String(contentsOf: request.fileURL, encoding: .utf8)
            } catch {
                Self.logger.error("Quick Look failed to read \(request.fileURL.path): \(error.localizedDescription)")
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
            return Data(document.utf8)
        }
        reply.title = request.fileURL.deletingPathExtension().lastPathComponent
        handler(reply, nil)
    }
}
