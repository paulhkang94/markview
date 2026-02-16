import Foundation

// MARK: - Diagnostic Types

public struct LintDiagnostic: Equatable {
    public enum Severity: String {
        case warning, error
    }

    public let severity: Severity
    public let line: Int
    public let column: Int
    public let message: String
    public let rule: LintRule
    public let fix: String?

    public init(severity: Severity, line: Int, column: Int, message: String, rule: LintRule, fix: String? = nil) {
        self.severity = severity
        self.line = line
        self.column = column
        self.message = message
        self.rule = rule
        self.fix = fix
    }
}

public enum LintRule: String, CaseIterable {
    case inconsistentHeadings = "inconsistent-headings"
    case trailingWhitespace = "trailing-whitespace"
    case missingBlankLines = "missing-blank-lines"
    case duplicateHeadings = "duplicate-headings"
    case brokenLinks = "broken-links"
    case unclosedFences = "unclosed-fences"
    case unclosedFormatting = "unclosed-formatting"
    case mismatchedBrackets = "mismatched-brackets"
    case invalidTables = "invalid-tables"
}

// MARK: - Linter

public final class MarkdownLinter {

    public init() {}

    public func lint(_ markdown: String, rules: Set<LintRule>? = nil) -> [LintDiagnostic] {
        let activeRules = rules ?? Set(LintRule.allCases)
        let lines = markdown.components(separatedBy: "\n")
        var diagnostics: [LintDiagnostic] = []

        if activeRules.contains(.inconsistentHeadings) {
            diagnostics.append(contentsOf: checkInconsistentHeadings(lines))
        }
        if activeRules.contains(.trailingWhitespace) {
            diagnostics.append(contentsOf: checkTrailingWhitespace(lines))
        }
        if activeRules.contains(.missingBlankLines) {
            diagnostics.append(contentsOf: checkMissingBlankLines(lines))
        }
        if activeRules.contains(.duplicateHeadings) {
            diagnostics.append(contentsOf: checkDuplicateHeadings(lines))
        }
        if activeRules.contains(.brokenLinks) {
            diagnostics.append(contentsOf: checkBrokenLinks(markdown, lines: lines))
        }
        if activeRules.contains(.unclosedFences) {
            diagnostics.append(contentsOf: checkUnclosedFences(lines))
        }
        if activeRules.contains(.unclosedFormatting) {
            diagnostics.append(contentsOf: checkUnclosedFormatting(lines))
        }
        if activeRules.contains(.mismatchedBrackets) {
            diagnostics.append(contentsOf: checkMismatchedBrackets(lines))
        }
        if activeRules.contains(.invalidTables) {
            diagnostics.append(contentsOf: checkInvalidTables(lines))
        }

        return diagnostics.sorted { $0.line < $1.line }
    }

    // MARK: - Rule: Inconsistent Headings

    func checkInconsistentHeadings(_ lines: [String]) -> [LintDiagnostic] {
        var diagnostics: [LintDiagnostic] = []
        var seenLevels: [Int] = []
        var inFence = false

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }

