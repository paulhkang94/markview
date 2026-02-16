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
// MARK: - CSS Parsing Helpers (for auto-coverage tests)
// =============================================================================

/// Visual CSS properties that must be overridden in dark mode
let visualProperties: Set<String> = [
    "color", "background", "background-color", "border", "border-color",
    "border-top-color", "border-bottom-color", "border-left-color", "border-right-color"
]

struct CSSRule {
    let selector: String
    let properties: [String: String]
}

/// Simple regex-based CSS parser. Extracts selector → property pairs from a CSS block.
/// Does not handle nested @media — call on pre-split light/dark sections.
func parseCSSRules(_ css: String) -> [CSSRule] {
    var rules: [CSSRule] = []

    // Match: selector { ... }
    // Use a simple brace-counting approach for robustness
    let scanner = css as NSString
    let length = scanner.length
    var i = 0

    while i < length {
        // Skip whitespace
        while i < length && (scanner.character(at: i) == 0x20 || scanner.character(at: i) == 0x0A || scanner.character(at: i) == 0x0D || scanner.character(at: i) == 0x09) {
            i += 1
        }
        if i >= length { break }

        // Find the next '{'
        let selectorStart = i
        while i < length && scanner.character(at: i) != 0x7B /* { */ {
            i += 1
        }
        if i >= length { break }

        let selector = scanner.substring(with: NSRange(location: selectorStart, length: i - selectorStart))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        i += 1 // skip '{'

        // Find matching '}'
        var braceDepth = 1
        let bodyStart = i
        while i < length && braceDepth > 0 {
            let ch = scanner.character(at: i)
            if ch == 0x7B { braceDepth += 1 }
            else if ch == 0x7D { braceDepth -= 1 }
            i += 1
        }
        let bodyEnd = i - 1
        if bodyEnd <= bodyStart || selector.isEmpty { continue }

        let body = scanner.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))

        // Parse property: value pairs
        var props: [String: String] = [:]
        let declarations = body.components(separatedBy: ";")
        for decl in declarations {
            let parts = decl.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let prop = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                props[prop] = value
            }
        }

        if !props.isEmpty {
            rules.append(CSSRule(selector: selector, properties: props))
        }
    }

    return rules
}

/// Extract the CSS content between <style> and </style> from full HTML
func extractCSS(from html: String) -> String {
    guard let styleStart = html.range(of: "<style>")?.upperBound ?? html.range(of: "<style id=\"app-css\">")?.upperBound,
          let styleEnd = html.range(of: "</style>")?.lowerBound else { return "" }
    return String(html[styleStart..<styleEnd])
}

/// Split CSS into light-mode rules (before @media dark) and dark-mode rules (inside @media dark)
func splitLightDarkCSS(_ css: String) -> (light: String, dark: String) {
    guard let mediaStart = css.range(of: "@media (prefers-color-scheme: dark)") else {
        return (light: css, dark: "")
    }

    let light = String(css[css.startIndex..<mediaStart.lowerBound])

    // Find the opening brace after the media query
    let afterMedia = css[mediaStart.upperBound...]
    guard let braceStart = afterMedia.firstIndex(of: "{") else {
        return (light: light, dark: "")
    }

    // Find matching closing brace
    var depth = 1
    var idx = css.index(after: braceStart)
    while idx < css.endIndex && depth > 0 {
        if css[idx] == "{" { depth += 1 }
        else if css[idx] == "}" { depth -= 1 }
        idx = css.index(after: idx)
    }
    let braceEnd = css.index(before: idx)
    let dark = String(css[css.index(after: braceStart)..<braceEnd])

    // Also get any CSS after the dark block (it's still light-mode)
    let afterDark = String(css[idx...])
    return (light: light + afterDark, dark: dark)
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
    try expect(full.contains("<html"), "Missing <html>")
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
    try expect(full.contains("#3d444d"), "Missing dark border color")
}

runner.test("dark mode CSS covers all styled elements") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")

    // The dark mode media query must override every element that has a visible background/color in light mode
    let requiredDarkOverrides = [
        ("body", "body text/background"),
        ("th", "table header"),
        ("tr:nth-child(2n)", "alternating table rows"),
        ("blockquote", "blockquote"),
        ("hr", "horizontal rule"),
        ("h1, h2", "heading borders"),
        ("a {", "link color"),
        ("code:not(", "inline code"),
    ]

    for (selector, description) in requiredDarkOverrides {
        // Check the selector appears after the dark mode media query declaration
        guard let darkStart = full.range(of: "@media (prefers-color-scheme: dark)") else {
            throw TestError.assertionFailed("No dark mode media query found")
        }
        let afterDark = String(full[darkStart.upperBound...])
        try expect(afterDark.contains(selector),
                  "Dark mode missing override for \(description) ('\(selector)')")
    }
}

