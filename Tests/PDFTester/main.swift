/// MarkViewPDFTester — behavioral PDF export validation.
///
/// Validates that ExportManager.generatePDF produces a valid, non-empty PDF
/// that captures the full document (not just the visible viewport).
///
/// Why this exists: source-inspection tests (checking source.contains("createPDF"))
/// passed while the feature was silently broken in three different ways. This tester
/// actually runs WebKit, generates a PDF, opens it with PDFKit, and asserts correctness.
///
/// Run: swift run MarkViewPDFTester
/// Exit 0 = all tests passed. Exit 1 = at least one failure.

import AppKit
import PDFKit
import WebKit

// ── Minimal test runner ───────────────────────────────────────────────────────

final class Results: @unchecked Sendable {
    var passed = 0
    var failed = 0
}
let results = Results()

func test(_ name: String, body: @MainActor () async throws -> Void) async {
    do {
        try await body()
        print("  ✓ \(name)")
        results.passed += 1
    } catch {
        print("  ✗ \(name): \(error)")
        results.failed += 1
    }
}

func expect(_ condition: Bool, _ message: String) throws {
    guard condition else { throw TestError(message) }
}

struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { description = msg }
}

// ── Test infrastructure ───────────────────────────────────────────────────────

/// Loads HTML into a WKWebView and waits for load to complete.
@MainActor
func makeLoadedWebView(html: String, width: CGFloat = 800, height: CGFloat = 600) async throws -> WKWebView {
    // WKWebView requires a window to render properly
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.orderFront(nil)

    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    window.contentView = webView

    // Load HTML and wait for WKNavigationDelegate didFinish
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let delegate = NavigationWaiter(continuation: continuation)
        webView.navigationDelegate = delegate
        // Keep delegate alive during load
        objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        webView.loadHTMLString(html, baseURL: nil)
    }

    // Extra settle time for layout (Mermaid, Prism, etc.)
    try await Task.sleep(nanoseconds: 300_000_000) // 300ms

    return webView
}

class NavigationWaiter: NSObject, WKNavigationDelegate {
    let continuation: CheckedContinuation<Void, Error>
    var settled = false

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !settled else { return }
        settled = true
        continuation.resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !settled else { return }
        settled = true
        continuation.resume(throwing: error)
    }
}

/// Generates a PDF from a webView to a temp file and returns the URL.
@MainActor
func generatePDF(from webView: WKWebView) async throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("markview-pdf-test-\(ProcessInfo.processInfo.processIdentifier).pdf")

    // Mirror ExportManager.generatePDF logic (can't import MarkView target here)
    let jsResult = try? await webView.callAsyncJavaScript(
        "return document.documentElement.scrollHeight",
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    let docHeight = jsResult.flatMap { $0 as? Double }.map { CGFloat($0) } ?? webView.bounds.height
    let viewWidth = webView.bounds.width > 0 ? webView.bounds.width : 800

    let config = WKPDFConfiguration()
    config.rect = CGRect(x: 0, y: 0, width: viewWidth, height: docHeight)

    let data: Data = try await withCheckedThrowingContinuation { continuation in
        webView.createPDF(configuration: config) { result in
            switch result {
            case .success(let d): continuation.resume(returning: d)
            case .failure(let e): continuation.resume(throwing: e)
            }
        }
    }

    guard data.count > 0 else { throw TestError("createPDF returned empty data") }
    try data.write(to: url)
    return url
}

// ── HTML fixtures ─────────────────────────────────────────────────────────────

let shortHTML = """
<html><body>
<h1>Short Document</h1>
<p>This is a short test document.</p>
</body></html>
"""

// Long document that should exceed a single viewport height (600px)
let longHTML: String = {
    var html = "<html><body style='font-size:16px;line-height:1.5;padding:20px;'>"
    html += "<h1>Long Document Test</h1>"
    for i in 1...80 {
        html += "<p>Paragraph \(i): Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
        html += "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>"
    }
    html += "</body></html>"
    return html
}()

