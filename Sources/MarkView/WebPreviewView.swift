import SwiftUI
import WebKit
import MarkViewCore

struct WebPreviewView: NSViewRepresentable {
    let html: String
    var baseDirectoryURL: URL?
    /// Unique identifier for the current file. When this changes (new file opened),
    /// the coordinator forces a full page reload instead of the JS fast-path.
    var fileIdentifier: String?
    // These must be explicit properties (not read from AppSettings inside updateNSView)
    // so that SwiftUI detects changes and triggers updateNSView.
    var previewFontSize: Double = 16
    var previewWidth: String = "900px"
    var theme: AppTheme = .system
    /// Direct reference to the scroll sync controller (not a SwiftUI binding).
    var syncController: ScrollSyncController?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Security: Do NOT enable allowFileAccessFromFileURLs — it allows JS to fetch
        // arbitrary file:// URLs, which combined with XSS could leak local files.
        // Local images are loaded via <base href> + allowingReadAccessTo scope instead.

        // Register message handler for scroll sync: JS posts source line to Swift.
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: TemplateConstants.scrollSyncHandler)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityLabel(Strings.markdownPreview)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.syncController = syncController

        // Register coordinator with the sync controller for direct calls
        syncController?.previewCoordinator = context.coordinator

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Sync WKWebView appearance with system so @media (prefers-color-scheme) works
        switch theme {
        case .light:
            webView.appearance = NSAppearance(named: .aqua)
        case .dark:
            webView.appearance = NSAppearance(named: .darkAqua)
        case .system:
            webView.appearance = nil // inherit from system
        }
        context.coordinator.baseDirectoryURL = baseDirectoryURL
        context.coordinator.fileIdentifier = fileIdentifier
        context.coordinator.previewFontSize = previewFontSize
        context.coordinator.previewWidth = previewWidth
        context.coordinator.theme = theme
        context.coordinator.syncController = syncController
        syncController?.previewCoordinator = context.coordinator
        context.coordinator.updateContent(html, in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var baseDirectoryURL: URL?
        var fileIdentifier: String?
        var previewFontSize: Double = 16
        var previewWidth: String = "900px"
        var theme: AppTheme = .system
        weak var syncController: ScrollSyncController?
        private var hasLoadedInitialPage = false
        private var lastHTML: String = ""
        private var lastCSS: String = ""
        private var lastBaseDirectory: URL?
        private var lastFileIdentifier: String?
        private var prismJS: String?
        private var mermaidJS: String?
        /// When true, ignore the next scroll event from JS (it's from a programmatic scroll).
        var suppressNextScroll = false

        override init() {
            if let prismURL = ResourceBundle.url(forResource: "prism-bundle.min", withExtension: "js", subdirectory: "Resources") {
                do {
                    prismJS = try String(contentsOf: prismURL, encoding: .utf8)
                } catch {
                    AppLogger.render.warning("Failed to load Prism.js bundle: \(error.localizedDescription)")
                    AppLogger.breadcrumb("Prism.js load failed", category: "render", level: .warning)
                }
            } else {
                AppLogger.render.warning("Prism.js bundle resource not found")
                AppLogger.breadcrumb("Prism.js resource missing", category: "render", level: .warning)
            }

            if let mermaidURL = ResourceBundle.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Resources") {
                do {
                    mermaidJS = try String(contentsOf: mermaidURL, encoding: .utf8)
                } catch {
                    AppLogger.render.warning("Failed to load Mermaid.js bundle: \(error.localizedDescription)")
                    AppLogger.breadcrumb("Mermaid.js load failed", category: "render", level: .warning)
                }
            } else {
                AppLogger.render.warning("Mermaid.js bundle resource not found")
                AppLogger.breadcrumb("Mermaid.js resource missing", category: "render", level: .warning)
            }
        }

        // MARK: - WKScriptMessageHandler

        /// Receives source line messages from the JS scroll listener.
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == TemplateConstants.scrollSyncHandler else { return }

            if suppressNextScroll {
                suppressNextScroll = false
                return
            }

            // JS sends the source line of the topmost visible element with data-sourcepos
            if let line = message.body as? Int, line > 0 {
                syncController?.previewDidScrollToLine(line)
            }
        }

        // MARK: - WKNavigationDelegate

        /// Intercept link clicks: open external URLs in the system browser,
        /// allow local file:// loads (preview content) to proceed in-place.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }

            // Allow initial page loads (our preview HTML) and file:// URLs
            if navigationAction.navigationType == .other || url.isFileURL {
                return .allow
            }

            // External links (http/https/mailto) → open in system browser
            if url.scheme == "https" || url.scheme == "http" || url.scheme == "mailto" {
                NSWorkspace.shared.open(url)
                return .cancel
            }

            // Anchor links within the page
            if url.fragment != nil && url.path == webView.url?.path {
                return .allow
            }

            return .cancel
        }

        // MARK: - Scroll Sync JS

        /// JavaScript scroll sync system. Builds a cached sorted array of {line, offsetTop}
        /// on content load/mutation, then binary-searches on scroll — O(log n) per frame,
        /// no DOM queries in the scroll path.
        private static let scrollListenerJS = """
        (function() {
            if (window._markviewScrollListenerInstalled) return;
            window._markviewScrollListenerInstalled = true;
            var _rafPending = false;
            var _lastLine = 0;

            // Cached sourcepos map: sorted array of {line, top}
            // Rebuilt on content change via _markviewRebuildCache()
            window._markviewSourceCache = [];

            window._markviewRebuildCache = function() {
                var elements = document.querySelectorAll('[data-sourcepos]');
                var cache = [];
                for (var i = 0; i < elements.length; i++) {
                    var sp = elements[i].getAttribute('data-sourcepos');
                    if (!sp) continue;
                    var line = parseInt(sp.split(':')[0], 10);
                    if (isNaN(line)) continue;
                    var rect = elements[i].getBoundingClientRect();
                    cache.push({ line: line, top: rect.top + window.scrollY });
                }
                // Already sorted by DOM order (top position)
                window._markviewSourceCache = cache;
            };

            function getTopVisibleSourceLine() {
                var cache = window._markviewSourceCache;
                if (!cache.length) return 0;
                var scrollY = window.scrollY;
                // Binary search for the last element with top <= scrollY
                var lo = 0, hi = cache.length - 1, best = 0;
                while (lo <= hi) {
                    var mid = (lo + hi) >> 1;
                    if (cache[mid].top <= scrollY + 2) {
                        best = mid;
                        lo = mid + 1;
                    } else {
                        hi = mid - 1;
                    }
                }
                return cache[best].line;
            }

            window.addEventListener('scroll', function() {
                if (window._markviewSuppressScroll) {
                    window._markviewSuppressScroll = false;
                    return;
                }
                if (_rafPending) return;
                _rafPending = true;
                requestAnimationFrame(function() {
                    _rafPending = false;
                    var line = getTopVisibleSourceLine();
                    if (line > 0 && line !== _lastLine) {
                        _lastLine = line;
                        try {
                            window.webkit.messageHandlers.scrollSync.postMessage(line);
                        } catch(e) {}
                    }
                });
            }, { passive: true });

            // Build initial cache
            window._markviewRebuildCache();
        })();
        """

        /// Scroll the preview to the element corresponding to the given source line.
        /// Uses the cached offset map for O(log n) binary search + direct window.scrollTo
        /// (no DOM query, no scrollIntoView reflow).
        func scrollToSourceLine(_ line: Int) {
            guard let webView = webView else { return }
            suppressNextScroll = true
            let js = """
            (function() {
                window._markviewSuppressScroll = true;
                var cache = window._markviewSourceCache || [];
                if (!cache.length) return;
                // Binary search for largest line <= target
                var lo = 0, hi = cache.length - 1, best = 0;
                while (lo <= hi) {
                    var mid = (lo + hi) >> 1;
                    if (cache[mid].line <= \(line)) {
                        best = mid;
                        lo = mid + 1;
                    } else {
                        hi = mid - 1;
                    }
                }
                window.scrollTo(0, cache[best].top);
            })();
            """
            webView.evaluateJavaScript(js)
        }

        // MARK: - Content Updates

        /// Tracks whether a file change is pending — ensures full page reload
        /// even if SwiftUI splits the update across multiple updateNSView calls
        /// (fileIdentifier may update before renderedHTML in separate @Published cycles).
        private var pendingFileReload = false

        func updateContent(_ html: String, in webView: WKWebView) {
            let currentCSS = "\(Int(previewFontSize))|\(previewWidth)|\(theme)"
            let cssChanged = currentCSS != lastCSS
            lastCSS = currentCSS

            // Force full page reload when a different file is opened (even from the same
            // directory) so the entire document is replaced. The JS fast-path (innerHTML
            // swap) fails silently on loadFileURL-loaded pages after the temp file is deleted.
            let fileChanged = fileIdentifier != lastFileIdentifier
            if fileChanged {
                pendingFileReload = true
            }
            lastFileIdentifier = fileIdentifier

            let baseDirChanged = baseDirectoryURL != lastBaseDirectory
            lastBaseDirectory = baseDirectoryURL

            let needsFullReload = !hasLoadedInitialPage || baseDirChanged || pendingFileReload

            guard html != lastHTML || cssChanged || needsFullReload else { return }
            lastHTML = html

            let styledHTML = injectSettingsCSS(into: html)

            if needsFullReload {
                pendingFileReload = false
                let fullHTML = injectMermaid(into: injectPrism(into: styledHTML))
                loadViaFileURL(fullHTML, in: webView)
                hasLoadedInitialPage = true
            } else {
                updateContentViaJS(styledHTML, in: webView)
            }
        }

        /// Write HTML to a temp file and load via loadFileURL so WKWebView can access local images.
        private func loadViaFileURL(_ html: String, in webView: WKWebView) {
            var finalHTML = html
            // Inject <base> tag so relative paths (images, links) resolve from the markdown file's directory
            if let dir = baseDirectoryURL {
                let baseTag = "<base href=\"\(dir.absoluteString)\">"
                finalHTML = finalHTML.replacingOccurrences(of: "<head>", with: "<head>\(baseTag)")
            }
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("markview-preview-\(UUID().uuidString).html")
            do {
                try finalHTML.write(to: tempFile, atomically: true, encoding: .utf8)
            } catch {
                AppLogger.render.error("Failed to write temp preview file: \(error.localizedDescription)")
                AppLogger.captureError(error, category: "render", message: "Temp file write failed")
            }
            // Security: Grant WKWebView read access to the markdown file's directory so
            // relative images load. <base href> handles URL resolution; allowingReadAccessTo
            // controls what the WebView can actually fetch from disk.
            // Using baseDirectoryURL directly is safe — it's the markdown's own folder,
            // not a broad path. Falls back to tempDir if no file is open (e.g. MCP preview).
            let accessURL = baseDirectoryURL ?? tempFile.deletingLastPathComponent()
            webView.loadFileURL(tempFile, allowingReadAccessTo: accessURL)
            // Install scroll listener after page loads
            installScrollListenerAfterLoad(in: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                do {
                    try FileManager.default.removeItem(at: tempFile)
                } catch {
                    AppLogger.render.error("Failed to clean up temp file: \(error.localizedDescription)")
                    AppLogger.captureError(error, category: "render", message: "Temp file cleanup failed")
                }
            }
        }

        private func installScrollListenerAfterLoad(in webView: WKWebView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                webView.evaluateJavaScript(Self.scrollListenerJS)

                // Restore scroll position after pane toggle (view recreation).
                // The syncController persists via @State in ContentView, so lastPreviewLine
                // survives the destroy/recreate cycle.
                if let line = self.syncController?.lastPreviewLine, line > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.scrollToSourceLine(line)
                    }
                }
            }
        }

        private func injectSettingsCSS(into html: String) -> String {
            var css = ""
            css += "body { max-width: \(previewWidth); font-size: \(Int(previewFontSize))px; }\n"

            switch theme {
            case .light:
                css += "body { color: #1f2328; background: #ffffff; }\n"
                css += ":root { color-scheme: light; }\n"
            case .dark:
                css += Self.darkModeCSS + "\n"
            case .system:
                if Self.systemIsDarkMode {
                    css += Self.darkModeCSS + "\n"
                }
            }

            if css.isEmpty { return html }

            let styleTag = "<style id=\"\(TemplateConstants.settingsStyleID)\">\(css)</style>"
            return html.replacingOccurrences(of: "</head>", with: "\(styleTag)\n</head>")
        }

        private func injectPrism(into html: String) -> String {
            guard let prismJS = prismJS else { return html }
            let scriptTag = "<script>\(prismJS)\nPrism.manual = false; Prism.highlightAll();</script>"
            return html.replacingOccurrences(of: "</body>", with: "\(scriptTag)\n</body>")
        }

        private func injectMermaid(into html: String) -> String {
            guard let mermaidJS = mermaidJS else { return html }
            // The bridge converts cmark-gfm output (<pre><code class="language-mermaid">) to
            // Mermaid-ready <div class="mermaid"> elements, then calls mermaid.run().
            // Exposed as window._markviewRenderMermaid so the JS fast-path can re-invoke it
            // after innerHTML swaps without reloading the full library.
            let scriptTag = """
            <script>
            \(mermaidJS)
            ;(function() {
                window._markviewRenderMermaid = function() {
                    document.querySelectorAll('pre code.language-mermaid').forEach(function(code) {
                        var pre = code.parentElement;
                        var div = document.createElement('div');
                        div.className = 'mermaid';
                        div.textContent = code.textContent;
                        pre.parentNode.replaceChild(div, pre);
                    });
                    var isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
                    // Read the document font size so diagrams scale with the preview font size slider
                    var docFontSize = parseFloat(window.getComputedStyle(document.body).fontSize) || 16;
                    mermaid.initialize({
                        startOnLoad: false,
                        theme: isDark ? 'dark' : 'default',
                        securityLevel: 'loose',
                        fontSize: docFontSize,
                        // htmlLabels:false: SVG text wraps correctly vs HTML mode which clips.
                        // rankSpacing:80 pushes the first node down far enough that multi-line
                        // subgraph titles don't overlap child nodes (Dagre default is 50 — too tight).
                        flowchart: { useMaxWidth: true, htmlLabels: false, rankSpacing: 80, nodeSpacing: 60 },
                        sequence: { useMaxWidth: true },
                        gantt: { useMaxWidth: true },
                        er: { useMaxWidth: true },
                        pie: { useMaxWidth: true }
                    });
                    mermaid.run().then(function() {
                        document.querySelectorAll('.mermaid svg').forEach(function(svg) {
                            // 1. Responsive sizing: add viewBox so max-width:100% scales correctly
                            var w = parseFloat(svg.getAttribute('width') || '0');
                            var h = parseFloat(svg.getAttribute('height') || '0');
                            if (w > 0 && h > 0 && !svg.getAttribute('viewBox')) {
                                svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
                            }
                            svg.removeAttribute('height');
                            svg.style.maxWidth = '100%';
                            svg.style.height = 'auto';
                            svg.style.display = 'block';

                            // 2. Fix subgraph label overlap: Dagre places the cluster label
                            // at the top of the cluster rect. When labels wrap to multiple lines,
                            // the first child node can overlap the title. Detect and shift label up.
                            svg.querySelectorAll('.cluster').forEach(function(cluster) {
                                var clusterRect = cluster.querySelector('rect');
                                var labelGroup = cluster.querySelector('.cluster-label');
                                if (!clusterRect || !labelGroup) return;
                                try {
                                    var labelBB = labelGroup.getBBox();
                                    var rectBB = clusterRect.getBBox();
                                    // If label bottom extends below cluster top + 10px padding, shift it up
                                    var labelBottom = labelBB.y + labelBB.height;
                                    var rectTop = rectBB.y;
                                    if (labelBottom > rectTop + labelBB.height + 10) {
                                        var shift = labelBottom - (rectTop + labelBB.height + 10);
                                        var currentTransform = labelGroup.getAttribute('transform') || '';
                                        var match = currentTransform.match(/translate\\(([^,]+),([^)]+)\\)/);
                                        if (match) {
                                            var tx = parseFloat(match[1]);
                                            var ty = parseFloat(match[2]) - shift;
                                            labelGroup.setAttribute('transform', 'translate(' + tx + ',' + ty + ')');
                                        }
                                    }
                                } catch(e) {}
                            });
                        });
                    }).catch(function() {});
                };
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', window._markviewRenderMermaid);
                } else {
                    window._markviewRenderMermaid();
                }
            })();
            </script>
            """
            return html.replacingOccurrences(of: "</body>", with: "\(scriptTag)\n</body>")
        }

        private func updateContentViaJS(_ html: String, in webView: WKWebView) {
            let bodyContent: String
            if let startRange = html.range(of: "<article id=\"\(TemplateConstants.contentElementID)\"", options: .literal).flatMap({ html.range(of: ">", range: $0.upperBound..<html.endIndex) }),
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

            var css = "body { max-width: \(previewWidth); font-size: \(Int(previewFontSize))px; }"
            switch theme {
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
                var contentEl = document.getElementById('\(TemplateConstants.contentElementID)');
                if (contentEl) {
                    contentEl.innerHTML = \(escapedContent);
                }
                var existing = document.getElementById('\(TemplateConstants.settingsStyleID)');
                if (existing) { existing.textContent = \(Self.jsStringLiteral(css)); }
                if (typeof Prism !== 'undefined') {
                    Prism.highlightAll();
                }
                if (typeof window._markviewRenderMermaid === 'function') {
                    window._markviewRenderMermaid();
                }
                requestAnimationFrame(function() {
                    window.scrollTo(0, scrollPos);
                    if (typeof window._markviewRebuildCache === 'function') {
                        window._markviewRebuildCache();
                    }
                });
            })();
            """
            webView.evaluateJavaScript(js)
            webView.evaluateJavaScript(Self.scrollListenerJS)
        }

        private static var systemIsDarkMode: Bool {
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

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
            "h1, h2, h3, h4, h5 { color: #e6edf3; }",
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