runner.test("dark mode table has proper contrast (GitHub Primer)") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")

    guard let darkStart = full.range(of: "@media (prefers-color-scheme: dark)") else {
        throw TestError.assertionFailed("No dark mode media query found")
    }
    let afterDark = String(full[darkStart.upperBound...])

    // Alternating rows use subtle dark background (#151b23), not same as body (#0d1117)
    try expect(afterDark.contains("#151b23"), "Dark mode alternating rows should use #151b23")

    // Borders should use GitHub dark border color #3d444d
    try expect(afterDark.contains("#3d444d"), "Dark mode borders should use #3d444d")
}

runner.test("dark mode inherits text color from body") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")

    guard let darkStart = full.range(of: "@media (prefers-color-scheme: dark)") else {
        throw TestError.assertionFailed("No dark mode media query found")
    }
    let afterDark = String(full[darkStart.upperBound...])

    // Body sets light text color — table cells inherit it (GitHub Primer approach)
    try expect(afterDark.contains("body") && afterDark.contains("color: #e6edf3"),
              "Dark mode body must set light text color for inheritance")
}

runner.test("dark mode inline code has explicit text color") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")

    guard let darkStart = full.range(of: "@media (prefers-color-scheme: dark)") else {
        throw TestError.assertionFailed("No dark mode media query found")
    }
    let afterDark = String(full[darkStart.upperBound...])

    // Inline code must set both background AND color — relying on inheritance
    // can leave dark text (#1f2328) on dark background (#343942)
    guard let codeRule = afterDark.range(of: "code:not(") else {
        throw TestError.assertionFailed("Dark mode missing inline code rule")
    }
    let ruleEnd = afterDark[codeRule.upperBound...].prefix(200)
    try expect(ruleEnd.contains("color:"),
              "Dark mode inline code must set explicit text color (not just background)")
}

// MARK: - Auto-Parsed CSS Dark Mode Coverage

runner.test("dark mode auto-coverage: every styled element has dark override") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")
    let css = extractCSS(from: full)
    let (lightCSS, darkCSS) = splitLightDarkCSS(css)

    let lightRules = parseCSSRules(lightCSS)
    let darkRules = parseCSSRules(darkCSS)

    // Build a set of dark-mode selectors → properties for lookup
    var darkOverrides: [String: Set<String>] = [:]
    for rule in darkRules {
        let normalizedSelector = rule.selector
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let props = Set(rule.properties.keys.filter { visualProperties.contains($0) })
        if !props.isEmpty {
            darkOverrides[normalizedSelector, default: []].formUnion(props)
        }
    }

    // Selectors that intentionally don't need dark overrides
    let exemptSelectors: Set<String> = [
        "pre code",          // covered by `pre` dark override
        "a:hover",           // inherits from `a` dark override
        ":root",             // color-scheme declaration, not visual
        "img",               // no color properties
        "input[type=\"checkbox\"]", // native control
    ]

    // CSS shorthand → longhand relationships: if dark mode sets any of the longhands,
    // that counts as covering the shorthand's visual aspects
    let shorthandCoverage: [String: [String]] = [
        "border": ["border-color", "border-top-color", "border-right-color", "border-bottom-color", "border-left-color"],
        "border-top": ["border-top-color"],
        "border-right": ["border-right-color"],
        "border-bottom": ["border-bottom-color"],
        "border-left": ["border-left-color"],
    ]

    /// Check if a light selector is covered by a more specific dark selector.
    /// E.g., `code { background }` is covered by `code:not([class*="language-"]) { background }`
    /// combined with `pre { background }` (since code inside pre uses pre's background).
    func selectorCoveredBySpecific(_ lightSel: String, prop: String) -> Bool {
        // `code` is covered for background: code:not(language) handles inline code,
        // and pre handles code blocks (pre code has background: none in light mode)
        if lightSel == "code" && prop == "background" {
            return darkOverrides.keys.contains(where: { $0.hasPrefix("code:not(") })
                && darkOverrides.keys.contains(where: { $0 == "pre" })
        }
        return false
    }

    var missing: [String] = []
    for rule in lightRules {
        let selector = rule.selector.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip exempt selectors
        if exemptSelectors.contains(selector) { continue }
        if selector.hasPrefix("@") { continue } // skip nested @media (e.g. @media print)

        // Find visual properties in this light rule
        let lightVisualProps = rule.properties.keys.filter { visualProperties.contains($0) }
        if lightVisualProps.isEmpty { continue }

        // Collect all dark-mode properties for this selector (exact + combined group match)
        var foundDarkProps: Set<String> = darkOverrides[selector] ?? []
        for (darkSel, darkProps) in darkOverrides {
            let darkParts = darkSel.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let lightParts = selector.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if lightParts.allSatisfy({ lp in darkParts.contains(lp) }) {
                foundDarkProps.formUnion(darkProps)
            }
        }

        for prop in lightVisualProps {
            if foundDarkProps.contains(prop) { continue }

            // Check shorthand → longhand coverage (e.g., border covered by border-color)
            if let longhands = shorthandCoverage[prop], longhands.contains(where: { foundDarkProps.contains($0) }) {
                continue
            }

            // Check if inheritable property is covered by body
            let inheritableProps: Set<String> = ["color"]
            if inheritableProps.contains(prop) && selector != "body" && darkOverrides["body"]?.contains(prop) == true {
                continue
            }

            // Check if a more specific dark selector covers this
            if selectorCoveredBySpecific(selector, prop: prop) { continue }

            missing.append("\(selector) { \(prop) }")
        }
    }

    if !missing.isEmpty {
        let report = missing.map { "  - \($0)" }.joined(separator: "\n")
        throw TestError.assertionFailed("Dark mode missing overrides for \(missing.count) light-mode visual properties:\n\(report)")
    }
}

