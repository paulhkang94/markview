import Foundation

/// Plugin that renders Markdown using the existing cmark-gfm renderer.
public struct MarkdownPlugin: LanguagePlugin {
    public let supportedExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]
    public let displayName = "Markdown"
    public let requiresJSExecution = false

    public init() {}

    public func render(source: String) -> String {
        MarkdownRenderer.renderHTML(from: source)
    }
}
