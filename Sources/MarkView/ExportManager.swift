import AppKit
import WebKit

/// Handles exporting markdown preview to HTML and PDF formats.
final class ExportManager {

    /// Export the current HTML to a standalone HTML file (with inline CSS).
    static func exportHTML(html: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: ".md", with: ".html")
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            try? html.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Export via WKWebView's createPDF — produces high-quality output.
    static func exportPDF(from webView: WKWebView, suggestedName: String) {
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
                try? data.write(to: url)
            case .failure(let error):
                print("PDF export failed: \(error)")
            }
        }
    }
}
