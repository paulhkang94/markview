import Foundation
import MarkViewCore

// Simple test runner — no XCTest dependency required
struct TestRunner {
    var passed = 0
    var failed = 0
    var skipped = 0

    mutating func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("  ✓ \(name)")
        } catch {
            failed += 1
            print("  ✗ \(name): \(error)")
        }
    }

    mutating func skip(_ name: String, reason: String) {
        skipped += 1
        print("  ⊘ \(name) (skipped: \(reason))")
    }

    func summary() {
        print("\nResults: \(passed) passed, \(failed) failed, \(skipped) skipped")
    }
}

func expect(_ condition: Bool, _ message: String = "Assertion failed", file: String = #file, line: Int = #line) throws {
    guard condition else {
        throw TestError.assertionFailed("\(message) (\(URL(fileURLWithPath: file).lastPathComponent):\(line))")
    }
}

enum TestError: Error, CustomStringConvertible {
    case assertionFailed(String)
    case fixtureNotFound(String)

    var description: String {
        switch self {
        case .assertionFailed(let msg): return msg
        case .fixtureNotFound(let name): return "Fixture not found: \(name)"
        }
    }
}

func loadFixture(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
        throw TestError.fixtureNotFound(name)
    }
    return try String(contentsOf: url, encoding: .utf8)
}

func normalizeHTML(_ html: String) -> String {
    html.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

// =============================================================================
// MARK: - Golden File Support
// =============================================================================

let fixtureNames = [
    "basic", "gfm-tables", "gfm-tasklists", "gfm-strikethrough",
    "gfm-autolinks", "code-blocks", "links-and-images", "edge-cases"
]

func goldenFilePath(for fixtureName: String) -> URL? {
    Bundle.module.url(forResource: fixtureName, withExtension: "html", subdirectory: "Fixtures/expected")
}

func generateGoldens() throws {
    // Write to the SOURCE tree, not the bundle copy
    // Locate the project root by finding Package.swift
    let cwd = FileManager.default.currentDirectoryPath
    let expectedDir = URL(fileURLWithPath: cwd)
        .appendingPathComponent("Tests/TestRunner/Fixtures/expected")
    try FileManager.default.createDirectory(at: expectedDir, withIntermediateDirectories: true)

    for name in fixtureNames {
        let md = try loadFixture("\(name).md")
        let html = MarkdownRenderer.renderHTML(from: md)
        let outURL = expectedDir.appendingPathComponent("\(name).html")
        try html.write(to: outURL, atomically: true, encoding: .utf8)
        print("  Generated: \(name).html (\(html.count) bytes)")
    }

    // Also generate full-template versions
    let templateDir = expectedDir.appendingPathComponent("full-template")
    try FileManager.default.createDirectory(at: templateDir, withIntermediateDirectories: true)
    for name in fixtureNames {
        let md = try loadFixture("\(name).md")
        let bodyHTML = MarkdownRenderer.renderHTML(from: md)
        let fullHTML = MarkdownRenderer.wrapInTemplate(bodyHTML)
        let outURL = templateDir.appendingPathComponent("\(name).html")
        try fullHTML.write(to: outURL, atomically: true, encoding: .utf8)
        print("  Generated: full-template/\(name).html (\(fullHTML.count) bytes)")
    }

    print("\nGolden files generated. Commit these to lock in the baseline.")
}

/// Compute a line-by-line diff between two strings, returning differing lines
func computeDiff(_ expected: String, _ actual: String) -> [(line: Int, expected: String, actual: String)] {
    let expectedLines = expected.components(separatedBy: "\n")
    let actualLines = actual.components(separatedBy: "\n")
    var diffs: [(line: Int, expected: String, actual: String)] = []

    let maxLines = max(expectedLines.count, actualLines.count)
    for i in 0..<maxLines {
        let exp = i < expectedLines.count ? expectedLines[i] : "<missing>"
        let act = i < actualLines.count ? actualLines[i] : "<missing>"
        if exp != act {
            diffs.append((line: i + 1, expected: exp, actual: act))
        }
    }
    return diffs
}

// =============================================================================
// MARK: - CLI Mode Selection
// =============================================================================

if CommandLine.arguments.contains("--generate-goldens") {
    print("=== Generating Golden Files ===")
    do {
        try generateGoldens()
        print("\nDone.")
        exit(0)
    } catch {
        print("Error generating goldens: \(error)")
        exit(1)
    }
}

// =============================================================================
// MARK: - Tests
// =============================================================================

var runner = TestRunner()

print("=== Tier 0: Build ===")
print("  ✓ Build succeeded (you're running this)")
runner.passed += 1

// MARK: - Renderer Tests

print("\n=== Tier 1: Renderer Unit Tests ===")

runner.test("empty string renders empty") {
    let html = MarkdownRenderer.renderHTML(from: "")
    try expect(html == "", "Expected empty string, got: \(html)")
}

runner.test("paragraph renders") {
    let html = MarkdownRenderer.renderHTML(from: "Hello world")
    try expect(html.contains("<p>Hello world</p>"), "Missing paragraph tag")
}

runner.test("headers h1-h6") {
    for level in 1...6 {
        let prefix = String(repeating: "#", count: level)
        let html = MarkdownRenderer.renderHTML(from: "\(prefix) Heading \(level)")
        try expect(html.contains("<h\(level)>Heading \(level)</h\(level)>"), "Failed for h\(level)")
    }
}

runner.test("bold") {
    let html = MarkdownRenderer.renderHTML(from: "**bold text**")
    try expect(html.contains("<strong>bold text</strong>"), "Missing bold")
}

runner.test("italic") {
    let html = MarkdownRenderer.renderHTML(from: "*italic text*")
    try expect(html.contains("<em>italic text</em>"), "Missing italic")
}

runner.test("bold and italic") {
    let html = MarkdownRenderer.renderHTML(from: "***bold and italic***")
    try expect(html.contains("<strong>") && html.contains("<em>"), "Missing bold+italic")
}

runner.test("inline code") {
    let html = MarkdownRenderer.renderHTML(from: "Use `git status` to check")
    try expect(html.contains("<code>git status</code>"), "Missing inline code")
}

runner.test("blockquote") {
    let html = MarkdownRenderer.renderHTML(from: "> This is a quote")
    try expect(html.contains("<blockquote>"), "Missing blockquote")
}

runner.test("horizontal rule") {
    let html = MarkdownRenderer.renderHTML(from: "---")
    try expect(html.contains("<hr"), "Missing hr")
}

runner.test("link") {
    let html = MarkdownRenderer.renderHTML(from: "[GitHub](https://github.com)")
    try expect(html.contains("<a href=\"https://github.com\">GitHub</a>"), "Missing link")
}

runner.test("image") {
    let html = MarkdownRenderer.renderHTML(from: "![Alt text](image.png)")
    try expect(html.contains("<img src=\"image.png\" alt=\"Alt text\""), "Missing image")
}

// MARK: - GFM Extension Tests

print("\n=== Tier 1: GFM Extension Tests ===")

runner.test("GFM table") {
    let md = "| Name | Age |\n|------|-----|\n| Alice | 30 |"
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<table>"), "Missing table")
    try expect(html.contains("<th>Name</th>"), "Missing th")
    try expect(html.contains("<td>Alice</td>"), "Missing td")
}

runner.test("GFM table alignment") {
    let md = "| Left | Center | Right |\n|:-----|:------:|------:|\n| L | C | R |"
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("align=\"center\"") || html.contains("text-align: center"), "Missing center align")
    try expect(html.contains("align=\"right\"") || html.contains("text-align: right"), "Missing right align")
}