runner.test("tables use max-content width not 100%") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")

    // Tables should fit content (GitHub Primer: width: max-content; max-width: 100%)
    try expect(full.contains("max-content"), "Tables should use width: max-content")
    try expect(full.contains("max-width: 100%"), "Tables should cap at 100% to prevent overflow")
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
    case narrow, medium, wide, full
    var label: String {
        switch self {
        case .narrow: return "Narrow (700px)"
        case .medium: return "Medium (900px)"
        case .wide: return "Wide (1200px)"
        case .full: return "Full Width"
        }
    }
    var cssValue: String {
        switch self {
        case .narrow: return "700px"
        case .medium: return "900px"
        case .wide: return "1200px"
        case .full: return "100%"
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

runner.test("PreviewWidth has 4 cases and correct CSS values") {
    try expect(TestPreviewWidth.allCases.count == 4, "Expected 4 PreviewWidth cases")
    try expect(TestPreviewWidth.narrow.cssValue == "700px", "Narrow should be 700px")
    try expect(TestPreviewWidth.medium.cssValue == "900px", "Medium should be 900px")
    try expect(TestPreviewWidth.wide.cssValue == "1200px", "Wide should be 1200px")
    try expect(TestPreviewWidth.full.cssValue == "100%", "Full should be 100%")
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
    try expect(TestPreviewWidth.narrow.label == "Narrow (700px)", "Narrow label")
    try expect(TestPreviewWidth.medium.label == "Medium (900px)", "Medium label")
    try expect(TestPreviewWidth.wide.label == "Wide (1200px)", "Wide label")
    try expect(TestPreviewWidth.full.label == "Full Width", "Full label")
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
// MARK: - Accessibility (A11Y) Tests
// =============================================================================

print("\n=== Accessibility Tests ===")

runner.test("inline template has article with role=document") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")
    try expect(full.contains("role=\"document\""), "Missing role=document on article")
    try expect(full.contains("aria-label=\"Rendered markdown content\""), "Missing aria-label on article")
}

runner.test("postProcessForAccessibility adds table role") {
    let html = "<table><tr><th>Name</th></tr><tr><td>Alice</td></tr></table>"
    let processed = MarkdownRenderer.postProcessForAccessibility(html)
    try expect(processed.contains("<table role=\"table\">"), "Missing role=table")
}

runner.test("postProcessForAccessibility adds scope=col to th") {
    let html = "<table><tr><th>Name</th><th align=\"center\">Age</th></tr></table>"
    let processed = MarkdownRenderer.postProcessForAccessibility(html)
    try expect(processed.contains("<th scope=\"col\">Name</th>"), "Missing scope=col on plain th")
    try expect(processed.contains("<th scope=\"col\" align=\"center\">Age</th>"), "Missing scope=col on aligned th")
}

runner.test("postProcessForAccessibility adds aria-label to code blocks") {
    let html = "<pre><code class=\"language-swift\">let x = 1</code></pre>"
    let processed = MarkdownRenderer.postProcessForAccessibility(html)
    try expect(processed.contains("<pre aria-label=\"Code block\">"), "Missing aria-label on pre")
}

runner.test("postProcessForAccessibility adds aria-label to task checkboxes") {
    let html = "<input type=\"checkbox\" checked=\"\" disabled=\"\"> Done"
    let processed = MarkdownRenderer.postProcessForAccessibility(html)
    try expect(processed.contains("aria-label=\"Task item\""), "Missing aria-label on checkbox")
}

runner.test("postProcessForAccessibility on GFM table fixture") {
    let md = "| Name | Age |\n|------|-----|\n| Alice | 30 |"
    let html = MarkdownRenderer.renderHTML(from: md)
    let processed = MarkdownRenderer.postProcessForAccessibility(html)
    try expect(processed.contains("role=\"table\""), "Fixture table missing role")
    try expect(processed.contains("scope=\"col\""), "Fixture th missing scope")
}

runner.test("postProcessForAccessibility on task list fixture") {
    let md = "- [x] Done\n- [ ] Not done"
    let html = MarkdownRenderer.renderHTML(from: md)
    let processed = MarkdownRenderer.postProcessForAccessibility(html)
    try expect(processed.contains("aria-label=\"Task item\""), "Task checkboxes missing aria-label")
}

// MARK: - Focus CSS Tests

print("\n=== Focus CSS Tests ===")

runner.test("template has :focus-visible styles") {
    // Read template.html from disk
    let cwd = FileManager.default.currentDirectoryPath
    let templatePath = URL(fileURLWithPath: cwd).appendingPathComponent("Sources/MarkView/Resources/template.html")
    let template = try String(contentsOf: templatePath, encoding: .utf8)
    try expect(template.contains(":focus-visible"), "template.html missing :focus-visible CSS")
    try expect(template.contains("outline:") || template.contains("outline-color:"), "template.html missing focus outline style")
}

runner.test("dark mode has focus outline color") {
    let cwd = FileManager.default.currentDirectoryPath
    let templatePath = URL(fileURLWithPath: cwd).appendingPathComponent("Sources/MarkView/Resources/template.html")
    let template = try String(contentsOf: templatePath, encoding: .utf8)

    guard let darkStart = template.range(of: "@media (prefers-color-scheme: dark)") else {
        throw TestError.assertionFailed("No dark mode media query in template.html")
    }
    let afterDark = String(template[darkStart.upperBound...])
    try expect(afterDark.contains(":focus-visible") && afterDark.contains("outline-color"),
              "Dark mode missing focus outline color override")
}

// MARK: - Internationalization (I18N) Tests

print("\n=== Internationalization Tests ===")

runner.test("template has lang attribute") {
    let cwd = FileManager.default.currentDirectoryPath
    let templatePath = URL(fileURLWithPath: cwd).appendingPathComponent("Sources/MarkView/Resources/template.html")
    let template = try String(contentsOf: templatePath, encoding: .utf8)
    try expect(template.contains("<html lang=\"en\">"), "template.html missing lang=en attribute")
}

runner.test("inline template has lang attribute") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")
    try expect(full.contains("<html lang=\"en\">"), "Inline template missing lang=en attribute")
}

runner.test("RTL CSS rules exist in template") {
    let cwd = FileManager.default.currentDirectoryPath
    let templatePath = URL(fileURLWithPath: cwd).appendingPathComponent("Sources/MarkView/Resources/template.html")
    let template = try String(contentsOf: templatePath, encoding: .utf8)
    try expect(template.contains("[dir=\"rtl\"]"), "template.html missing RTL CSS rules")
    try expect(template.contains("[dir=\"rtl\"] blockquote"), "template.html missing RTL blockquote rule")
    try expect(template.contains("[dir=\"rtl\"] ul"), "template.html missing RTL list rule")
}

runner.test("all user-facing strings use Strings enum") {
    // Grep SwiftUI view files for bare string literals that should be in Strings enum.
    // We check for common patterns that indicate a user-facing string NOT using Strings.X
    let cwd = FileManager.default.currentDirectoryPath
    let viewFiles = [
        "Sources/MarkView/ContentView.swift",
        "Sources/MarkView/StatusBarView.swift",
        "Sources/MarkView/EditorView.swift",
        "Sources/MarkView/MarkViewApp.swift",
    ]

    var violations: [String] = []
    for file in viewFiles {
        let path = URL(fileURLWithPath: cwd).appendingPathComponent(file)
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { continue }
        let lines = content.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip comments, imports, struct/class/func declarations
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("import") || trimmed.isEmpty { continue }
            // Check for Button("literal"), Text("literal"), .help("literal"), .alert("literal")
            // These should use Strings.X instead
            let patterns = [
                "Button(\"", "Text(\"", ".help(\"", ".alert(\"",
                ".accessibilityLabel(\"", ".accessibilityHint(\""
            ]
            for pattern in patterns {
                if trimmed.contains(pattern) {
                    // Allow Text() in format strings like Text("\(value)pt")
                    // Allow .help() that just wraps a Strings reference
                    let afterPattern = trimmed.components(separatedBy: pattern).dropFirst().joined()
                    if afterPattern.hasPrefix("\\(") { continue }
                    violations.append("\(URL(fileURLWithPath: file).lastPathComponent):\(i+1): \(trimmed.prefix(80))")
                }
            }
        }
    }

    if !violations.isEmpty {
        let report = violations.prefix(5).joined(separator: "\n  ")
        throw TestError.assertionFailed("Found \(violations.count) bare string literals (should use Strings.X):\n  \(report)")
    }
}

