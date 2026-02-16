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

            // Preview width
            let width = settings.previewWidth.cssValue
            css += "body { max-width: \(width); }\n"

            // Theme override
            switch settings.theme {
            case .light:
                css += "body { color: #1f2328; background: #ffffff; }\n"
                css += ":root { color-scheme: light; }\n"
            case .dark:
                css += "body { color: #e6edf3; background: #0d1117; }\n"
                css += ":root { color-scheme: dark; }\n"
                css += "a { color: #58a6ff; }\n"
                css += "code:not([class*=\"language-\"]) { background: #343942; }\n"
                css += "pre { background: #161b22 !important; }\n"
                css += "th { background: #161b22; }\n"
                css += "th, td { border-color: #30363d; }\n"
                css += "blockquote { border-left-color: #30363d; color: #8b949e; }\n"
                css += "h1, h2 { border-bottom-color: #30363d; }\n"
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
            var css = "body { max-width: \(settings.previewWidth.cssValue); }"
            switch settings.theme {
            case .light:
                css += " body { color: #1f2328; background: #fff; } :root { color-scheme: light; }"
            case .dark:
                css += " body { color: #e6edf3; background: #0d1117; } :root { color-scheme: dark; }"
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

        private static func jsStringLiteral(_ s: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed),
                  let str = String(data: data, encoding: .utf8) else { return "\"\"" }
            return str
        }
    }
}
