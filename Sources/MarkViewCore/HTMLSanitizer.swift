import Foundation

/// Sanitizes HTML to prevent XSS attacks.
/// Strips script tags, event handlers, and javascript: URIs.
public final class HTMLSanitizer {

    public init() {}

    /// Sanitize HTML by removing dangerous elements and attributes.
    public func sanitize(_ html: String) -> String {
        var result = html

        // 1. Remove <script> tags and their contents
        result = result.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: .regularExpression
        )

        // 2. Remove self-closing / unclosed script tags
        result = result.replacingOccurrences(
            of: "<script[^>]*/?>",
            with: "",
            options: .regularExpression
        )

        // 3. Remove event handler attributes (onclick, onerror, onload, etc.)
        result = result.replacingOccurrences(
            of: "\\s+on\\w+\\s*=\\s*\"[^\"]*\"",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\s+on\\w+\\s*=\\s*'[^']*'",
            with: "",
            options: .regularExpression
        )

        // 4. Replace javascript: URIs
        result = result.replacingOccurrences(
            of: "javascript:",
            with: "blocked:",
            options: .caseInsensitive
        )

        // 5. Remove <iframe> tags
        result = result.replacingOccurrences(
            of: "<iframe[^>]*>[\\s\\S]*?</iframe>",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "<iframe[^>]*/?>",
            with: "",
            options: .regularExpression
        )

        // 6. Remove <object> and <embed> tags
        result = result.replacingOccurrences(
            of: "<object[^>]*>[\\s\\S]*?</object>",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "<embed[^>]*/?>",
            with: "",
            options: .regularExpression
        )

        return result
    }
}
