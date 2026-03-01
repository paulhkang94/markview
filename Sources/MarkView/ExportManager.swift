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

    /// Export full document as PDF using NSPrintOperation — paginates correctly across all content.
    ///
    /// WKPDFConfiguration.rect (the previous approach) only captures a fixed viewport rectangle —
    /// it does not paginate. NSPrintOperation uses WebKit's own layout engine to flow the full
    /// document across pages, producing correct multi-page output for long documents.
    @MainActor static func exportPDF(from webView: WKWebView, suggestedName: String, errorPresenter: ErrorPresenter) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: ".md", with: ".pdf")
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let printInfo = NSPrintInfo()
        // A4 in points (72 pt/inch): 8.27" × 11.69"
        printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
        printInfo.leftMargin = 36    // 0.5 inch
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let op = webView.printOperation(with: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false

        if !op.run() {
            errorPresenter.show("PDF export failed", detail: "Print operation failed")
            AppLogger.captureError(
                CocoaError(.fileWriteUnknown),
                category: "export",
                message: "NSPrintOperation failed for PDF export"
            )
        } else {
            AppLogger.export.info("PDF exported to \(url.path)")
        }
    }
}
