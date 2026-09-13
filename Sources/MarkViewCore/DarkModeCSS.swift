/// Dark appearance overrides shared by the app, Quick Look, and fallback document.
/// The bundled HTML template owns its CSS variables; tests keep that palette aligned.
public enum DarkModeCSS {
    private static let foreground = "#e6edf3"
    private static let muted = "#8b949e"
    private static let canvas = "#0d1117"
    private static let subtle = "#151b23"
    private static let inset = "#161b22"
    private static let border = "#3d444d"
    private static let accent = "#58a6ff"

    private static let rules: [(String, [(String, String)])] = [
        ("body", [("color", foreground), ("background", canvas)]),
        ("a", [("color", accent)]),
        // Preserve the existing override's inline-code shade, distinct from the template.
        ("code:not([class*=\"language-\"])", [("background", "#343942"), ("color", foreground)]),
        ("pre", [("background", inset + " !important"), ("color", foreground)]),
        ("th, td", [("border-color", border), ("color", foreground)]),
        ("tr", [("background-color", canvas), ("border-top-color", border + "b3")]),
        ("tr:nth-child(2n)", [("background-color", subtle)]),
        ("blockquote", [("border-left-color", border), ("color", muted)]),
        ("hr", [("border-top-color", border)]),
        ("h1, h2, h3, h4, h5", [("color", foreground)]),
        ("h1, h2", [("border-bottom-color", border)]),
        ("h6", [("color", muted)]),
    ]

    /// User-selected appearance overrides the system color scheme in the app.
    public static let app: String = {
        var lines = render(important: false)
        lines.insert(":root { color-scheme: dark; }", at: 1)
        return lines.joined(separator: " ")
    }()

    /// Extension WebContent does not inherit host appearance. Force every declaration.
    public static let quickLook = render(important: true)
        .map { "    " + $0 }.joined(separator: "\n")

    /// The fallback document already declares its supported color schemes.
    public static let inlineTemplate = render(important: false).joined(separator: " ")

    private static func render(important: Bool) -> [String] {
        rules.map { selector, declarations in
            let body = declarations.map { property, value in
                let suffix = important && !value.hasSuffix(" !important") ? " !important" : ""
                return "\(property): \(value)\(suffix);"
            }.joined(separator: " ")
            return "\(selector) { \(body) }"
        }
    }
}