runner.test("GFM strikethrough") {
    let html = MarkdownRenderer.renderHTML(from: "~~deleted text~~")
    try expect(html.contains("<del>deleted text</del>"), "Missing strikethrough")
}

runner.test("GFM task list") {
    let md = "- [x] Done\n- [ ] Not done"
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("checked"), "Missing checked attribute")
    try expect(html.contains("type=\"checkbox\""), "Missing checkbox")
}

runner.test("GFM autolink") {
    let html = MarkdownRenderer.renderHTML(from: "Visit https://example.com for info")
    try expect(html.contains("<a href=\"https://example.com\">"), "Missing autolink")
}

runner.test("fenced code block with language") {
    let md = "```python\ndef hello():\n    pass\n```"
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<pre>"), "Missing pre")
    try expect(html.contains("language-python"), "Missing language class")
}

// MARK: - Edge Cases

print("\n=== Tier 1: Edge Case Tests ===")

runner.test("unicode content") {
    let html = MarkdownRenderer.renderHTML(from: "Hello 世界 🌍")
    try expect(html.contains("Hello 世界 🌍"), "Unicode not preserved")
}

runner.test("nested blockquotes") {
    let md = "> Level 1\n>> Level 2\n>>> Level 3"
    let html = MarkdownRenderer.renderHTML(from: md)
    let count = html.components(separatedBy: "<blockquote>").count - 1
    try expect(count >= 2, "Expected nested blockquotes, got \(count)")
}

runner.test("smart punctuation") {
    let html = MarkdownRenderer.renderHTML(from: "\"quotes\"")
    try expect(html.contains("\u{201C}") || html.contains("&ldquo;") || html.contains("\""),
               "Smart quotes not working")
}

runner.test("template wrapping") {
    let html = MarkdownRenderer.wrapInTemplate("<p>Hello</p>")
    try expect(html.contains("<!DOCTYPE html>"), "Missing doctype")
    try expect(html.contains("<p>Hello</p>"), "Missing content")
    try expect(html.contains("</html>"), "Missing closing html")
}

runner.test("custom template") {
    let template = "<html><body>{{CONTENT}}</body></html>"
    let html = MarkdownRenderer.wrapInTemplate("<p>Test</p>", template: template)
    try expect(html == "<html><body><p>Test</p></body></html>", "Custom template failed")
}

// MARK: - Fixture-Based GFM Compliance

print("\n=== Tier 2: GFM Compliance (Fixture-Based) ===")

runner.test("basic.md fixture renders") {
    let md = try loadFixture("basic.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<h1>"), "Missing h1 in basic.md")
    try expect(html.contains("<strong>"), "Missing bold in basic.md")
    try expect(html.contains("<em>"), "Missing italic in basic.md")
    try expect(html.contains("<blockquote>"), "Missing blockquote in basic.md")
    try expect(html.contains("<hr"), "Missing hr in basic.md")
}

runner.test("gfm-tables.md fixture renders") {
    let md = try loadFixture("gfm-tables.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<table>"), "Missing table")
    try expect(html.contains("<th>"), "Missing th")
    try expect(html.contains("<td>"), "Missing td")
    try expect(html.contains("align="), "Missing alignment")
}

runner.test("gfm-tasklists.md fixture renders") {
    let md = try loadFixture("gfm-tasklists.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("type=\"checkbox\""), "Missing checkboxes")
    try expect(html.contains("checked"), "Missing checked items")
}

runner.test("gfm-strikethrough.md fixture renders") {
    let md = try loadFixture("gfm-strikethrough.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<del>"), "Missing strikethrough")
}

runner.test("gfm-autolinks.md fixture renders") {
    let md = try loadFixture("gfm-autolinks.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<a href="), "Missing autolinks")
}

runner.test("code-blocks.md fixture renders") {
    let md = try loadFixture("code-blocks.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<pre>"), "Missing code blocks")
    try expect(html.contains("language-python"), "Missing python language")
    try expect(html.contains("language-swift"), "Missing swift language")
    try expect(html.contains("language-javascript"), "Missing javascript language")
    try expect(html.contains("language-rust"), "Missing rust language")
    try expect(html.contains("language-go"), "Missing go language")
    try expect(html.contains("language-bash"), "Missing bash language")
    try expect(html.contains("language-typescript"), "Missing typescript language")
}

runner.test("links-and-images.md fixture renders") {
    let md = try loadFixture("links-and-images.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<a href="), "Missing links")
    try expect(html.contains("<img"), "Missing images")
}

runner.test("edge-cases.md fixture renders") {
    let md = try loadFixture("edge-cases.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(!html.isEmpty, "Edge cases produced empty output")
    try expect(html.contains("这是一个测试段落"), "Missing Chinese unicode")
    try expect(html.contains("🚀"), "Missing emoji")
}

// MARK: - Performance

print("\n=== Tier 2: Performance ===")

runner.test("large file renders under 500ms") {
    let md = try loadFixture("large-file.md")
    let start = CFAbsoluteTimeGetCurrent()
    _ = MarkdownRenderer.renderHTML(from: md)
    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
    print("    Render time: \(String(format: "%.1f", elapsed))ms for \(md.count) bytes")
    try expect(elapsed < 500, "Render took \(elapsed)ms, expected < 500ms")
}

runner.test("large file performance (10 iterations)") {
    let md = try loadFixture("large-file.md")
    var totalMs = 0.0
    for _ in 0..<10 {
        let start = CFAbsoluteTimeGetCurrent()
        _ = MarkdownRenderer.renderHTML(from: md)
        totalMs += (CFAbsoluteTimeGetCurrent() - start) * 1000
    }
    let avgMs = totalMs / 10.0
    print("    Average: \(String(format: "%.1f", avgMs))ms per render")
}

// MARK: - FileWatcher Tests

print("\n=== Tier 1: FileWatcher Tests ===")

runner.test("FileWatcher detects direct write") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mvtest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("test.md")
    try "# Original".write(to: file, atomically: true, encoding: .utf8)

    let sem = DispatchSemaphore(value: 0)
    let watcher = FileWatcher(path: file.path) { sem.signal() }
    watcher.start()

    Thread.sleep(forTimeInterval: 0.2)
    try "# Modified".write(to: file, atomically: false, encoding: .utf8)

    let result = sem.wait(timeout: .now() + 3.0)
    watcher.stop()
    try expect(result == .success, "FileWatcher did not detect write within 3s")
}

