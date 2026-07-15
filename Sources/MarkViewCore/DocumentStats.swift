import Foundation

/// Word/character/line counts for the status bar, computed in a single pass.
///
/// Replaces three independent full-document scans (`split` for words,
/// `components(separatedBy:)` for lines, plus a second word scan for reading
/// time) that ran on the main thread inside `StatusBarView.body` and caused
/// multi-second App Hanging events on large documents (item-713,
/// Sentry APPLE-MACOS-34/-37).
public struct DocumentStats: Equatable, Sendable {
    public let wordCount: Int
    public let charCount: Int
    public let lineCount: Int

    public init(wordCount: Int, charCount: Int, lineCount: Int) {
        self.wordCount = wordCount
        self.charCount = charCount
        self.lineCount = lineCount
    }

    public static let zero = DocumentStats(wordCount: 0, charCount: 0, lineCount: 0)

    /// Reading time in minutes at 200 wpm (minimum 1 for non-empty content).
    public var readingMinutes: Int {
        max(1, wordCount / 200)
    }

    /// Single-pass computation, parity-exact with the previous getters:
    /// - words: runs of non-whitespace Characters (`Character.isWhitespace`
    ///   already covers newlines)
    /// - chars: Character (grapheme) count
    /// - lines: newline *scalars* + 1, matching
    ///   `components(separatedBy: .newlines).count` (CRLF counts as two)
    public static func compute(from content: String) -> DocumentStats {
        if content.isEmpty { return .zero }

        let newlines = CharacterSet.newlines
        var words = 0
        var chars = 0
        var newlineScalars = 0
        var inWord = false

        for ch in content {
            chars += 1
            if ch.isWhitespace {
                if inWord {
                    words += 1
                    inWord = false
                }
            } else {
                inWord = true
            }
            for scalar in ch.unicodeScalars where newlines.contains(scalar) {
                newlineScalars += 1
            }
        }
        if inWord { words += 1 }

        return DocumentStats(
            wordCount: words,
            charCount: chars,
            lineCount: newlineScalars + 1
        )
    }
}
