import SwiftUI
import WebKit

struct WebPreviewView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityLabel(Strings.markdownPreview)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Sync WKWebView appearance with system so @media (prefers-color-scheme) works
        let settings = AppSettings.shared
        switch settings.theme {
        case .light:
            webView.appearance = NSAppearance(named: .aqua)
        case .dark:
            webView.appearance = NSAppearance(named: .darkAqua)
        case .system:
            webView.appearance = nil // inherit from system
        }
        context.coordinator.updateContent(html, in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var hasLoadedInitialPage = false
        private var hasSizedWindow = false
        private var lastHTML: String = ""
        private var prismJS: String?
        private let settings = AppSettings.shared

        override init() {
            if let prismURL = Bundle.module.url(forResource: "prism-bundle.min", withExtension: "js", subdirectory: "Resources") {
                prismJS = try? String(contentsOf: prismURL, encoding: .utf8)
            }
            super.init()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasSizedWindow else { return }
            hasSizedWindow = true
            sizeWindowToContent(webView)
        }

        private func sizeWindowToContent(_ webView: WKWebView) {
            let js = "JSON.stringify({w: document.documentElement.scrollWidth, h: document.documentElement.scrollHeight})"
            webView.evaluateJavaScript(js) { [weak webView] result, _ in
                guard let webView = webView,
                      let json = result as? String,
                      let data = json.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: CGFloat],
                      let contentWidth = dict["w"],
                      let contentHeight = dict["h"],
                      let window = webView.window,
                      let screen = window.screen ?? NSScreen.main else { return }

                let screenFrame = screen.visibleFrame
                let titleBarHeight: CGFloat = 28
                let statusBarHeight: CGFloat = 24
                let chrome = titleBarHeight + statusBarHeight
                let horizontalPadding: CGFloat = 40

                let targetWidth = min(contentWidth + horizontalPadding, screenFrame.width)
                let targetHeight = min(contentHeight + chrome, screenFrame.height)

                let width = max(targetWidth, 600)
                let height = max(targetHeight, 400)

                let x = screenFrame.origin.x + (screenFrame.width - width) / 2
                let y = screenFrame.origin.y + (screenFrame.height - height) / 2
                window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: true)
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
                // Detect current system appearance and inject dark CSS explicitly,
                // because WKWebView's @media (prefers-color-scheme) is unreliable
                if Self.systemIsDarkMode {
                    css += Self.darkModeCSS + "\n"
                }
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
            if let startRange = html.range(of: "<article id=\"content\"", options: .literal).flatMap({ html.range(of: ">", range: $0.upperBound..<html.endIndex) }),
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
                if Self.systemIsDarkMode {
                    css += " " + Self.darkModeCSS
                }
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

        /// Detect if the system is currently in dark mode.
        private static var systemIsDarkMode: Bool {
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        /// Single source of truth for forced-dark theme CSS (GitHub Primer colors).
        /// Used by both injectSettingsCSS (initial load) and updateContentViaJS (live updates).
        /// IMPORTANT: Every element with a visual property MUST have an explicit color set here —
        /// do NOT rely on CSS inheritance from body, as WKWebView dark mode is unreliable.
        private static let darkModeCSS = [
            "body { color: #e6edf3; background: #0d1117; }",
            ":root { color-scheme: dark; }",
            "a { color: #58a6ff; }",
            "code:not([class*=\"language-\"]) { background: #343942; color: #e6edf3; }",
            "pre { background: #161b22 !important; color: #e6edf3; }",
            "th, td { border-color: #3d444d; color: #e6edf3; }",
            "tr { background-color: #0d1117; border-top-color: #3d444db3; }",
            "tr:nth-child(2n) { background-color: #151b23; }",
            "blockquote { border-left-color: #3d444d; color: #8b949e; }",
            "hr { border-top-color: #3d444d; }",
            "h1, h2 { border-bottom-color: #3d444d; color: #e6edf3; }",
            "h6 { color: #8b949e; }",
        ].joined(separator: " ")

        private static func jsStringLiteral(_ s: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed),
                  let str = String(data: data, encoding: .utf8) else { return "\"\"" }
            return str
        }
    }
}