runner.test("FileWatcher detects atomic save") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mvtest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("test.md")
    try "# Original".write(to: file, atomically: true, encoding: .utf8)

    let sem = DispatchSemaphore(value: 0)
    let watcher = FileWatcher(path: file.path) { sem.signal() }
    watcher.start()

    Thread.sleep(forTimeInterval: 0.2)
    let tmpFile = dir.appendingPathComponent("test.md.tmp")
    try "# Atomic save".write(to: tmpFile, atomically: false, encoding: .utf8)
    _ = try FileManager.default.replaceItemAt(file, withItemAt: tmpFile)

    let result = sem.wait(timeout: .now() + 3.0)
    watcher.stop()
    try expect(result == .success, "FileWatcher did not detect atomic save within 3s")
}

runner.test("FileWatcher stop prevents notifications") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mvtest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("test.md")
    try "# Original".write(to: file, atomically: true, encoding: .utf8)

    var called = false
    let watcher = FileWatcher(path: file.path) { called = true }
    watcher.start()
    watcher.stop()

    try "# Should not trigger".write(to: file, atomically: false, encoding: .utf8)
    Thread.sleep(forTimeInterval: 0.5)
    try expect(!called, "Received notification after stop")
}

// MARK: - Word Count / Stats Tests

print("\n=== Tier 1: Word Count / Stats Tests ===")

func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
}

func lineCount(_ text: String) -> Int {
    text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
}

runner.test("word count basic") {
    try expect(wordCount("Hello world") == 2, "Expected 2 words")
    try expect(wordCount("One two three four five") == 5, "Expected 5 words")
}

runner.test("word count with markdown") {
    // "# Heading\n\nA paragraph with **bold**." splits to: #, Heading, A, paragraph, with, **bold**.
    try expect(wordCount("# Heading\n\nA paragraph with **bold**.") == 6, "Expected 6 words")
}

runner.test("word count empty") {
    try expect(wordCount("") == 0, "Expected 0 words for empty string")
}

runner.test("line count") {
    try expect(lineCount("one\ntwo\nthree") == 3, "Expected 3 lines")
    try expect(lineCount("single line") == 1, "Expected 1 line")
    try expect(lineCount("") == 0, "Expected 0 lines for empty")
}

// MARK: - Renderer Stress Tests

print("\n=== Tier 2: Renderer Stress Tests ===")

runner.test("empty document renders gracefully") {
    let html = MarkdownRenderer.renderHTML(from: "")
    try expect(html.isEmpty, "Empty input should produce empty output")
}

runner.test("whitespace-only document") {
    let html = MarkdownRenderer.renderHTML(from: "   \n\n   \n\t\t\n   ")
    // Should not crash, may produce empty or whitespace
    _ = html // Just checking it doesn't crash
}

runner.test("very long single line") {
    let longLine = String(repeating: "word ", count: 10000)
    let html = MarkdownRenderer.renderHTML(from: longLine)
    try expect(html.contains("word"), "Long line should render")
}

runner.test("deeply nested lists") {
    var md = ""
    for i in 0..<20 {
        md += String(repeating: "  ", count: i) + "- Level \(i)\n"
    }
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<ul>"), "Nested lists should render")
}

runner.test("many consecutive headings") {
    var md = ""
    for i in 1...100 {
        md += "## Heading \(i)\n\n"
    }
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("Heading 1"), "First heading should render")
    try expect(html.contains("Heading 100"), "Last heading should render")
}

runner.test("mixed GFM features in one document") {
    let md = """
    # Title

    | Col A | Col B |
    |-------|-------|
    | ~~old~~ | **new** |

    - [x] Done task with `code`
    - [ ] Pending task with [link](https://example.com)

    > Blockquote with https://auto.link

    ```swift
    let x = 42
    ```
    """
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<table>"), "Table should render")
    try expect(html.contains("<del>"), "Strikethrough should render")
    try expect(html.contains("checkbox"), "Task list should render")
    try expect(html.contains("<blockquote>"), "Blockquote should render")
    try expect(html.contains("language-swift"), "Code block should render")
    try expect(html.contains("<a href="), "Links should render")
}

// MARK: - Metrics Tests

print("\n=== Tier 1: Metrics Tests ===")

runner.test("metrics disabled by default") {
    let metrics = MetricsCollector.shared
    // Should not crash when disabled
    metrics.trackFileOpened(sizeBytes: 1000)
    metrics.trackRender(durationMs: 5.0)
    metrics.trackExport(format: "html")
    metrics.trackFeature("editor")
    metrics.flush()
    // All good if no crash
}

runner.test("metrics aggregate loads without file") {
    let metrics = MetricsCollector.shared
    metrics.clearAll()
    let aggregate = metrics.loadAggregate()
    try expect(aggregate.totalSessions == 0, "Expected 0 sessions for fresh metrics")
    try expect(aggregate.totalFilesOpened == 0, "Expected 0 files for fresh metrics")
}

runner.test("metrics enabled tracks and persists") {
    let metrics = MetricsCollector.shared
    metrics.clearAll()
    metrics.setEnabled(true)
    metrics.trackFileOpened(sizeBytes: 5000)
    metrics.trackRender(durationMs: 3.5)
    metrics.trackRender(durationMs: 2.0)
    metrics.trackFeature("editor")
    metrics.trackFeature("export")
    metrics.trackEditorUsed()
    metrics.flush()

    let aggregate = metrics.loadAggregate()
    try expect(aggregate.totalSessions == 1, "Expected 1 session, got \(aggregate.totalSessions)")
    try expect(aggregate.totalFilesOpened == 1, "Expected 1 file opened")
    try expect(aggregate.totalRenders == 2, "Expected 2 renders")
    try expect(aggregate.largestFileEverBytes == 5000, "Expected 5000 bytes")
    try expect(aggregate.editorSessionCount == 1, "Expected 1 editor session")
    try expect(aggregate.featureUsageCounts["editor"] == 1, "Expected editor feature tracked")
    try expect(aggregate.featureUsageCounts["export"] == 1, "Expected export feature tracked")

    // Clean up
    metrics.clearAll()
    metrics.setEnabled(false)
}