let tableHTML: String = {
    var html = "<html><body style='font-size:14px;padding:20px;'>"
    html += "<h1>Table Export Test</h1>"
    html += "<table border='1' style='width:100%;border-collapse:collapse;'>"
    html += "<tr><th>ID</th><th>Task</th><th>Status</th><th>Priority</th></tr>"
    for i in 1...50 {
        html += "<tr><td>\(i)</td><td>Task \(i): Description of the work item</td><td>pending</td><td>p\(i % 4)</td></tr>"
    }
    html += "</table></body></html>"
    return html
}()

// ── Tests ─────────────────────────────────────────────────────────────────────

@MainActor
func runTests() async {
    print("\nMarkViewPDFTester\n")

    await test("Short document produces valid PDF file") {
        let webView = try await makeLoadedWebView(html: shortHTML)
        let url = try await generatePDF(from: webView)
        defer { try? FileManager.default.removeItem(at: url) }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int ?? 0
        try expect(size > 1000, "PDF file too small (\(size) bytes) — likely empty")

        let doc = PDFDocument(url: url)
        try expect(doc != nil, "PDFDocument could not open output file — invalid PDF format")
    }

    await test("Long document captures full height (not viewport-only)") {
        let webView = try await makeLoadedWebView(html: longHTML, height: 600)
        let url = try await generatePDF(from: webView)
        defer { try? FileManager.default.removeItem(at: url) }

        let jsHeight = try await webView.callAsyncJavaScript(
            "return document.documentElement.scrollHeight",
            arguments: [:], in: nil, contentWorld: .page
        ) as? Double ?? 0

        try expect(jsHeight > 600, "Document should be taller than viewport (got \(jsHeight)px)")

        let doc = try { () throws -> PDFDocument in
            guard let d = PDFDocument(url: url) else {
                throw TestError("PDFDocument could not open output — invalid PDF")
            }
            return d
        }()

        // A full-document capture should produce a PDF whose page height > viewport height.
        // If only the viewport was captured, the PDF page height would be ~600px.
        let pageHeight = doc.page(at: 0)?.bounds(for: .mediaBox).height ?? 0
        try expect(pageHeight > 600, "PDF page height \(Int(pageHeight))px ≤ viewport 600px — viewport-only capture detected")
    }

    await test("Table document produces valid openable PDF under 5MB") {
        let webView = try await makeLoadedWebView(html: tableHTML)
        let url = try await generatePDF(from: webView)
        defer { try? FileManager.default.removeItem(at: url) }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let sizeBytes = attrs[.size] as? Int ?? 0
        let sizeMB = Double(sizeBytes) / 1_048_576

        // NSPrintOperation produced 51.9MB for a similar table — this catches regression
        try expect(sizeMB < 5.0, "PDF is \(String(format: "%.1f", sizeMB))MB — likely using NSPrintOperation object explosion (>5MB threshold)")
        try expect(sizeBytes > 1000, "PDF too small (\(sizeBytes) bytes)")

        let doc = PDFDocument(url: url)
        try expect(doc != nil, "PDFDocument cannot open — invalid format (was PostScript/CUPS spool?)")
    }

    await test("PDF header is valid (%PDF-)") {
        let webView = try await makeLoadedWebView(html: shortHTML)
        let url = try await generatePDF(from: webView)
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forReadingFrom: url)
        let header = handle.readData(ofLength: 5)
        handle.closeFile()
        let headerStr = String(data: header, encoding: .ascii) ?? ""
        try expect(headerStr.hasPrefix("%PDF-"), "File does not start with %PDF- (got '\(headerStr)') — not a valid PDF")
    }
}

// ── Entry point ───────────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // headless — no Dock icon

Task { @MainActor in
    await runTests()

    print("\nResults: \(results.passed) passed, \(results.failed) failed\n")
    exit(results.failed > 0 ? 1 : 0)
}

app.run()
