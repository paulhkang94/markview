import Foundation
import cmark_gfm
import cmark_gfm_extensions

public final class MarkdownRenderer {

    /// Render markdown string to GFM-compliant HTML
    public static func renderHTML(from markdown: String) -> String {
        // Register all GFM extensions — MUST call before using extensions
        cmark_gfm_core_extensions_ensure_registered()

        let options: Int32 = CMARK_OPT_UNSAFE | CMARK_OPT_SMART | CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        // Attach all GFM extensions
        let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        // Parse
        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let doc = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(doc) }

        // Render to HTML
        guard let htmlPtr = cmark_render_html(
            doc, options,
            cmark_parser_get_syntax_extensions(parser)
        ) else { return "" }
        defer { free(htmlPtr) }

        return String(cString: htmlPtr)
    }

    /// Post-process rendered HTML to add ARIA attributes for accessibility.
    public static func postProcessForAccessibility(_ html: String) -> String {
        var result = html
        // Add role="table" to tables (handles optional sourcepos attributes)
        result = result.replacingOccurrences(
            of: "<table(\\s[^>]*)?>",
            with: "<table$1 role=\"table\">",
            options: .regularExpression
        )
        // Add scope="col" to th elements (handles optional sourcepos/align attributes)
        result = result.replacingOccurrences(
            of: "<th(\\s[^>]*)?>",
            with: "<th$1 scope=\"col\">",
            options: .regularExpression
        )
        // Add aria-label to code blocks (handles optional sourcepos attributes)
        result = result.replacingOccurrences(
            of: "<pre(\\s[^>]*)?>",
            with: "<pre$1 aria-label=\"Code block\">",
            options: .regularExpression
        )
        // Add aria-label to task list checkboxes
        result = result.replacingOccurrences(
            of: "<input type=\"checkbox\"",
            with: "<input type=\"checkbox\" aria-label=\"Task item\""
        )
        return result
    }

    /// Wrap rendered HTML body in a full HTML document.
    /// If a template is provided, replaces {{CONTENT}}. Otherwise uses built-in template.
    public static func wrapInTemplate(_ bodyHTML: String, template: String? = nil) -> String {
        if let template = template {
            return template.replacingOccurrences(of: "{{CONTENT}}", with: bodyHTML)
        }
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <style>
                :root { color-scheme: light dark; }
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; max-width: 900px; margin: 0 auto; padding: 32px; line-height: 1.6; color: #1f2328; background: #fff; }
                @media (prefers-color-scheme: dark) { body { color: #e6edf3; background: #0d1117; } a { color: #58a6ff; } code:not([class*="language-"]) { background: #343942; color: #e6edf3; } pre { background: #161b22 !important; color: #e6edf3; } th, td { border-color: #3d444d; color: #e6edf3; } tr { background-color: #0d1117; border-top-color: #3d444db3; } tr:nth-child(2n) { background-color: #151b23; } blockquote { border-left-color: #3d444d; color: #8b949e; } hr { border-top-color: #3d444d; } h1, h2, h3, h4, h5 { color: #e6edf3; } h1, h2 { border-bottom-color: #3d444d; } h6 { color: #8b949e; } }
                h1, h2 { border-bottom: 1px solid #d1d9e0; padding-bottom: 0.3em; }
                pre { background: #f6f8fa; padding: 16px; border-radius: 6px; overflow-x: auto; }
                code { background: #eff1f3; padding: 0.2em 0.4em; border-radius: 6px; font-size: 85%; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
                pre code { background: none; padding: 0; font-size: 100%; }
                table { border-spacing: 0; border-collapse: collapse; display: block; width: max-content; max-width: 100%; overflow: auto; font-variant: tabular-nums; }
                th, td { padding: 6px 13px; border: 1px solid #d1d9e0; }
                th { font-weight: 600; }
                tr { background-color: #ffffff; border-top: 1px solid #d1d9e0b3; }
                tr:nth-child(2n) { background-color: #f6f8fa; }
                blockquote { border-left: 4px solid #d0d7de; margin: 0 0 16px 0; padding: 0 16px; color: #656d76; }
                img { max-width: 100%; }
                input[type="checkbox"] { margin-right: 0.5em; }
                hr { border: none; border-top: 1px solid #d0d7de; margin: 24px 0; }
                a { color: #0969da; text-decoration: none; }
                a:hover { text-decoration: underline; }
            </style>
        </head>
        <body><article role="document" aria-label="Rendered markdown content">\(bodyHTML)</article></body>
        </html>
        """
    }
}