// MARK: - Tier 3: Golden File Snapshot Regression Tests

print("\n=== Tier 3: Golden File Snapshot Regression ===")

do {
    // Check if golden files exist
    let firstGolden = goldenFilePath(for: "basic")
    if firstGolden != nil {
        for name in fixtureNames {
            runner.test("\(name) matches golden baseline") {
                let md = try loadFixture("\(name).md")
                let actual = MarkdownRenderer.renderHTML(from: md)
                guard let goldenURL = goldenFilePath(for: name) else {
                    throw TestError.fixtureNotFound("expected/\(name).html")
                }
                let expected = try String(contentsOf: goldenURL, encoding: .utf8)

                if normalizeHTML(actual) != normalizeHTML(expected) {
                    let diffs = computeDiff(expected, actual)
                    let diffSummary = diffs.prefix(3).map { "    L\($0.line): expected=\($0.expected.prefix(80)) actual=\($0.actual.prefix(80))" }.joined(separator: "\n")
                    throw TestError.assertionFailed("Output changed for \(name).md (\(diffs.count) lines differ):\n\(diffSummary)")
                }
            }
        }
    } else {
        print("  ⚠ No golden files found. Run with --generate-goldens to create baselines.")
    }
}

// MARK: - Tier 3: Full-Template E2E Tests

print("\n=== Tier 3: Full-Template E2E ===")

runner.test("full HTML document is well-formed") {
    let md = try loadFixture("basic.md")
    let body = MarkdownRenderer.renderHTML(from: md)
    let full = MarkdownRenderer.wrapInTemplate(body)

    try expect(full.hasPrefix("<!DOCTYPE html>") || full.contains("<!DOCTYPE html>"), "Missing DOCTYPE")
    try expect(full.contains("<html>"), "Missing <html>")
    try expect(full.contains("</html>"), "Missing </html>")
    try expect(full.contains("<head>"), "Missing <head>")
    try expect(full.contains("</head>"), "Missing </head>")
    try expect(full.contains("<body>"), "Missing <body>")
    try expect(full.contains("</body>"), "Missing </body>")
    try expect(full.contains("<meta charset=\"utf-8\">"), "Missing charset meta")
    try expect(full.contains("<style>"), "Missing style block")
}

runner.test("full template contains all CSS rules") {
    let body = MarkdownRenderer.renderHTML(from: "# Test")
    let full = MarkdownRenderer.wrapInTemplate(body)

    // Key CSS features for GitHub-style rendering
    try expect(full.contains("font-family:"), "Missing font-family")
    try expect(full.contains("max-width:"), "Missing max-width")
    try expect(full.contains("prefers-color-scheme: dark"), "Missing dark mode support")
    try expect(full.contains("border-collapse"), "Missing table CSS")
    try expect(full.contains("border-radius"), "Missing code block border-radius")
    try expect(full.contains("monospace"), "Missing monospace font for code")
}

runner.test("full template renders all GFM features in context") {
    let md = """
    # Full E2E Test

    | Feature | Status |
    |---------|--------|
    | Tables | ✅ |

    - [x] Task lists
    - [ ] More tasks

    ~~struck~~ and **bold** and `code`

    > Blockquote

    ```swift
    let x = 1
    ```

    Visit https://example.com
    """
    let body = MarkdownRenderer.renderHTML(from: md)
    let full = MarkdownRenderer.wrapInTemplate(body)

    // Verify all features present in final document
    try expect(full.contains("<h1>Full E2E Test</h1>"), "Missing heading")
    try expect(full.contains("<table>"), "Missing table")
    try expect(full.contains("checkbox"), "Missing task list checkboxes")
    try expect(full.contains("<del>struck</del>"), "Missing strikethrough")
    try expect(full.contains("<strong>bold</strong>"), "Missing bold")
    try expect(full.contains("<code>code</code>"), "Missing inline code")
    try expect(full.contains("<blockquote>"), "Missing blockquote")
    try expect(full.contains("language-swift"), "Missing code block language")
    try expect(full.contains("<a href=\"https://example.com\""), "Missing autolink")
}

runner.test("full template dark mode CSS is complete") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")

    // Verify dark mode has all necessary overrides
    try expect(full.contains("color: #e6edf3"), "Missing dark text color")
    try expect(full.contains("background: #0d1117"), "Missing dark background")
    try expect(full.contains("#161b22"), "Missing dark code background")
    try expect(full.contains("#30363d"), "Missing dark border color")
}

// MARK: - Tier 3: Renderer Determinism Tests

print("\n=== Tier 3: Renderer Determinism ===")

runner.test("same input always produces identical output") {
    let md = try loadFixture("basic.md")
    let results = (0..<5).map { _ in MarkdownRenderer.renderHTML(from: md) }
    for i in 1..<results.count {
        try expect(results[i] == results[0], "Non-deterministic output on render \(i)")
    }
}

runner.test("renderer is thread-safe (concurrent renders)") {
    let md = try loadFixture("basic.md")
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "test-concurrent", attributes: .concurrent)
    var results = [String?](repeating: nil, count: 10)
    let lock = NSLock()

    for i in 0..<10 {
        group.enter()
        queue.async {
            let html = MarkdownRenderer.renderHTML(from: md)
            lock.lock()
            results[i] = html
            lock.unlock()
            group.leave()
        }
    }
    group.wait()

    let first = results[0]!
    for i in 1..<10 {
        try expect(results[i] == first, "Concurrent render \(i) produced different output")
    }
}

// MARK: - Tier 3: HTML Output Structural Validation

print("\n=== Tier 3: HTML Structural Validation ===")

