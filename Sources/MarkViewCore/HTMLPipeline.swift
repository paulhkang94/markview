import Foundation

// MARK: - PHK Debug

/// Lightweight debug logger gated on PHK_DEBUG env var.
/// Enable: `PHK_DEBUG=1 swift run MarkViewHTMLGen ...` or `PHK_DEBUG=1 swift run MarkViewTestRunner`.
/// Zero overhead in production (env var read once at process start).
enum PHKDebug {
    static let enabled = ProcessInfo.processInfo.environment["PHK_DEBUG"] != nil
    static func log(_ msg: String, file: String = #fileID, line: Int = #line) {
        guard enabled else { return }
        fputs("[PHK] \(msg) (\(file):\(line))\n", stderr)
    }
}

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
        PHKDebug.log("loadFromBundle() — bundle: \(Bundle.module.bundlePath)")
        func load(_ name: String, ext: String = "js") -> String? {
            // SPM .process() resources are placed at the bundle root, not in a subdirectory.
            // Try without subdirectory first (debug/release SPM builds), then with "Resources"
            // as a fallback for any future layout changes.
            if let url = Bundle.module.url(forResource: name, withExtension: ext) {
                let content = try? String(contentsOf: url, encoding: .utf8)
                PHKDebug.log("  \(name).\(ext): \(content.map { "\($0.count) bytes" } ?? "READ FAILED")")
                return content
            }
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources") {
                let content = try? String(contentsOf: url, encoding: .utf8)
                PHKDebug.log("  \(name).\(ext) (Resources/): \(content.map { "\($0.count) bytes" } ?? "READ FAILED")")
                return content
            }
            PHKDebug.log("  \(name).\(ext): NOT FOUND in bundle ⚠️")
            return nil
        }
        let pipeline = HTMLPipeline(
            prismJS: load("prism-bundle.min"),
            mermaidJS: load("mermaid.min"),
            katexJS: load("katex.min"),
            katexAutoRenderJS: load("auto-render.min")
        )
        PHKDebug.log("loadFromBundle() done — prism:\(pipeline.prismJS != nil) mermaid:\(pipeline.mermaidJS != nil) katex:\(pipeline.katexJS != nil)")
        return pipeline
    }

    // MARK: - Image inlining

    /// Convert relative image `src` attributes to inline data URIs.
    ///
    /// Extracted from WebPreviewView so the image-inlining pipeline is testable
    /// without an AppKit dependency. The WebContent process in WKWebView is sandboxed
    /// and cannot load images from arbitrary file paths; this embeds them as base64
    /// before the HTML reaches the renderer.
    ///
    /// Only relative paths are processed (URLs, data URIs, absolute paths are skipped).
    public static func inlineLocalImages(in html: String, baseDirectory: URL) -> String {
        let pattern = "src=\"([^\"]*\\.(png|jpg|jpeg|gif|svg|webp|ico|bmp|tiff?))\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return html
        }
        var result = html
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let srcRange = Range(match.range(at: 1), in: html) else { continue }
            let src = String(html[srcRange])
            guard !src.hasPrefix("http://"), !src.hasPrefix("https://"),
                  !src.hasPrefix("data:"), !src.hasPrefix("file://"),
                  !src.hasPrefix("/") else { continue }
            let imageURL = baseDirectory.appendingPathComponent(src)
            guard let data = try? Data(contentsOf: imageURL) else { continue }
            let ext = imageURL.pathExtension.lowercased()
            let mime: String
            switch ext {
            case "png":        mime = "image/png"
            case "jpg","jpeg": mime = "image/jpeg"
            case "gif":        mime = "image/gif"
            case "svg":        mime = "image/svg+xml"
            case "webp":       mime = "image/webp"
            case "ico":        mime = "image/x-icon"
            case "bmp":        mime = "image/bmp"
            case "tif","tiff": mime = "image/tiff"
            default:           mime = "image/\(ext)"
            }
            let dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
            if let attrRange = Range(match.range(at: 0), in: result) {
                result.replaceSubrange(attrRange, with: "src=\"\(dataURI)\"")
            }
        }
        return result
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
        <style>
        /* Mermaid pan/zoom/copy controls — shown on diagram hover, matches GitHub UX */
        /* Sizing: 32px buttons (Material/Apple standard for pointer-driven macOS) */
        .mermaid { position: relative; overflow: hidden; }
        .mermaid-inner { transform-origin: 50% 50%; transition: transform 0.1s ease; }
        .mermaid-controls {
            position: absolute; top: 8px; right: 8px;
            display: flex; flex-direction: row; gap: 4px;
            opacity: 0; transition: opacity 120ms ease-in-out;
            z-index: 20; pointer-events: none;
        }
        .mermaid:hover .mermaid-controls { opacity: 1; pointer-events: auto; }
        .mermaid-ctrl-group {
            display: grid; gap: 3px;
            background: rgba(128,128,128,0.08);
            border: 1px solid rgba(128,128,128,0.2);
            border-radius: 6px; padding: 6px;
            backdrop-filter: blur(6px);
        }
        .mermaid-ctrl-nav { grid-template-columns: repeat(3, 32px); grid-template-rows: repeat(3, 32px); }
        .mermaid-ctrl-zoom { grid-template-columns: 32px; grid-template-rows: repeat(3, 32px); }
        .mermaid-btn {
            width: 32px; height: 32px; padding: 0; margin: 0;
            background: rgba(128,128,128,0.1); border: none; border-radius: 4px;
            cursor: pointer; font-size: 14px; line-height: 1;
            display: flex; align-items: center; justify-content: center;
            color: inherit;
        }
        .mermaid-btn:hover { background: rgba(128,128,128,0.25); }
        .mermaid-btn-spacer { width: 32px; height: 32px; }
        @media (prefers-color-scheme: dark) {
            .mermaid-ctrl-group { background: rgba(255,255,255,0.08); border-color: rgba(255,255,255,0.15); }
            .mermaid-btn { background: rgba(255,255,255,0.1); }
            .mermaid-btn:hover { background: rgba(255,255,255,0.2); }
        }
        </style>
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
                    // 3. Pan/zoom/copy controls (GitHub parity)
                    window._PHK_DEBUG && console.log('[PHK] mermaid controls: adding to', document.querySelectorAll('.mermaid').length, 'diagrams');
                    document.querySelectorAll('.mermaid').forEach(function(container) {
                        var svg = container.querySelector('svg');
                        if (!svg || container.querySelector('.mermaid-controls')) return; // skip if already added
                        // Wrap SVG in inner div so CSS transform doesn't fight width/height styles
                        var inner = document.createElement('div');
                        inner.className = 'mermaid-inner';
                        container.insertBefore(inner, svg);
                        inner.appendChild(svg);
                        var state = { tx: 0, ty: 0, s: 1.0 };
                        function applyTransform() {
                            inner.style.transform = 'translate(' + state.tx + 'px,' + state.ty + 'px) scale(' + state.s + ')';
                        }
                        // Build controls: nav cross (↑←⟳→↓) + zoom column (+−⎘)
                        var controls = document.createElement('div');
                        controls.className = 'mermaid-controls';
                        var B = '<button class="mermaid-btn" data-a="';
                        var SP = '<div class="mermaid-btn-spacer"></div>';
                        controls.innerHTML =
                            '<div class="mermaid-ctrl-group mermaid-ctrl-nav">' +
                                SP + B + 'u" title="Pan up">↑</button>' + SP +
                                B + 'l" title="Pan left">←</button>' + B + 'r0" title="Reset">⟳</button>' + B + 'ri" title="Pan right">→</button>' +
                                SP + B + 'd" title="Pan down">↓</button>' + SP +
                            '</div>' +
                            '<div class="mermaid-ctrl-group mermaid-ctrl-zoom">' +
                                B + 'zi" title="Zoom in">＋</button>' +
                                B + 'zo" title="Zoom out">－</button>' +
                                B + 'cp" title="Copy SVG">⎘</button>' +
                            '</div>';
                        controls.addEventListener('click', function(e) {
                            var btn = e.target.closest('[data-a]');
                            if (!btn) return;
                            e.stopPropagation();
                            var P = 40, Z = 1.3;
                            switch (btn.dataset.a) {
                                case 'u':  state.ty += P; break;
                                case 'd':  state.ty -= P; break;
                                case 'l':  state.tx += P; break;
                                case 'ri': state.tx -= P; break;
                                case 'r0': state = {tx:0, ty:0, s:1.0}; break;
                                case 'zi': state.s = Math.min(state.s * Z, 8); break;
                                case 'zo': state.s = Math.max(state.s / Z, 0.1); break;
                                case 'cp':
                                    try {
                                        var xml = new XMLSerializer().serializeToString(svg);
                                        navigator.clipboard.writeText(xml).then(function() {
                                            btn.textContent = '✓';
                                            setTimeout(function() { btn.textContent = '⎘'; }, 1200);
                                        }).catch(function() {});
                                    } catch(e) {}
                                    return;
                            }
                            applyTransform();
                        });
                        container.appendChild(controls);
                        container.style.overflow = 'hidden';
                        window._PHK_DEBUG && console.log('[PHK] mermaid controls: wired for container', container.id || container.className);
                        // Mouse wheel zoom: only on Ctrl+scroll or Cmd+scroll (macOS pinch).
                        // Plain scroll must propagate to the WKWebView for normal page scroll.
                        container.addEventListener('wheel', function(e) {
                            if (!e.ctrlKey && !e.metaKey) return; // let page scroll pass through
                            e.preventDefault();
                            var Z = e.deltaY < 0 ? 1.1 : 0.9;
                            state.s = Math.min(Math.max(state.s * Z, 0.1), 8);
                            applyTransform();
                        }, { passive: false });
                        // Click-drag to pan
                        var dragging = false, dragStartX = 0, dragStartY = 0, dragTx = 0, dragTy = 0;
                        inner.style.cursor = 'grab';
                        inner.addEventListener('mousedown', function(e) {
                            if (e.button !== 0) return;
                            dragging = true; dragStartX = e.clientX; dragStartY = e.clientY;
                            dragTx = state.tx; dragTy = state.ty;
                            inner.style.cursor = 'grabbing';
                            e.preventDefault();
                        });
                        document.addEventListener('mousemove', function(e) {
                            if (!dragging) return;
                            state.tx = dragTx + (e.clientX - dragStartX);
                            state.ty = dragTy + (e.clientY - dragStartY);
                            applyTransform();
                        });
                        document.addEventListener('mouseup', function() {
                            if (dragging) { dragging = false; inner.style.cursor = 'grab'; }
                        });
                    });
                    window.rendered = true;  // Mermaid async complete — unblock Playwright/WKWebView sentinel
                    window._PHK_DEBUG && console.log('[PHK] mermaid.run() resolved — rendered=true (path: mermaid.then)');
                }).catch(function(err) {
                    window._PHK_DEBUG && console.log('[PHK] mermaid.run() error — rendered=true (path: mermaid.catch)', err);
                    window.rendered = true;  // unblock on error too
                });
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
