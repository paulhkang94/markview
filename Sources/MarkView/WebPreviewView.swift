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

        init() {
            // Load bundled Prism.js
            if let prismURL = Bundle.module.url(forResource: "prism-bundle.min", withExtension: "js", subdirectory: "Resources") {
                prismJS = try? String(contentsOf: prismURL, encoding: .utf8)
            }
        }

        func updateContent(_ html: String, in webView: WKWebView) {
            guard html != lastHTML else { return }
            lastHTML = html

            if !hasLoadedInitialPage {
                // First load: inject Prism.js into the HTML before loading
                let fullHTML = injectPrism(into: html)
                webView.loadHTMLString(fullHTML, baseURL: nil)
                hasLoadedInitialPage = true
            } else {
                // Subsequent updates: use JS to replace content and preserve scroll
                updateContentViaJS(html, in: webView)
            }
        }

        private func injectPrism(into html: String) -> String {
            guard let prismJS = prismJS else { return html }
            let scriptTag = "<script>\(prismJS)\nPrism.manual = false; Prism.highlightAll();</script>"
            return html.replacingOccurrences(of: "</body>", with: "\(scriptTag)\n</body>")
        }

        private func updateContentViaJS(_ html: String, in webView: WKWebView) {
            // Extract just the body content from the full HTML
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

            let js = """
            (function() {
                var scrollPos = window.scrollY;
                var contentEl = document.getElementById('content');
                if (contentEl) {
                    contentEl.innerHTML = \(escapedContent);
                }
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
    }
}
