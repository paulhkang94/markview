import AppKit
import WebKit

/// Handles exporting markdown preview to HTML and PDF formats.
/// Returns errors to caller for toast display.
final class ExportManager {

    /// Export the current HTML to a standalone HTML file (with inline CSS).
    @MainActor static func exportHTML(html: String, suggestedName: String, errorPresenter: ErrorPresenter) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: ".md", with: ".html")
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
                AppLogger.export.info("HTML exported to \(url.path)")
            } catch {
                errorPresenter.show("HTML export failed", detail: error.localizedDescription)
                AppLogger.captureError(error, category: "export", message: "HTML export write failed")
            }
        }
    }

    /// Export full document as PDF using WKWebView.createPDF with JS-resolved document height.
    ///
    /// Architecture note on NSPrintOperation (previous approach, now removed):
    /// NSPrintOperation renders each DOM element as a separate PDF object. For complex HTML
    /// (markdown tables, code blocks, many divs) this produces 16M+ objects → 50MB+ files
    /// that Preview cannot open. createPDF uses WebKit's native PDF renderer: efficient
    /// vector output, typically 100–500KB for text documents.
    ///
    /// Full-document capture: JavaScript resolves the true scroll height so the capture
    /// rect covers all content, not just the visible viewport.
    @MainActor static func exportPDF(from webView: WKWebView, suggestedName: String, errorPresenter: ErrorPresenter) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: ".md", with: ".pdf")
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task { @MainActor in
            let ok = await generatePDF(from: webView, to: url)
            if !ok {
                errorPresenter.show("PDF export failed", detail: "Could not render document")
                AppLogger.captureError(
                    CocoaError(.fileWriteUnknown),
                    category: "export",
                    message: "generatePDF returned false"
                )
            }
        }
    }

    /// Generate PDF to a URL without a save panel. Used by tests and the export action.
    ///
    /// Returns true on success. The caller is responsible for error presentation.
    @MainActor static func generatePDF(from webView: WKWebView, to url: URL) async -> Bool {
        // Resolve full document height via JS — captures all content, not just viewport.
        let jsResult = try? await webView.callAsyncJavaScript(
            "return document.documentElement.scrollHeight",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let docHeight = (jsResult as? Double).map { CGFloat($0) } ?? webView.bounds.height
        let viewWidth = webView.bounds.width > 0 ? webView.bounds.width : 800

        let config = WKPDFConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: viewWidth, height: docHeight)

        return await withCheckedContinuation { continuation in
            webView.createPDF(configuration: config) { result in
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: url)
                        AppLogger.export.info("PDF exported to \(url.path) (\(data.count / 1024)KB, height=\(Int(docHeight))px)")
                        continuation.resume(returning: true)
                    } catch {
                        AppLogger.captureError(error, category: "export", message: "PDF write failed")
                        continuation.resume(returning: false)
                    }
                case .failure(let error):
                    AppLogger.captureError(error, category: "export", message: "createPDF failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
