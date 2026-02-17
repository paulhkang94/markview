import Foundation

// MARK: - Suggestion Types

public struct Suggestion: Equatable {
    public let text: String
    public let displayLabel: String
    public let kind: SuggestionKind

    public init(text: String, displayLabel: String, kind: SuggestionKind) {
        self.text = text
        self.displayLabel = displayLabel
        self.kind = kind
    }
}

public enum SuggestionKind: String {
    case language
    case emoji
    case heading
    case link
}

// MARK: - Suggestion Engine

public final class MarkdownSuggestions {

    public init() {}

    /// Languages supported by the bundled Prism.js configuration.
    public static let supportedLanguages: [String] = [
        "bash", "c", "cpp", "css", "diff", "go", "html",
        "java", "javascript", "json", "kotlin", "markdown",
        "python", "ruby", "rust", "swift", "typescript", "yaml"
    ]

    /// Common emoji shortcodes mapped to their unicode characters.
    public static let emojiMap: [String: String] = [
        "rocket": "\u{1F680}",
        "star": "\u{2B50}",
        "heart": "\u{2764}\u{FE0F}",
        "fire": "\u{1F525}",
        "check": "\u{2705}",
        "x": "\u{274C}",
        "warning": "\u{26A0}\u{FE0F}",
        "bulb": "\u{1F4A1}",
        "bug": "\u{1F41B}",
        "memo": "\u{1F4DD}",
        "thumbsup": "\u{1F44D}",
        "thumbsdown": "\u{1F44E}",
        "eyes": "\u{1F440}",
        "tada": "\u{1F389}",
        "sparkles": "\u{2728}",
        "zap": "\u{26A1}",
        "100": "\u{1F4AF}",
        "thinking": "\u{1F914}",
        "wave": "\u{1F44B}",
        "clap": "\u{1F44F}",
    ]

    // MARK: - Code Fence Language Suggestions

    /// Returns language suggestions for code fence completion.
    /// Call after user types ``` to suggest language identifiers.
    public func suggestLanguages(prefix: String = "") -> [Suggestion] {
        let filtered = prefix.isEmpty
            ? Self.supportedLanguages
            : Self.supportedLanguages.filter { $0.hasPrefix(prefix.lowercased()) }

        return filtered.map { lang in
            Suggestion(text: lang, displayLabel: lang, kind: .language)
        }
    }

    // MARK: - Emoji Suggestions

    /// Returns emoji suggestions matching the given prefix.
    /// Call after user types : to suggest emoji shortcodes.
    public func suggestEmoji(prefix: String) -> [Suggestion] {
        let lowered = prefix.lowercased()
        return Self.emojiMap
            .filter { $0.key.hasPrefix(lowered) }
            .sorted { $0.key < $1.key }
            .map { key, value in
                Suggestion(text: ":\(key):", displayLabel: "\(value) :\(key):", kind: .emoji)
            }
    }

    /// Look up a specific emoji shortcode.
    public func lookupEmoji(_ shortcode: String) -> String? {
        let key = shortcode.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return Self.emojiMap[key.lowercased()]
    }

    // MARK: - Heading Suggestions

    /// Returns heading level suggestions based on levels used in the document.
    /// Call after user types # to suggest appropriate heading levels.
    public func suggestHeadings(document: String) -> [Suggestion] {
        var usedLevels: Set<Int> = []
        for line in document.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            var level = 0
            for ch in trimmed {
                if ch == "#" { level += 1 } else { break }
            }
            if level >= 1 && level <= 6 {
                usedLevels.insert(level)
            }
        }

        return usedLevels.sorted().map { level in
            let hashes = String(repeating: "#", count: level)
            return Suggestion(
                text: "\(hashes) ",
                displayLabel: "h\(level) (\(hashes))",
                kind: .heading
            )
        }
    }

    // MARK: - Link Suggestions

    /// Returns reference-style link suggestions from the document.
    /// Call after user types [ to suggest reference link labels.
    private static let refLinkPattern = try! NSRegularExpression(pattern: "^\\[([^\\]]+)\\]:\\s+(.+)$", options: .anchorsMatchLines)

    public func suggestLinks(document: String) -> [Suggestion] {
        var refs: [(label: String, url: String)] = []
        let nsDoc = document as NSString
        let matches = Self.refLinkPattern.matches(in: document, range: NSRange(location: 0, length: nsDoc.length))

        for match in matches {
            let label = nsDoc.substring(with: match.range(at: 1))
            let url = nsDoc.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            refs.append((label: label, url: url))
        }

        return refs.map { ref in
            Suggestion(
                text: "[\(ref.label)]",
                displayLabel: "\(ref.label) → \(ref.url)",
                kind: .link
            )
        }
    }
}