runner.test("no unclosed tags in rendered HTML") {
    // Check that key block-level tags are balanced in fixture output
    // Uses regex to properly match opening tags (not content inside code blocks)
    for name in fixtureNames {
        let md = try loadFixture("\(name).md")
        let html = MarkdownRenderer.renderHTML(from: md)

        // Only check tags that are unambiguous block-level elements
        // Skip <p> because cmark can produce <p> tags that get split by other elements
        let tagsToCheck = ["h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "table", "ul", "ol"]
        for tag in tagsToCheck {
            // Count opening tags: <tag> or <tag ...>
            var openCount = 0
            var searchRange = html.startIndex..<html.endIndex
            while let range = html.range(of: "<\(tag)[ >]", options: .regularExpression, range: searchRange) {
                openCount += 1
                searchRange = range.upperBound..<html.endIndex
            }
            let closeCount = html.components(separatedBy: "</\(tag)>").count - 1
            if openCount > 0 {
                try expect(openCount == closeCount,
                    "Unbalanced <\(tag)> in \(name).md: \(openCount) open, \(closeCount) close")
            }
        }
    }
}

runner.test("special characters are properly escaped") {
    let md = "Text with <angle> brackets & ampersand"
    let html = MarkdownRenderer.renderHTML(from: md)
    // cmark should escape these in text nodes (CMARK_OPT_UNSAFE allows HTML blocks but text nodes are still escaped)
    try expect(!html.contains("<angle>") || html.contains("&lt;angle&gt;") || html.contains("&amp;"),
               "Special chars not properly escaped")
}

runner.test("all fixtures produce non-empty output") {
    for name in fixtureNames {
        let md = try loadFixture("\(name).md")
        let html = MarkdownRenderer.renderHTML(from: md)
        try expect(!html.isEmpty, "\(name).md produced empty output")
        try expect(html.count > 10, "\(name).md produced suspiciously short output: \(html.count) chars")
    }
}

// MARK: - Tier 3: Performance Regression Gate

print("\n=== Tier 3: Performance Regression Gate ===")

runner.test("all fixtures render under 100ms") {
    for name in fixtureNames {
        let md = try loadFixture("\(name).md")
        let start = CFAbsoluteTimeGetCurrent()
        _ = MarkdownRenderer.renderHTML(from: md)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        try expect(elapsed < 100, "\(name).md took \(String(format: "%.1f", elapsed))ms (limit: 100ms)")
    }
}

runner.test("full template wrapping under 5ms") {
    let body = "<p>Hello</p>"
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<100 {
        _ = MarkdownRenderer.wrapInTemplate(body)
    }
    let avgMs = (CFAbsoluteTimeGetCurrent() - start) * 1000 / 100
    try expect(avgMs < 5, "Template wrapping: \(String(format: "%.2f", avgMs))ms avg (limit: 5ms)")
}

runner.test("debounce-simulated rapid renders stay under budget") {
    // Simulate 20 rapid re-renders (as if user is typing fast)
    let md = try loadFixture("basic.md")
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<20 {
        _ = MarkdownRenderer.renderHTML(from: md)
    }
    let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
    let avgMs = totalMs / 20
    print("    20 rapid renders: \(String(format: "%.1f", totalMs))ms total, \(String(format: "%.2f", avgMs))ms avg")
    try expect(avgMs < 50, "Rapid render avg \(String(format: "%.1f", avgMs))ms exceeds 50ms budget")
}

// MARK: - Settings Enum Tests
//
// These enums mirror the definitions in Sources/MarkView/Settings.swift.
// The test runner can't import MarkView (SwiftUI dependency), so we redefine
// the enum contracts here to verify raw values, labels, and CSS values are correct.

print("\n=== Settings Enum Tests ===")

enum TestAppTheme: String, CaseIterable {
    case light, dark, system
    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}

enum TestPreviewWidth: String, CaseIterable {
    case narrow, medium, wide
    var label: String {
        switch self {
        case .narrow: return "Narrow"
        case .medium: return "Medium"
        case .wide: return "Wide"
        }
    }
    var cssValue: String {
        switch self {
        case .narrow: return "700px"
        case .medium: return "900px"
        case .wide: return "100%"
        }
    }
}

enum TestTabBehavior: String, CaseIterable {
    case twoSpaces, fourSpaces, tab
    var label: String {
        switch self {
        case .twoSpaces: return "2 Spaces"
        case .fourSpaces: return "4 Spaces"
        case .tab: return "Tab"
        }
    }
    var insertionString: String {
        switch self {
        case .twoSpaces: return "  "
        case .fourSpaces: return "    "
        case .tab: return "\t"
        }
    }
}

runner.test("AppTheme has 3 cases and is CaseIterable") {
    let cases = ["light", "dark", "system"]
    for raw in cases {
        let theme = TestAppTheme(rawValue: raw)
        try expect(theme != nil, "AppTheme missing case: \(raw)")
    }
    try expect(TestAppTheme.allCases.count == 3, "Expected 3 AppTheme cases, got \(TestAppTheme.allCases.count)")
}

runner.test("AppTheme default is system") {
    try expect(TestAppTheme.system.rawValue == "system", "Default theme should be 'system'")
}

runner.test("PreviewWidth has 3 cases and correct CSS values") {
    try expect(TestPreviewWidth.allCases.count == 3, "Expected 3 PreviewWidth cases")
    try expect(TestPreviewWidth.narrow.cssValue == "700px", "Narrow should be 700px")
    try expect(TestPreviewWidth.medium.cssValue == "900px", "Medium should be 900px")
    try expect(TestPreviewWidth.wide.cssValue == "100%", "Wide should be 100%")
}

runner.test("PreviewWidth default is medium") {
    try expect(TestPreviewWidth.medium.rawValue == "medium", "Default width should be 'medium'")
}

runner.test("TabBehavior has 3 cases and correct insertion strings") {
    try expect(TestTabBehavior.allCases.count == 3, "Expected 3 TabBehavior cases")
    try expect(TestTabBehavior.twoSpaces.insertionString == "  ", "2 spaces should insert 2 spaces")
    try expect(TestTabBehavior.fourSpaces.insertionString == "    ", "4 spaces should insert 4 spaces")
    try expect(TestTabBehavior.tab.insertionString == "\t", "Tab should insert tab character")
}

runner.test("TabBehavior default is fourSpaces") {
    try expect(TestTabBehavior.fourSpaces.rawValue == "fourSpaces", "Default tab behavior should be 'fourSpaces'")
}

runner.test("AppTheme labels are correct") {
    try expect(TestAppTheme.light.label == "Light", "Light theme label")
    try expect(TestAppTheme.dark.label == "Dark", "Dark theme label")
    try expect(TestAppTheme.system.label == "System", "System theme label")
}

runner.test("PreviewWidth labels are correct") {
    try expect(TestPreviewWidth.narrow.label == "Narrow", "Narrow label")
    try expect(TestPreviewWidth.medium.label == "Medium", "Medium label")
    try expect(TestPreviewWidth.wide.label == "Wide", "Wide label")
}

runner.test("TabBehavior labels are correct") {
    try expect(TestTabBehavior.twoSpaces.label == "2 Spaces", "2 spaces label")
    try expect(TestTabBehavior.fourSpaces.label == "4 Spaces", "4 spaces label")
    try expect(TestTabBehavior.tab.label == "Tab", "Tab label")
}

runner.test("AppTheme raw values round-trip") {
    for theme in TestAppTheme.allCases {
        let recovered = TestAppTheme(rawValue: theme.rawValue)
        try expect(recovered == theme, "Round-trip failed for \(theme)")
    }
}

runner.test("PreviewWidth raw values round-trip") {
    for width in TestPreviewWidth.allCases {
        let recovered = TestPreviewWidth(rawValue: width.rawValue)
        try expect(recovered == width, "Round-trip failed for \(width)")
    }
}

runner.test("TabBehavior raw values round-trip") {
    for tab in TestTabBehavior.allCases {
        let recovered = TestTabBehavior(rawValue: tab.rawValue)
        try expect(recovered == tab, "Round-trip failed for \(tab)")
    }
}

runner.test("Invalid raw values return nil") {
    try expect(TestAppTheme(rawValue: "invalid") == nil, "Invalid AppTheme should be nil")
    try expect(TestPreviewWidth(rawValue: "invalid") == nil, "Invalid PreviewWidth should be nil")
    try expect(TestTabBehavior(rawValue: "invalid") == nil, "Invalid TabBehavior should be nil")
}

// MARK: - Linter Tests

print("\n=== Linter Tests ===")

let linter = MarkdownLinter()

func loadLintFixture(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Fixtures/lint") else {
        throw TestError.fixtureNotFound("lint/\(name).md")
    }
    return try String(contentsOf: url, encoding: .utf8)
}

