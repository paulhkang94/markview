import Foundation

/// Plugin that renders HTML files with sanitization.
public struct HTMLPlugin: LanguagePlugin {
    public let supportedExtensions: Set<String> = ["html", "htm"]
    public let displayName = "HTML"
    public let requiresJSExecution = false

    private let sanitizer = HTMLSanitizer()

    public init() {}

    public func render(source: String) -> String {
        sanitizer.sanitize(source)
    }
}