            if let level = headingLevel(line) {
                if let lastLevel = seenLevels.last, level > lastLevel + 1 {
                    diagnostics.append(LintDiagnostic(
                        severity: .warning,
                        line: i + 1,
                        column: 1,
                        message: "Heading level skipped: h\(lastLevel) → h\(level)",
                        rule: .inconsistentHeadings,
                        fix: "Add an h\(lastLevel + 1) heading before this"
                    ))
                }
                seenLevels.append(level)
            }
        }
        return diagnostics
    }

    // MARK: - Rule: Trailing Whitespace

    func checkTrailingWhitespace(_ lines: [String]) -> [LintDiagnostic] {
        var diagnostics: [LintDiagnostic] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            let trailingCount = line.count - trimmed.count
            // Allow exactly 2 trailing spaces (markdown line break) but flag others
            if trailingCount > 0 && trailingCount != 2 {
                diagnostics.append(LintDiagnostic(
                    severity: .warning,
                    line: i + 1,
                    column: trimmed.count + 1,
                    message: "Trailing whitespace (\(trailingCount) spaces)",
                    rule: .trailingWhitespace,
                    fix: "Remove trailing whitespace"
                ))
            }
        }
        return diagnostics
    }

    // MARK: - Rule: Missing Blank Lines

    func checkMissingBlankLines(_ lines: [String]) -> [LintDiagnostic] {
        var diagnostics: [LintDiagnostic] = []
        var inFence = false

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }

            if headingLevel(line) != nil && i > 0 {
                let prev = lines[i - 1]
                if !prev.trimmingCharacters(in: .whitespaces).isEmpty && headingLevel(prev) == nil && !prev.hasPrefix("```") {
                    diagnostics.append(LintDiagnostic(
                        severity: .warning,
                        line: i + 1,
                        column: 1,
                        message: "Missing blank line before heading",
                        rule: .missingBlankLines,
                        fix: "Add a blank line above this heading"
                    ))
                }
            }
        }
        return diagnostics
    }

    // MARK: - Rule: Duplicate Headings

    func checkDuplicateHeadings(_ lines: [String]) -> [LintDiagnostic] {
        var diagnostics: [LintDiagnostic] = []
        var seen: [String: Int] = [:]
        var inFence = false

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }

            if headingLevel(line) != nil {
                let text = headingText(line)
                if let firstLine = seen[text] {
                    diagnostics.append(LintDiagnostic(
                        severity: .warning,
                        line: i + 1,
                        column: 1,
                        message: "Duplicate heading \"\(text)\" (first at line \(firstLine))",
                        rule: .duplicateHeadings
                    ))
                } else {
                    seen[text] = i + 1
                }
            }
        }
        return diagnostics
    }

    // MARK: - Rule: Broken Links

    func checkBrokenLinks(_ markdown: String, lines: [String]) -> [LintDiagnostic] {
        var diagnostics: [LintDiagnostic] = []

        // Collect reference definitions: [label]: url
        var definitions: Set<String> = []
        let defPattern = try! NSRegularExpression(pattern: "^\\[([^\\]]+)\\]:\\s", options: .anchorsMatchLines)
        let nsMarkdown = markdown as NSString
        let defMatches = defPattern.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))
        for match in defMatches {
            let label = nsMarkdown.substring(with: match.range(at: 1)).lowercased()
            definitions.insert(label)
        }

        // Find reference-style links: [text][ref]
        let refPattern = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\[([^\\]]+)\\]")
        for (i, line) in lines.enumerated() {
            let nsLine = line as NSString
            let matches = refPattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                let ref = nsLine.substring(with: match.range(at: 2)).lowercased()
                if !definitions.contains(ref) {
                    diagnostics.append(LintDiagnostic(
                        severity: .error,
                        line: i + 1,
                        column: match.range.location + 1,
                        message: "Broken reference link: [\(ref)] is not defined",
                        rule: .brokenLinks,
                        fix: "Add a reference definition: [\(ref)]: url"
                    ))
                }
            }
        }
        return diagnostics
    }

    // MARK: - Rule: Unclosed Fences

    func checkUnclosedFences(_ lines: [String]) -> [LintDiagnostic] {
        var diagnostics: [LintDiagnostic] = []
        var fenceStart: Int? = nil

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if fenceStart == nil {
                    fenceStart = i + 1
                } else {
                    fenceStart = nil
                }
            }
        }

        if let start = fenceStart {
            diagnostics.append(LintDiagnostic(
                severity: .error,
                line: start,
                column: 1,
                message: "Unclosed code fence",
                rule: .unclosedFences,
                fix: "Add ``` to close the code fence"
            ))
        }
        return diagnostics
    }

    // MARK: - Rule: Unclosed Formatting

    func checkUnclosedFormatting(_ lines: [String]) -> [LintDiagnostic] {
        var diagnostics: [LintDiagnostic] = []
        var inFence = false

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }

            // Check for unclosed ** (bold)
            let boldCount = countOccurrences(of: "**", in: line)
            if boldCount % 2 != 0 {
                diagnostics.append(LintDiagnostic(
                    severity: .warning,
                    line: i + 1,
                    column: 1,
                    message: "Possibly unclosed bold formatting (**)",
                    rule: .unclosedFormatting,
                    fix: "Add closing **"
                ))
            }

            // Check for unclosed __ (bold alt)
            let underscoreBoldCount = countOccurrences(of: "__", in: line)
            if underscoreBoldCount % 2 != 0 {
                diagnostics.append(LintDiagnostic(
                    severity: .warning,
                    line: i + 1,
                    column: 1,
                    message: "Possibly unclosed bold formatting (__)",
                    rule: .unclosedFormatting,
                    fix: "Add closing __"
                ))
            }

            // Check for unclosed ~~ (strikethrough)
            let strikeCount = countOccurrences(of: "~~", in: line)
            if strikeCount % 2 != 0 {
                diagnostics.append(LintDiagnostic(
                    severity: .warning,
                    line: i + 1,
                    column: 1,
                    message: "Possibly unclosed strikethrough (~~)",
                    rule: .unclosedFormatting,
                    fix: "Add closing ~~"
                ))
            }
        }
        return diagnostics
    }

    // MARK: - Rule: Mismatched Brackets

    func checkMismatchedBrackets(_ lines: [String]) -> [LintDiagnostic] {
        var diagnostics: [LintDiagnostic] = []
        var inFence = false

        let linkPattern = try! NSRegularExpression(pattern: "\\[([^\\]]*?)\\]\\(([^)]*?)$")

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }

            let nsLine = line as NSString
            let matches = linkPattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                diagnostics.append(LintDiagnostic(
                    severity: .error,
                    line: i + 1,
                    column: match.range.location + 1,
                    message: "Missing closing parenthesis in link",
                    rule: .mismatchedBrackets,
                    fix: "Add ) to close the link URL"
                ))
            }
        }
        return diagnostics
    }

    // MARK: - Rule: Invalid Tables

    func checkInvalidTables(_ lines: [String]) -> [LintDiagnostic] {
        var diagnostics: [LintDiagnostic] = []
        var inFence = false
        var tableHeaderCols: Int? = nil
        var tableStartLine: Int = 0

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("```") { inFence.toggle(); tableHeaderCols = nil; continue }
            if inFence { continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("|") && trimmed.hasPrefix("|") {
                let cols = pipeCount(trimmed)
                if tableHeaderCols == nil {
                    tableHeaderCols = cols
                    tableStartLine = i + 1
                } else if cols != tableHeaderCols! {
                    // Check if this is the separator line (|---|---|)
                    let isSeparator = trimmed.replacingOccurrences(of: "[|\\-: ]", with: "", options: .regularExpression).isEmpty
                    if !isSeparator {
                        diagnostics.append(LintDiagnostic(
                            severity: .warning,
                            line: i + 1,
                            column: 1,
                            message: "Table row has \(cols) columns but header has \(tableHeaderCols!) columns",
                            rule: .invalidTables,
                            fix: "Adjust columns to match header (\(tableHeaderCols!) columns)"
                        ))
                    }
                }
            } else {
                tableHeaderCols = nil
            }
        }
        return diagnostics
    }

    // MARK: - Helpers

    private func headingLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        // Must have space after # marks (or be just #)
        guard trimmed.count == level || trimmed.dropFirst(level).first == " " else { return nil }
        return level
    }

    private func headingText(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let spaceIndex = trimmed.firstIndex(of: " ") else { return "" }
        return String(trimmed[trimmed.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespaces)
    }

    private func countOccurrences(of substring: String, in string: String) -> Int {
        var count = 0
        var searchRange = string.startIndex..<string.endIndex
        while let range = string.range(of: substring, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<string.endIndex
        }
        return count
    }

    private func pipeCount(_ line: String) -> Int {
        // Count cells by splitting on | and filtering empty edges
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        // A line like "| a | b | c |" splits to ["", " a ", " b ", " c ", ""]
        return parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}