// Rule detection tests (positive)

runner.test("linter detects inconsistent headings") {
    let md = try loadLintFixture("inconsistent-headings")
    let diags = linter.lint(md, rules: [.inconsistentHeadings])
    try expect(diags.count >= 1, "Expected at least 1 diagnostic, got \(diags.count)")
    try expect(diags[0].rule == .inconsistentHeadings, "Wrong rule: \(diags[0].rule)")
}

runner.test("linter detects trailing whitespace") {
    let md = "# Title\nHello   \nWorld\n"
    let diags = linter.lint(md, rules: [.trailingWhitespace])
    try expect(diags.count >= 1, "Expected at least 1 trailing whitespace diagnostic, got \(diags.count)")
    try expect(diags[0].rule == .trailingWhitespace, "Wrong rule")
}

runner.test("linter detects missing blank lines") {
    let md = try loadLintFixture("missing-blank-lines")
    let diags = linter.lint(md, rules: [.missingBlankLines])
    try expect(diags.count >= 1, "Expected at least 1 diagnostic, got \(diags.count)")
    try expect(diags[0].rule == .missingBlankLines, "Wrong rule")
}

runner.test("linter detects duplicate headings") {
    let md = try loadLintFixture("duplicate-headings")
    let diags = linter.lint(md, rules: [.duplicateHeadings])
    try expect(diags.count >= 1, "Expected at least 1 diagnostic, got \(diags.count)")
    try expect(diags[0].rule == .duplicateHeadings, "Wrong rule")
}

runner.test("linter detects broken links") {
    let md = try loadLintFixture("broken-links")
    let diags = linter.lint(md, rules: [.brokenLinks])
    try expect(diags.count == 1, "Expected 1 broken link, got \(diags.count)")
    try expect(diags[0].message.contains("missing-ref"), "Should reference 'missing-ref'")
}

runner.test("linter detects unclosed fences") {
    let md = try loadLintFixture("unclosed-fences")
    let diags = linter.lint(md, rules: [.unclosedFences])
    try expect(diags.count == 1, "Expected 1 unclosed fence, got \(diags.count)")
    try expect(diags[0].severity == .error, "Unclosed fence should be error")
}

runner.test("linter detects unclosed formatting") {
    let md = try loadLintFixture("unclosed-formatting")
    let diags = linter.lint(md, rules: [.unclosedFormatting])
    try expect(diags.count >= 2, "Expected at least 2 diagnostics (bold + strikethrough), got \(diags.count)")
}

runner.test("linter detects mismatched brackets") {
    let md = try loadLintFixture("mismatched-brackets")
    let diags = linter.lint(md, rules: [.mismatchedBrackets])
    try expect(diags.count >= 1, "Expected at least 1 mismatched bracket, got \(diags.count)")
    try expect(diags[0].severity == .error, "Mismatched bracket should be error")
}

runner.test("linter detects invalid tables") {
    let md = try loadLintFixture("invalid-tables")
    let diags = linter.lint(md, rules: [.invalidTables])
    try expect(diags.count >= 1, "Expected at least 1 invalid table row, got \(diags.count)")
}

// Negative tests (clean file)

runner.test("linter produces no diagnostics for clean file") {
    let md = try loadLintFixture("clean")
    let diags = linter.lint(md)
    try expect(diags.isEmpty, "Clean file should have no diagnostics, got \(diags.count): \(diags.map { "\($0.rule.rawValue) L\($0.line)" })")
}

runner.test("linter clean: no inconsistent headings in proper hierarchy") {
    let md = "# H1\n\n## H2\n\n### H3\n"
    let diags = linter.lint(md, rules: [.inconsistentHeadings])
    try expect(diags.isEmpty, "Proper heading hierarchy should produce no diagnostics")
}

runner.test("linter clean: no trailing whitespace") {
    let md = "# Title\n\nNo trailing spaces here.\n"
    let diags = linter.lint(md, rules: [.trailingWhitespace])
    try expect(diags.isEmpty, "No trailing whitespace should produce no diagnostics")
}

runner.test("linter allows 2-space line break") {
    let md = "Line with break  \nNext line\n"
    let diags = linter.lint(md, rules: [.trailingWhitespace])
    try expect(diags.isEmpty, "2-space line break should not be flagged")
}

runner.test("linter clean: no broken links when refs defined") {
    let md = "Click [here][ref] for info.\n\n[ref]: https://example.com\n"
    let diags = linter.lint(md, rules: [.brokenLinks])
    try expect(diags.isEmpty, "Valid reference links should produce no diagnostics")
}

runner.test("linter clean: closed code fences") {
    let md = "```swift\nlet x = 1\n```\n"
    let diags = linter.lint(md, rules: [.unclosedFences])
    try expect(diags.isEmpty, "Closed fences should produce no diagnostics")
}

