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

    /// Open the macOS Print dialog for the webView.
    ///
    /// The user chooses "Save as PDF" (or a printer) from the standard Print panel.
    /// macOS handles correct A4 pagination, margins, and PDF generation natively.
    ///
    /// Why not use createPDF or NSPrintOperation directly:
    /// - createPDF(rect: fullDocHeight) → unbounded single-page PDF, GB-scale for long docs
    /// - NSPrintOperation without print panel → 16M+ PDF objects, corrupt 50MB+ output
    /// The Print dialog delegates to macOS's PDF subsystem which handles all of this correctly.
    @MainActor static func exportPDF(from webView: WKWebView, suggestedName: String, errorPresenter: ErrorPresenter) {
        let printInfo = NSPrintInfo()
        // A4 paper, 0.5-inch margins, fit content to page width, auto-paginate vertically
        printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic

        let op = webView.printOperation(with: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true

        // Use run() not runModal(for:window) — keyWindow goes nil when menu is active,
        // causing a force-unwrap crash or silent no-op.
        op.run()
    }

    /// Generate PDF to a URL without a save panel — used by MarkViewPDFTester only.
    ///
    /// Uses createPDF with a bounded viewport rect (NOT full scroll height) to produce
    /// a small valid PDF for test validation. Not suitable for exporting long documents.
    @MainActor static func generatePDF(from webView: WKWebView, to url: URL) async -> Bool {
        let viewWidth = webView.bounds.width > 0 ? webView.bounds.width : 800
        let viewHeight = webView.bounds.height > 0 ? webView.bounds.height : 600

        let config = WKPDFConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: viewWidth, height: viewHeight)

        return await withCheckedContinuation { continuation in
            var resumed = false
            func resume(_ value: Bool) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s safety timeout
                resume(false)
            }

            webView.createPDF(configuration: config) { result in
                switch result {
                case .success(let data):
                    let ok = (try? data.write(to: url)) != nil
                    AppLogger.export.info("Test PDF: \(data.count / 1024)KB to \(url.lastPathComponent)")
                    resume(ok)
                case .failure(let error):
                    AppLogger.captureError(error, category: "export", message: "test createPDF failed: \(error.localizedDescription)")
                    resume(false)
                }
            }
        }
    }
}
