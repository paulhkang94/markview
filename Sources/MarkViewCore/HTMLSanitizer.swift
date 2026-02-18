import Foundation

/// Sanitizes HTML to prevent XSS attacks.
/// Strips dangerous tags, event handlers, javascript: URIs, and data: URIs.
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

        // 3. Remove <svg> tags and their contents (XSS via onload, animate, etc.)
        result = result.replacingOccurrences(
            of: "<svg[^>]*>[\\s\\S]*?</svg>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "<svg[^>]*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 4. Remove <math> tags and their contents (XSS via namespace confusion)
        result = result.replacingOccurrences(
            of: "<math[^>]*>[\\s\\S]*?</math>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "<math[^>]*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 5. Remove <style> tags and their contents (CSS-based data exfiltration)
        result = result.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "<style[^>]*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 6. Remove <base> tags (redirects all relative links)
        result = result.replacingOccurrences(
            of: "<base[^>]*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 7. Remove <form> tags and their contents (phishing vectors)
        result = result.replacingOccurrences(
            of: "<form[^>]*>[\\s\\S]*?</form>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "<form[^>]*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 8. Remove <input> tags (phishing / form injection)
        result = result.replacingOccurrences(
            of: "<input[^>]*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 9. Remove <textarea> tags (phishing / form injection)
        result = result.replacingOccurrences(
            of: "<textarea[^>]*>[\\s\\S]*?</textarea>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "<textarea[^>]*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 10. Remove <button> tags used in form contexts
        result = result.replacingOccurrences(
            of: "<button[^>]*>[\\s\\S]*?</button>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 11. Remove <select> tags (form injection)
        result = result.replacingOccurrences(
            of: "<select[^>]*>[\\s\\S]*?</select>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 12. Remove <link> tags (loads external stylesheets / resources)
        result = result.replacingOccurrences(
            of: "<link[^>]*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 13. Remove <iframe> tags
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

        // 14. Remove <object> and <embed> tags
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

        // 15. Remove event handler attributes — quoted (double), quoted (single), AND unquoted
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
        // Unquoted event handlers: matches on<event>=<value> where value ends at space or >
        result = result.replacingOccurrences(
            of: "\\s+on\\w+\\s*=\\s*[^\\s'\">][^\\s>]*",
            with: "",
            options: .regularExpression
        )

        // 16. Replace javascript: URIs (case-insensitive, already handled above but keep explicit)
        result = result.replacingOccurrences(
            of: "javascript:",
            with: "blocked:",
            options: .caseInsensitive
        )

        // 17. Replace data: URIs (can execute JS in some contexts, e.g. data:text/html)
        result = result.replacingOccurrences(
            of: "data:",
            with: "blocked-data:",
            options: .caseInsensitive
        )

        return result
    }
}
