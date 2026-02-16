import SwiftUI
import WebKit

struct WebPreviewView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateContent(html, in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        weak var webView: WKWebView?
        private var hasLoadedInitialPage = false
        private var lastHTML: String = ""
        private var prismJS: String?
        private let settings = AppSettings.shared

        init() {
            if let prismURL = Bundle.module.url(forResource: "prism-bundle.min", withExtension: "js", subdirectory: "Resources") {
                prismJS = try? String(contentsOf: prismURL, encoding: .utf8)
            }
        }

        func updateContent(_ html: String, in webView: WKWebView) {
            guard html != lastHTML else { return }
            lastHTML = html

            let styledHTML = injectSettingsCSS(into: html)

            if !hasLoadedInitialPage {
                let fullHTML = injectPrism(into: styledHTML)
                webView.loadHTMLString(fullHTML, baseURL: nil)
                hasLoadedInitialPage = true
            } else {
                updateContentViaJS(styledHTML, in: webView)
            }
        }

        private func injectSettingsCSS(into html: String) -> String {
            var css = ""

            // Preview width and font size
            let width = settings.previewWidth.cssValue
            let fontSize = Int(settings.previewFontSize)
            css += "body { max-width: \(width); font-size: \(fontSize)px; }\n"

            // Theme override
            switch settings.theme {
            case .light:
                css += "body { color: #1f2328; background: #ffffff; }\n"
                css += ":root { color-scheme: light; }\n"
            case .dark:
                css += Self.darkModeCSS + "\n"
            case .system:
                break // Use CSS media query (default behavior)
            }

            if css.isEmpty { return html }

            let styleTag = "<style id=\"settings-override\">\(css)</style>"
            return html.replacingOccurrences(of: "</head>", with: "\(styleTag)\n</head>")
        }

        private func injectPrism(into html: String) -> String {
            guard let prismJS = prismJS else { return html }
            let scriptTag = "<script>\(prismJS)\nPrism.manual = false; Prism.highlightAll();</script>"
            return html.replacingOccurrences(of: "</body>", with: "\(scriptTag)\n</body>")
        }

        private func updateContentViaJS(_ html: String, in webView: WKWebView) {
            let bodyContent: String
            if let startRange = html.range(of: "<article id=\"content\">"),
               let endRange = html.range(of: "</article>") {
                bodyContent = String(html[startRange.upperBound..<endRange.lowerBound])
            } else if let startRange = html.range(of: "<body>"),
                      let endRange = html.range(of: "</body>") {
                bodyContent = String(html[startRange.upperBound..<endRange.lowerBound])
            } else {
                bodyContent = html
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: bodyContent, options: .fragmentsAllowed),
                  let escapedContent = String(data: jsonData, encoding: .utf8) else { return }

            // Also update settings CSS
            var css = "body { max-width: \(settings.previewWidth.cssValue); font-size: \(Int(settings.previewFontSize))px; }"
            switch settings.theme {
            case .light:
                css += " body { color: #1f2328; background: #ffffff; } :root { color-scheme: light; }"
            case .dark:
                css += " " + Self.darkModeCSS
            case .system:
                break
            }

            let js = """
            (function() {
                var scrollPos = window.scrollY;
                var contentEl = document.getElementById('content');
                if (contentEl) {
                    contentEl.innerHTML = \(escapedContent);
                }
                var existing = document.getElementById('settings-override');
                if (existing) { existing.textContent = \(Self.jsStringLiteral(css)); }
                if (typeof Prism !== 'undefined') {
                    Prism.highlightAll();
                }
                requestAnimationFrame(function() {
                    window.scrollTo(0, scrollPos);
                });
            })();
            """
            webView.evaluateJavaScript(js)
        }

        /// Single source of truth for forced-dark theme CSS (GitHub Primer colors).
        /// Used by both injectSettingsCSS (initial load) and updateContentViaJS (live updates).
        private static let darkModeCSS = [
            "body { color: #e6edf3; background: #0d1117; }",
            ":root { color-scheme: dark; }",
            "a { color: #58a6ff; }",
            "code:not([class*=\"language-\"]) { background: #343942; color: #e6edf3; }",
            "pre { background: #161b22 !important; }",
            "th, td { border-color: #3d444d; }",
            "tr { background-color: #0d1117; border-top-color: #3d444db3; }",
            "tr:nth-child(2n) { background-color: #151b23; }",
            "blockquote { border-left-color: #3d444d; color: #8b949e; }",
            "hr { border-top-color: #3d444d; }",
            "h1, h2 { border-bottom-color: #3d444d; }",
            "h6 { color: #8b949e; }",
        ].joined(separator: " ")

        private static func jsStringLiteral(_ s: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed),
                  let str = String(data: data, encoding: .utf8) else { return "\"\"" }
            return str
        }
    }
}
