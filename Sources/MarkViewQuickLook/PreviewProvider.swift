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

    /// Compute preview size matching MarkView's window sizing logic:
    /// ~50% screen width, full screen height.
    private static var preferredContentSize: CGSize {
        let screen = NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let width = max(frame.width * 0.50, 800)
        let height = frame.height
        return CGSize(width: width, height: height)
    }

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
            let document = MarkdownRenderer.wrapInTemplate(accessible)
            return Data(document.utf8)
        }
        reply.title = request.fileURL.deletingPathExtension().lastPathComponent
        handler(reply, nil)
    }
}
