import Foundation

/// Assembles the full HTML document delivered to WKWebView by injecting
/// bundled JS libraries (Prism, Mermaid, KaTeX) into a rendered template.
///
/// Extracted from WebPreviewView so the injection pipeline is testable
/// without an AppKit dependency. All methods are pure String transformations.
public struct HTMLPipeline {

    public let prismJS: String?
    public let mermaidJS: String?
    public let katexJS: String?
    public let katexAutoRenderJS: String?

    public init(
        prismJS: String? = nil,
        mermaidJS: String? = nil,
        katexJS: String? = nil,
        katexAutoRenderJS: String? = nil
    ) {
        self.prismJS = prismJS
        self.mermaidJS = mermaidJS
        // Require both KaTeX bundles — one without the other is unusable
        self.katexJS = katexAutoRenderJS == nil ? nil : katexJS
        self.katexAutoRenderJS = katexAutoRenderJS
    }

    /// Convenience initialiser that loads all JS bundles from MarkViewCore's
    /// resource bundle (the path used at runtime by the test runner and MCP server).
    /// The Xcode app target uses ResourceBundle instead (translocation-safe).
    public static func loadFromBundle() -> HTMLPipeline {
        func load(_ name: String, ext: String = "js") -> String? {
            // SPM .process() resources are placed at the bundle root, not in a subdirectory.
            // Try without subdirectory first (debug/release SPM builds), then with "Resources"
            // as a fallback for any future layout changes.
            if let url = Bundle.module.url(forResource: name, withExtension: ext) {
                return try? String(contentsOf: url, encoding: .utf8)
            }
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources") {
                return try? String(contentsOf: url, encoding: .utf8)
            }
            return nil
        }
        return HTMLPipeline(
            prismJS: load("prism-bundle.min"),
            mermaidJS: load("mermaid.min"),
            katexJS: load("katex.min"),
            katexAutoRenderJS: load("auto-render.min")
        )
    }

    // MARK: - Public assembly

    /// Convenience: render markdown → fully assembled HTML document in one call.
    /// Loads the template and all JS bundles from MarkViewCore's resource bundle.
    /// Used by MarkViewHTMLGen CLI and test fixtures.
    public static func assembleFullDocument(from markdown: String) -> String {
        let bodyHTML = MarkdownRenderer.renderHTML(from: markdown)
        let accessibleHTML = MarkdownRenderer.postProcessForAccessibility(bodyHTML)
        let template: String?
        if let url = Bundle.module.url(forResource: "template", withExtension: "html") {
            template = try? String(contentsOf: url, encoding: .utf8)
        } else if let url = Bundle.module.url(forResource: "template", withExtension: "html", subdirectory: "Resources") {
            template = try? String(contentsOf: url, encoding: .utf8)
        } else {
            template = nil
        }
        let baseHTML = MarkdownRenderer.wrapInTemplate(accessibleHTML, template: template)
        return HTMLPipeline.loadFromBundle().assemble(baseHTML)
    }

    /// Produce the fully assembled HTML document: template with all JS injected.
    public func assemble(_ templateHTML: String) -> String {
        var html = templateHTML
        html = injectPrism(html)
        html = injectMermaid(html)
        html = injectKaTeX(html)
        return html
    }

    // MARK: - Injection helpers (public for testing — no AppKit consumers outside this module)

    /// Replace only the final `</body>` tag. Must use backwards search — bundled
    /// JS (mermaid.min.js bundles DOMPurify) contains `</body>` as a string literal.
    /// Forward `replacingOccurrences` replaces those internal occurrences and corrupts
    /// the HTML, causing JS source to render as visible text.
    public func insertBeforeBodyClose(_ script: String, into html: String) -> String {
        guard let range = html.range(of: "</body>", options: .backwards) else {
            return html + script
        }
        return html.replacingCharacters(in: range, with: "\(script)\n</body>")
    }

    public func injectPrism(_ html: String) -> String {
        guard let js = prismJS else { return html }
        let scriptTag = "<script>\(js)\nPrism.manual = false; Prism.highlightAll();</script>"
        return insertBeforeBodyClose(scriptTag, into: html)
    }

    public func injectMermaid(_ html: String) -> String {
        guard let js = mermaidJS else { return html }
        // The bridge converts cmark-gfm output (<pre><code class="language-mermaid">) to
        // Mermaid-ready <div class="mermaid"> elements, then calls mermaid.run().
        // Exposed as window._markviewRenderMermaid so the JS fast-path can re-invoke it
        // after innerHTML swaps without reloading the full library.
        let scriptTag = """
        <script>
        \(js)
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
                        // 1. Responsive sizing: viewBox preserves aspect ratio; removing
                        //    fixed width+height lets the SVG scale with zoom and container.
                        //    Without this, Mermaid outputs e.g. width="800" height="400" which
                        //    clips or overflows instead of scaling when the user zooms.
                        var w = parseFloat(svg.getAttribute('width') || '0');
                        var h = parseFloat(svg.getAttribute('height') || '0');
                        if (w > 0 && h > 0 && !svg.getAttribute('viewBox')) {
                            svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
                        }
                        svg.removeAttribute('width');
                        svg.removeAttribute('height');
                        svg.style.maxWidth = '100%';
                        svg.style.width = '100%';
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
                    window.rendered = true;  // Mermaid async complete — unblock Playwright/WKWebView sentinel
                }).catch(function() { window.rendered = true; });  // unblock on error too
            };
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', window._markviewRenderMermaid);
            } else {
                window._markviewRenderMermaid();
            }
        })();
        </script>
        """
        return insertBeforeBodyClose(scriptTag, into: html)
    }

    public func injectKaTeX(_ html: String) -> String {
        guard let katex = katexJS, let autoRender = katexAutoRenderJS else { return html }
        // KaTeX bundles DOMPurify which contains the literal string "</script>" — this would
        // end the <script> tag prematurely if not escaped, causing JS source to render as text.
        // Replacing "</script>" with "<\/script>" is safe: browsers parse them identically inside
        // JS but the HTML parser doesn't treat "<\/script>" as a closing tag.
        let safeKatex = katex.replacingOccurrences(of: "</script>", with: "<\\/script>")
        let safeAutoRender = autoRender.replacingOccurrences(of: "</script>", with: "<\\/script>")
        let script = """
        <script>\(safeKatex)</script>
        <script>
        \(safeAutoRender)
        document.addEventListener("DOMContentLoaded", function() {
            renderMathInElement(document.body, {
                delimiters: [
                    {left: "$$", right: "$$", display: true},
                    {left: "$", right: "$", display: false},
                    {left: "\\\\(", right: "\\\\)", display: false},
                    {left: "\\\\[", right: "\\\\]", display: true}
                ],
                output: "mathml",
                throwOnError: false
            });
        });
        </script>
        """
        return insertBeforeBodyClose(script, into: html)
    }
}