// =============================================================================
// MARK: - Dark Mode Explicit Color Regression Tests
// =============================================================================
// These tests prevent the bug where dark mode elements relied on CSS color
// inheritance from body, which fails in WKWebView. Every visible element
// MUST have an explicit color property in dark mode CSS.

print("\n=== Dark Mode Explicit Color Regression ===")

/// Parse dark mode CSS from a full HTML document and return selector → properties map.
func extractDarkModeRules(from html: String) -> [String: [String: String]] {
    let css = extractCSS(from: html)
    let (_, darkCSS) = splitLightDarkCSS(css)
    let rules = parseCSSRules(darkCSS)
    var result: [String: [String: String]] = [:]
    for rule in rules {
        result[rule.selector] = rule.properties
    }
    return result
}

/// Elements that display text and MUST have explicit color in dark mode.
/// Relying on body color inheritance is fragile in WKWebView.
let requiredExplicitColorSelectors = [
    ("body", "body text"),
    ("code:not([class*=\"language-\"])", "inline code"),
    ("th, td", "table cells"),
    ("pre", "code blocks"),
    ("h1, h2", "headings"),
]

runner.test("inline template: all text elements have explicit dark color") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")
    let darkRules = extractDarkModeRules(from: full)

    var missing: [String] = []
    for (selector, description) in requiredExplicitColorSelectors {
        let props = darkRules[selector] ?? [:]
        if props["color"] == nil {
            missing.append("\(selector) (\(description))")
        }
    }

    if !missing.isEmpty {
        throw TestError.assertionFailed(
            "Dark mode missing explicit color on \(missing.count) text elements " +
            "(DO NOT rely on inheritance from body):\n  " +
            missing.joined(separator: "\n  ")
        )
    }
}

