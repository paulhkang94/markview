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

    /// Export via WKWebView's createPDF — produces high-quality output.
    @MainActor static func exportPDF(from webView: WKWebView, suggestedName: String, errorPresenter: ErrorPresenter) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: ".md", with: ".pdf")
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let config = WKPDFConfiguration()
        // A4 size in points
        config.rect = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)

        webView.createPDF(configuration: config) { result in
            switch result {
            case .success(let data):
                do {
                    try data.write(to: url)
                    AppLogger.export.info("PDF exported to \(url.path)")
                } catch {
                    Task { @MainActor in
                        errorPresenter.show("PDF export failed", detail: error.localizedDescription)
                    }
                    AppLogger.captureError(error, category: "export", message: "PDF export write failed")
                }
            case .failure(let error):
                Task { @MainActor in
                    errorPresenter.show("PDF export failed", detail: error.localizedDescription)
                }
                AppLogger.captureError(error, category: "export", message: "PDF createPDF failed")
            }
        }
    }
}