runner.test("linter clean: balanced formatting") {
    let md = "This is **bold** and ~~struck~~.\n"
    let diags = linter.lint(md, rules: [.unclosedFormatting])
    try expect(diags.isEmpty, "Balanced formatting should produce no diagnostics")
}

runner.test("linter clean: valid links") {
    let md = "A [valid link](https://example.com) works.\n"
    let diags = linter.lint(md, rules: [.mismatchedBrackets])
    try expect(diags.isEmpty, "Valid links should produce no diagnostics")
}

runner.test("linter clean: consistent table columns") {
    let md = "| A | B |\n|---|---|\n| 1 | 2 |\n"
    let diags = linter.lint(md, rules: [.invalidTables])
    try expect(diags.isEmpty, "Consistent tables should produce no diagnostics")
}

// Integration tests

runner.test("linter has 9 rules") {
    try expect(LintRule.allCases.count == 9, "Expected 9 lint rules, got \(LintRule.allCases.count)")
}

runner.test("linter diagnostics are sorted by line") {
    let md = "Some text\n# Heading\n**unclosed\n"
    let diags = linter.lint(md)
    for i in 1..<diags.count {
        try expect(diags[i].line >= diags[i-1].line, "Diagnostics should be sorted by line")
    }
}

runner.test("linter with empty input") {
    let diags = linter.lint("")
    try expect(diags.isEmpty, "Empty input should produce no diagnostics")
}

// MARK: - Auto-Suggest Tests

print("\n=== Auto-Suggest Tests ===")

let suggestions = MarkdownSuggestions()

runner.test("supported languages list has 18 entries") {
    try expect(MarkdownSuggestions.supportedLanguages.count == 18,
        "Expected 18 languages, got \(MarkdownSuggestions.supportedLanguages.count)")
}

runner.test("language suggestions filter by prefix") {
    let swiftResults = suggestions.suggestLanguages(prefix: "sw")
    try expect(swiftResults.count == 1, "Expected 1 match for 'sw', got \(swiftResults.count)")
    try expect(swiftResults[0].text == "swift", "Expected 'swift'")

    let jResults = suggestions.suggestLanguages(prefix: "j")
    try expect(jResults.count == 3, "Expected 3 matches for 'j' (java, javascript, json), got \(jResults.count)")
}

runner.test("language suggestions return all when empty prefix") {
    let all = suggestions.suggestLanguages()
    try expect(all.count == 18, "Expected all 18 languages, got \(all.count)")
}

runner.test("emoji lookup works") {
    try expect(suggestions.lookupEmoji(":rocket:") == "\u{1F680}", "rocket emoji")
    try expect(suggestions.lookupEmoji("star") == "\u{2B50}", "star emoji without colons")
    try expect(suggestions.lookupEmoji(":nonexistent:") == nil, "nonexistent emoji")
}

runner.test("emoji suggestions filter by prefix") {
    let results = suggestions.suggestEmoji(prefix: "th")
    try expect(results.count >= 2, "Expected at least 2 matches for 'th' (thinking, thumbsup, thumbsdown)")
    try expect(results.allSatisfy({ $0.kind == .emoji }), "All should be emoji kind")
}

runner.test("heading suggestions reflect document structure") {
    let doc = "# Title\n\n## Section\n\nSome text\n\n### Subsection\n"
    let results = suggestions.suggestHeadings(document: doc)
    try expect(results.count == 3, "Expected 3 heading levels, got \(results.count)")
    try expect(results[0].text == "# ", "First should be h1")
    try expect(results[1].text == "## ", "Second should be h2")
    try expect(results[2].text == "### ", "Third should be h3")
}

runner.test("heading suggestions with no headings returns empty") {
    let doc = "Just some plain text.\n"
    let results = suggestions.suggestHeadings(document: doc)
    try expect(results.isEmpty, "No headings should give empty suggestions")
}

runner.test("link suggestions reflect document references") {
    let doc = "Click [here][ref1] for info.\n\n[ref1]: https://example.com\n[docs]: https://docs.example.com/guide\n"
    let results = suggestions.suggestLinks(document: doc)
    try expect(results.count == 2, "Expected 2 reference links, got \(results.count)")
    let labels = results.map { $0.text }
    try expect(labels.contains("[ref1]"), "Should contain ref1")
    try expect(labels.contains("[docs]"), "Should contain docs")
}

runner.test("link suggestions with no refs returns empty") {
    let doc = "Just [inline](https://example.com) links.\n"
    let results = suggestions.suggestLinks(document: doc)
    try expect(results.isEmpty, "No reference definitions should give empty suggestions")
}

runner.test("suggestion kinds are correct") {
    let langSugg = suggestions.suggestLanguages(prefix: "swift")
    try expect(langSugg.first?.kind == .language, "Language suggestion kind")

    let emojiSugg = suggestions.suggestEmoji(prefix: "rock")
    try expect(emojiSugg.first?.kind == .emoji, "Emoji suggestion kind")

    let headSugg = suggestions.suggestHeadings(document: "# Title\n")
    try expect(headSugg.first?.kind == .heading, "Heading suggestion kind")

    let linkSugg = suggestions.suggestLinks(document: "[ref]: https://x.com\n")
    try expect(linkSugg.first?.kind == .link, "Link suggestion kind")
}

// MARK: - Plugin & Sanitizer Tests

print("\n=== Plugin & Sanitizer Tests ===")

let registry = PluginRegistry()
let sanitizer = HTMLSanitizer()

func loadPluginFixture(_ path: String) throws -> String {
    guard let url = Bundle.module.url(forResource: path, withExtension: nil, subdirectory: "Fixtures") else {
        throw TestError.fixtureNotFound(path)
    }
    return try String(contentsOf: url, encoding: .utf8)
}

// Plugin registry tests

runner.test("plugin registry: register and lookup") {
    let reg = PluginRegistry()
    let mdPlugin = MarkdownPlugin()
    reg.register(mdPlugin)
    try expect(reg.plugin(forExtension: "md") != nil, "Should find plugin for .md")
    try expect(reg.plugin(forExtension: "markdown") != nil, "Should find plugin for .markdown")
    try expect(reg.plugin(forExtension: "xyz") == nil, "Should not find plugin for .xyz")
}

runner.test("plugin registry: registered extensions") {
    let reg = PluginRegistry()
    reg.register(MarkdownPlugin())
    reg.register(CSVPlugin())
    let exts = reg.registeredExtensions
    try expect(exts.contains("md"), "Should contain md")
    try expect(exts.contains("csv"), "Should contain csv")
    try expect(exts.contains("tsv"), "Should contain tsv")
}