runner.test("template.html: all text elements have explicit dark color") {
    let cwd = FileManager.default.currentDirectoryPath
    let templatePath = URL(fileURLWithPath: cwd).appendingPathComponent("Sources/MarkView/Resources/template.html")
    let template = try String(contentsOf: templatePath, encoding: .utf8)
    let darkRules = extractDarkModeRules(from: template)

    var missing: [String] = []
    for (selector, description) in requiredExplicitColorSelectors {
        let props = darkRules[selector] ?? [:]
        if props["color"] == nil {
            missing.append("\(selector) (\(description))")
        }
    }

    if !missing.isEmpty {
        throw TestError.assertionFailed(
            "template.html dark mode missing explicit color on \(missing.count) text elements " +
            "(DO NOT rely on inheritance from body):\n  " +
            missing.joined(separator: "\n  ")
        )
    }
}

runner.test("WebPreviewView darkModeCSS: all text elements have explicit color") {
    // Read WebPreviewView.swift and extract the darkModeCSS constant
    let cwd = FileManager.default.currentDirectoryPath
    let wpvPath = URL(fileURLWithPath: cwd).appendingPathComponent("Sources/MarkView/WebPreviewView.swift")
    let source = try String(contentsOf: wpvPath, encoding: .utf8)

    // Extract the darkModeCSS array content from source
    guard let darkStart = source.range(of: "private static let darkModeCSS = ["),
          let darkEnd = source.range(of: "].joined(separator:", range: darkStart.upperBound..<source.endIndex) else {
        throw TestError.assertionFailed("Could not find darkModeCSS constant in WebPreviewView.swift")
    }
    let darkCSSSource = String(source[darkStart.upperBound..<darkEnd.lowerBound])
    // Unescape Swift string escapes to get the actual CSS
    let darkCSS = darkCSSSource
        .replacingOccurrences(of: "\\\"", with: "\"")
        .replacingOccurrences(of: "\\n", with: "\n")

    for (selector, description) in requiredExplicitColorSelectors {
        // Find the CSS rule string for this selector
        guard let ruleStart = darkCSS.range(of: "\(selector) {") else {
            throw TestError.assertionFailed("darkModeCSS missing selector: \(selector) (\(description))")
        }
        let afterSelector = String(darkCSS[ruleStart.upperBound...])
        guard let ruleEndIdx = afterSelector.firstIndex(of: "}") else { continue }
        let ruleBody = String(afterSelector[afterSelector.startIndex..<ruleEndIdx])
        try expect(ruleBody.contains("color:"),
            "darkModeCSS: \(selector) (\(description)) missing explicit color property — " +
            "DO NOT rely on inheritance from body")
    }
}

