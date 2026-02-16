import SwiftUI
import WebKit

struct WebPreviewView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent until loaded
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

        func updateContent(_ html: String, in webView: WKWebView) {
            guard html != lastHTML else { return }
            lastHTML = html

            if !hasLoadedInitialPage {
                // First load — use loadHTMLString
                webView.loadHTMLString(html, baseURL: nil)
                hasLoadedInitialPage = true
            } else {
                // Subsequent updates — use JS injection to preserve scroll position
                let escapedHTML = escapeForJS(html)
                let js = """
                (function() {
                    var scrollPos = window.scrollY;
                    document.open();
                    document.write(\(escapedHTML));
                    document.close();
                    requestAnimationFrame(function() { window.scrollTo(0, scrollPos); });
                })();
                """
                webView.evaluateJavaScript(js)
            }
        }

        private func escapeForJS(_ str: String) -> String {
            // Use JSON encoding for safe string escaping
            if let data = try? JSONSerialization.data(withJSONObject: str, options: .fragmentsAllowed),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "\"\""
        }
    }
}