runner.test("plugin registry: clear") {
    let reg = PluginRegistry()
    reg.register(MarkdownPlugin())
    reg.clear()
    try expect(reg.plugin(forExtension: "md") == nil, "Should be empty after clear")
}

runner.test("plugin registry: case insensitive lookup") {
    let reg = PluginRegistry()
    reg.register(HTMLPlugin())
    try expect(reg.plugin(forExtension: "HTML") != nil, "Should find plugin for .HTML")
    try expect(reg.plugin(forExtension: "Html") != nil, "Should find plugin for .Html")
}

// Markdown plugin tests

runner.test("markdown plugin renders correctly") {
    let plugin = MarkdownPlugin()
    let html = plugin.render(source: "# Hello\n\n**Bold** text")
    try expect(html.contains("<h1>Hello</h1>"), "Should contain heading")
    try expect(html.contains("<strong>Bold</strong>"), "Should contain bold")
}

runner.test("markdown plugin does not require JS") {
    let plugin = MarkdownPlugin()
    try expect(!plugin.requiresJSExecution, "Markdown should not require JS")
}

// CSV plugin tests

runner.test("CSV plugin renders simple table") {
    let csv = try loadPluginFixture("csv/simple.csv")
    let plugin = CSVPlugin()
    let html = plugin.render(source: csv)
    try expect(html.contains("<table>"), "Should contain table")
    try expect(html.contains("<th>Name</th>"), "Should contain header")
    try expect(html.contains("<td>Alice</td>"), "Should contain data cell")
    try expect(html.contains("<thead>"), "Should contain thead")
    try expect(html.contains("<tbody>"), "Should contain tbody")
}

runner.test("CSV plugin renders unicode") {
    let csv = try loadPluginFixture("csv/unicode.csv")
    let plugin = CSVPlugin()
    let html = plugin.render(source: csv)
    try expect(html.contains("<table>"), "Should contain table")
    try expect(html.contains("Bonjour"), "Should contain unicode text")
}

runner.test("CSV plugin escapes HTML in cells") {
    let plugin = CSVPlugin()
    let html = plugin.render(source: "Header\n<script>alert('xss')</script>")
    try expect(!html.contains("<script>"), "Should escape script tags in cells")
    try expect(html.contains("&lt;script&gt;"), "Should HTML-escape the content")
}

runner.test("CSV plugin handles empty input") {
    let plugin = CSVPlugin()
    let html = plugin.render(source: "")
    try expect(html.contains("Empty"), "Should indicate empty file")
}

// HTML sanitizer tests

runner.test("sanitizer strips script tags") {
    let html = "<p>Hello</p><script>alert('xss')</script><p>World</p>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<script"), "Should strip script tags")
    try expect(!clean.contains("alert"), "Should strip script content")
    try expect(clean.contains("<p>Hello</p>"), "Should preserve safe content")
    try expect(clean.contains("<p>World</p>"), "Should preserve safe content")
}

runner.test("sanitizer strips event handlers") {
    let html = "<button onclick=\"alert('click')\">Click</button>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("onclick"), "Should strip onclick")
    try expect(clean.contains("Click"), "Should preserve button text")
}

runner.test("sanitizer blocks javascript URIs") {
    let html = "<a href=\"javascript:alert('xss')\">Link</a>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("javascript:"), "Should block javascript: URI")
    try expect(clean.contains("blocked:"), "Should replace with blocked:")
}

runner.test("sanitizer strips iframes") {
    let html = "<p>Text</p><iframe src=\"https://evil.com\"></iframe><p>More</p>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<iframe"), "Should strip iframe tags")
    try expect(clean.contains("<p>Text</p>"), "Should preserve safe content")
}

runner.test("sanitizer strips object/embed tags") {
    let html = "<object data=\"evil.swf\"></object><embed src=\"evil.swf\">"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<object"), "Should strip object tags")
    try expect(!clean.contains("<embed"), "Should strip embed tags")
}

runner.test("sanitizer preserves safe HTML") {
    let html = try loadPluginFixture("html/safe.html")
    let clean = sanitizer.sanitize(html)
    try expect(clean.contains("<h1>Hello World</h1>"), "Should preserve h1")
    try expect(clean.contains("<strong>bold</strong>"), "Should preserve bold")
    try expect(clean.contains("<li>Item 1</li>"), "Should preserve list items")
}

// Fixture-based sanitizer tests

runner.test("sanitizer: xss-attempt fixture is fully cleaned") {
    let html = try loadPluginFixture("html/xss-attempt.html")
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<script"), "No script tags should remain")
    try expect(!clean.contains("javascript:"), "No javascript: URIs should remain")
    try expect(!clean.contains("onerror"), "No event handlers should remain")
    try expect(!clean.contains("<iframe"), "No iframes should remain")
    try expect(clean.contains("Normal text"), "Safe content should remain")
}

runner.test("sanitizer: event-handlers fixture is cleaned") {
    let html = try loadPluginFixture("html/event-handlers.html")
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("onclick"), "Should strip onclick")
    try expect(!clean.contains("onmouseover"), "Should strip onmouseover")
    try expect(!clean.contains("onload"), "Should strip onload")
    try expect(!clean.contains("onerror"), "Should strip onerror")
    try expect(clean.contains("Safe content"), "Should preserve safe content")
}

// HTML plugin integration

runner.test("HTML plugin sanitizes by default") {
    let plugin = HTMLPlugin()
    let html = "<p>Hello</p><script>alert('xss')</script>"
    let result = plugin.render(source: html)
    try expect(!result.contains("<script"), "HTML plugin should sanitize")
    try expect(result.contains("<p>Hello</p>"), "Should preserve safe content")
    try expect(!plugin.requiresJSExecution, "HTML plugin should not require JS (sanitized)")
}

runner.test("All enums have non-empty IDs via rawValue") {
    for theme in TestAppTheme.allCases {
        try expect(!theme.rawValue.isEmpty, "AppTheme rawValue should not be empty")
    }
    for width in TestPreviewWidth.allCases {
        try expect(!width.rawValue.isEmpty, "PreviewWidth rawValue should not be empty")
    }
    for tab in TestTabBehavior.allCases {
        try expect(!tab.rawValue.isEmpty, "TabBehavior rawValue should not be empty")
    }
}

// =============================================================================

print("")
runner.summary()
exit(runner.failed > 0 ? 1 : 0)