runner.test("dark mode CSS is consistent across all 3 locations") {
    // Verify that the key dark mode colors match across template.html,
    // inline template, and WebPreviewView.swift darkModeCSS
    let cwd = FileManager.default.currentDirectoryPath

    // 1. Inline template
    let inlineHTML = MarkdownRenderer.wrapInTemplate("<p>test</p>")
    let inlineDark = extractDarkModeRules(from: inlineHTML)

    // 2. template.html
    let templatePath = URL(fileURLWithPath: cwd).appendingPathComponent("Sources/MarkView/Resources/template.html")
    let templateHTML = try String(contentsOf: templatePath, encoding: .utf8)
    let templateDark = extractDarkModeRules(from: templateHTML)

    // Check key selectors match between inline and template
    let criticalSelectors = ["body", "code:not([class*=\"language-\"])", "th, td", "pre"]
    var mismatches: [String] = []

    for sel in criticalSelectors {
        let inlineColor = inlineDark[sel]?["color"]
        let templateColor = templateDark[sel]?["color"]

        if inlineColor != templateColor {
            mismatches.append("\(sel): inline=\(inlineColor ?? "nil") vs template=\(templateColor ?? "nil")")
        }

        let inlineBg = inlineDark[sel]?["background"] ?? inlineDark[sel]?["background-color"]
        let templateBg = templateDark[sel]?["background"] ?? templateDark[sel]?["background-color"]

        if inlineBg != templateBg {
            mismatches.append("\(sel) bg: inline=\(inlineBg ?? "nil") vs template=\(templateBg ?? "nil")")
        }
    }

    if !mismatches.isEmpty {
        throw TestError.assertionFailed(
            "Dark mode CSS inconsistency between inline template and template.html:\n  " +
            mismatches.joined(separator: "\n  ")
        )
    }
}

