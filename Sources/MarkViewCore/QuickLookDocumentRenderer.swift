import Foundation

public struct QuickLookDocument: Sendable {
    public let html: String
    public let fileURL: URL?
    public let writeError: String?
}

/// Serializes file preparation away from the extension's main actor.
/// Cancellation is checked between stages; a cmark call already running is
/// allowed to finish before the next request starts.
public actor QuickLookDocumentRenderer {
    public static let shared = QuickLookDocumentRenderer()
    private let renderOperation: @Sendable (String) -> String

    public init(renderOperation: @escaping @Sendable (String) -> String = {
        MarkdownRenderer.renderHTML(from: $0)
    }) {
        self.renderOperation = renderOperation
    }

    public func prepare(
        fileURL: URL,
        css: String,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> QuickLookDocument {
        try Task.checkCancellation()
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        try Task.checkCancellation()
        let accessible = MarkdownRenderer.postProcessForAccessibility(renderOperation(markdown))
        let document = MarkdownRenderer.wrapInTemplate(accessible)
            .replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        try Task.checkCancellation()
        let output = temporaryDirectory.appendingPathComponent("ql-preview-\(UUID().uuidString).html")
        do {
            try document.write(to: output, atomically: true, encoding: .utf8)
        } catch {
            return QuickLookDocument(html: document, fileURL: nil, writeError: error.localizedDescription)
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
        return QuickLookDocument(html: document, fileURL: output, writeError: nil)
    }
}
