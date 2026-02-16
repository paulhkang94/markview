import Foundation
import MarkViewCore
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look preview extension for Markdown files.
/// Renders `.md` files as styled HTML using MarkViewCore's renderer.
class PreviewProvider: QLPreviewProvider {

    func providePreview(
        for request: QLFilePreviewRequest,
        _ handler: @escaping (QLPreviewReply?, Error?) -> Void
    ) {
        let contentType = UTType.html
        let reply = QLPreviewReply(
            dataOfContentType: contentType,
            contentSize: CGSize(width: 800, height: 600)
        ) { replyToUpdate -> Data in
            let markdown = (try? String(contentsOf: request.fileURL, encoding: .utf8)) ?? ""
            let html = MarkdownRenderer.renderHTML(from: markdown)
            let accessible = MarkdownRenderer.postProcessForAccessibility(html)
            let document = MarkdownRenderer.wrapInTemplate(accessible)
            return Data(document.utf8)
        }
        reply.title = request.fileURL.deletingPathExtension().lastPathComponent
        handler(reply, nil)
    }
}