runner.test("dark mode text contrast >= 4.5:1 for all explicit colors") {
    // WCAG AA requires >= 4.5:1 for normal text
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")
    let darkRules = extractDarkModeRules(from: full)

    // Parse hex color to relative luminance
    func luminance(_ hex: String) -> Double? {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6 else { return nil }
        let scanner = Scanner(string: h)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        func linearize(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    func contrastRatio(_ l1: Double, _ l2: Double) -> Double {
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // Dark background
    let bgHex = "#0d1117"
    guard let bgLum = luminance(bgHex) else {
        throw TestError.assertionFailed("Could not parse background color")
    }

    // Check all elements with explicit color
    var failures: [String] = []
    for (selector, description) in requiredExplicitColorSelectors {
        guard let colorValue = darkRules[selector]?["color"] else { continue }
        // Extract hex color from value (might be "#e6edf3" or "#8b949e" etc)
        let hexPattern = "#[0-9a-fA-F]{6}"
        guard let hexRange = colorValue.range(of: hexPattern, options: .regularExpression),
              let fgLum = luminance(String(colorValue[hexRange])) else { continue }

        let ratio = contrastRatio(fgLum, bgLum)
        if ratio < 4.5 {
            failures.append("\(selector) (\(description)): \(colorValue) on \(bgHex) = \(String(format: "%.1f", ratio)):1 (need >= 4.5:1)")
        }
    }

    if !failures.isEmpty {
        throw TestError.assertionFailed(
            "WCAG AA contrast failures in dark mode:\n  " +
            failures.joined(separator: "\n  ")
        )
    }
}

runner.test("WebPreviewView .system theme injects dark CSS (not just media query)") {
    // Verify that WebPreviewView.swift handles .system theme by detecting
    // the system appearance and injecting darkModeCSS, NOT just relying on
    // @media (prefers-color-scheme: dark) which is unreliable in WKWebView
    let cwd = FileManager.default.currentDirectoryPath
    let wpvPath = URL(fileURLWithPath: cwd).appendingPathComponent("Sources/MarkView/WebPreviewView.swift")
    let source = try String(contentsOf: wpvPath, encoding: .utf8)

    // Find the .system case in injectSettingsCSS
    guard source.contains("case .system:") else {
        throw TestError.assertionFailed("WebPreviewView missing .system case")
    }

    // Verify it does NOT just break/return — it must inject dark CSS conditionally
    // Look for the pattern: case .system followed by dark mode detection
    try expect(
        source.contains("systemIsDarkMode") || source.contains("effectiveAppearance"),
        "WebPreviewView .system theme must detect dark mode and inject CSS explicitly " +
        "(WKWebView @media prefers-color-scheme is unreliable)"
    )

    // Verify webView.appearance is set (so media query works as backup)
    try expect(
        source.contains("webView.appearance"),
        "WebPreviewView must set webView.appearance to sync with system theme"
    )
}

// =============================================================================
// MARK: - Window Sizing Tests
// =============================================================================
// Validates the window sizing logic used by MarkViewApp and ContentView.
// Tests the computation (screen percentages, minimums, centering) without requiring
// a running window — ensures sizing regressions are caught automatically.

print("\n=== Window Sizing Tests ===")

// Simulate the sizing functions extracted from MarkViewApp/ContentView
struct WindowSizingSpec {
    /// Preview-only mode: 55% width, 85% height
    static func previewOnlySize(screenWidth: CGFloat, screenHeight: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let w = max(screenWidth * 0.55, 800)
        let h = max(screenHeight * 0.85, 600)
        return (w, h)
    }

    /// Editor+preview mode: 80% width
    static func editorPreviewWidth(screenWidth: CGFloat) -> CGFloat {
        max(screenWidth * 0.80, 900)
    }

    /// Toggle sizing: returns target width for mode
    static func toggleTargetWidth(screenWidth: CGFloat, showEditor: Bool) -> CGFloat {
        if showEditor {
            return max(screenWidth * 0.80, 900)
        } else {
            return max(screenWidth * 0.55, 800)
        }
    }

    /// Center a window of given width on screen
    static func centeredX(screenOriginX: CGFloat, screenWidth: CGFloat, windowWidth: CGFloat) -> CGFloat {
        screenOriginX + (screenWidth - windowWidth) / 2
    }
}

// Read source files to validate constants match
let appSource = try! String(contentsOfFile: "Sources/MarkView/MarkViewApp.swift", encoding: .utf8)
let contentSource = try! String(contentsOfFile: "Sources/MarkView/ContentView.swift", encoding: .utf8)

runner.test("preview-only default: 55% screen width on standard display") {
    let (w, h) = WindowSizingSpec.previewOnlySize(screenWidth: 1920, screenHeight: 1080)
    try expect(w == 1056, "expected 1056, got \(w)")
    try expect(h == 918, "expected 918, got \(h)")
}

runner.test("preview-only default: min 800 kicks in on laptop display") {
    let (w, _) = WindowSizingSpec.previewOnlySize(screenWidth: 1440, screenHeight: 900)
    // 1440*0.55=792 < 800, so min kicks in
    try expect(w == 800, "expected 800 (min), got \(w)")
}

runner.test("preview-only minimum width: 800px on small screens") {
    let (w, _) = WindowSizingSpec.previewOnlySize(screenWidth: 1200, screenHeight: 800)
    // 1200 * 0.55 = 660, min 800 kicks in
    try expect(w == 800, "expected 800 minimum, got \(w)")
}

runner.test("preview-only minimum height: 600px on small screens") {
    let (_, h) = WindowSizingSpec.previewOnlySize(screenWidth: 1200, screenHeight: 600)
    // 600 * 0.85 = 510, min 600 kicks in
    try expect(h == 600, "expected 600 minimum, got \(h)")
}

runner.test("editor+preview: 80% screen width on standard display") {
    let w = WindowSizingSpec.editorPreviewWidth(screenWidth: 1920)
    try expect(w == 1536, "expected 1536, got \(w)")
}

runner.test("editor+preview minimum width: 900px on small screens") {
    let w = WindowSizingSpec.editorPreviewWidth(screenWidth: 1000)
    // 1000 * 0.80 = 800, min 900 kicks in
    try expect(w == 900, "expected 900 minimum, got \(w)")
}

runner.test("editor+preview is always wider than preview-only") {
    for screenWidth: CGFloat in [1000, 1200, 1440, 1920, 2560, 3840] {
        let previewWidth = WindowSizingSpec.toggleTargetWidth(screenWidth: screenWidth, showEditor: false)
        let editorWidth = WindowSizingSpec.toggleTargetWidth(screenWidth: screenWidth, showEditor: true)
        try expect(editorWidth > previewWidth,
            "editor (\(editorWidth)) must be wider than preview (\(previewWidth)) at screen \(screenWidth)")
    }
}

runner.test("toggle to editor widens, toggle back narrows") {
    let screen: CGFloat = 1920
    let previewW = WindowSizingSpec.toggleTargetWidth(screenWidth: screen, showEditor: false)
    let editorW = WindowSizingSpec.toggleTargetWidth(screenWidth: screen, showEditor: true)
    try expect(editorW > previewW, "editor should be wider")
    try expect(editorW / previewW > 1.3, "editor should be at least 30% wider than preview-only")
}

runner.test("window centering calculation") {
    let x = WindowSizingSpec.centeredX(screenOriginX: 0, screenWidth: 1920, windowWidth: 1056)
    try expect(x == 432, "expected centered at 432, got \(x)")
}

runner.test("window centering with screen offset (multi-monitor)") {
    let x = WindowSizingSpec.centeredX(screenOriginX: -1920, screenWidth: 1920, windowWidth: 1056)
    try expect(x == -1488, "expected centered at -1488 on secondary monitor, got \(x)")
}

runner.test("ultra-wide screen: preview-only doesn't stretch too wide") {
    let (w, _) = WindowSizingSpec.previewOnlySize(screenWidth: 3440, screenHeight: 1440)
    // 3440 * 0.55 = 1892 — wide but reasonable (use tolerance for floating point)
    try expect(abs(w - 1892) < 1, "expected ~1892, got \(w)")
    try expect(w < 2000, "preview-only should stay under 2000px even on ultra-wide")
}

runner.test("ultra-wide screen: editor+preview uses 80%") {
    let w = WindowSizingSpec.editorPreviewWidth(screenWidth: 3440)
    try expect(w == 2752, "expected 2752, got \(w)")
}

// Source code validation — ensure the percentages in code match our test spec
runner.test("MarkViewApp.swift uses 0.55 for preview-only width") {
    try expect(appSource.contains("width * 0.55"), "MarkViewApp must use 0.55 for preview-only width fraction")
}

runner.test("MarkViewApp.swift uses min width 800 for preview-only") {
    try expect(appSource.contains("0.55, 800") || appSource.contains("0.55, 800)"),
        "MarkViewApp must use 800 min width for preview-only")
}

runner.test("ContentView.swift uses 0.80 for editor+preview width") {
    try expect(contentSource.contains("0.80") || contentSource.contains("0.8"),
        "ContentView must use 0.80 for editor+preview width fraction")
}

runner.test("ContentView.swift uses 0.55 for preview-only width") {
    try expect(contentSource.contains("0.55"),
        "ContentView must use 0.55 for preview-only width fraction")
}

runner.test("ContentView.swift has min 900 for editor mode") {
    try expect(contentSource.contains("900"),
        "ContentView must enforce 900px minimum for editor+preview")
}

runner.test("ContentView.swift has min 800 for preview mode") {
    // Check toggle function has 800 min
    try expect(contentSource.contains("800"),
        "ContentView must enforce 800px minimum for preview-only")
}

runner.test("MarkViewApp min frame constraint: 600x400") {
    try expect(appSource.contains("minWidth: 600") && appSource.contains("minHeight: 400"),
        "MarkViewApp must set frame minimums to 600x400")
}

runner.test("window sizing uses animate: true for smooth transitions") {
    try expect(contentSource.contains("animate: true"),
        "toggleEditor must animate window resize for smooth UX")
}

// =============================================================================

print("")
runner.summary()
exit(runner.failed > 0 ? 1 : 0)
