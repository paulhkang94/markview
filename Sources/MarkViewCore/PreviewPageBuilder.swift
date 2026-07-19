import Foundation

/// Builds the full preview page (JS-injection assembly + optional local-image
/// inlining) and writes it to a unique temp file for `WKWebView.loadFileURL`.
///
/// Extracted from `WebPreviewView.Coordinator` so the whole full-reload
/// pipeline can run OFF the main thread (item-713 / mar-028, third hang
/// class): `HTMLPipeline.assemble` performs string surgery over ~3.2 MB of
/// injected JS bundles, image inlining reads files + base64-encodes them, and
/// the temp-file write is synchronous disk I/O — all of which previously ran
/// on the main actor inside `loadViaFileURL` on every full page reload
/// (file open, tab switch, base-directory change).
///
/// Pure function of its inputs — safe to call from any thread or executor.
/// The step order (assemble first, THEN inline images) is parity-exact with
/// the replaced main-thread code path and is test-pinned.
public enum PreviewPageBuilder {

    /// Assemble the final HTML document and write it to a unique
    /// `markview-preview-<uuid>.html` file inside `temporaryDirectory`.
    ///
    /// - Parameters:
    ///   - styledHTML: template HTML with the per-view settings CSS already
    ///     injected (the Coordinator does that cheap step on the main actor).
    ///   - baseDirectory: when non-nil, relative image `src` attributes are
    ///     inlined as data URIs (sandboxed WebContent can't read local files).
    ///   - pipeline: the JS-injection pipeline (Prism → diff2html → Mermaid → KaTeX).
    ///   - temporaryDirectory: injectable for tests; defaults to the process
    ///     temp directory used by the shipping app.
    /// - Returns: URL of the written temp file.
    /// - Throws: any file-write error, so the caller can log and keep the
    ///   reload retryable instead of silently loading a missing file.
    public static func assembleAndWrite(
        styledHTML: String,
        baseDirectory: URL?,
        pipeline: HTMLPipeline,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        var finalHTML = pipeline.assemble(styledHTML)
        // Inline local images as data URIs: the sandboxed WKWebView WebContent process
        // can't access files outside the app container even with allowingReadAccessTo.
        // Embedding images in the HTML string eliminates the file access requirement.
        if let dir = baseDirectory {
            finalHTML = HTMLPipeline.inlineLocalImages(in: finalHTML, baseDirectory: dir)
        }
        let tempFile = temporaryDirectory
            .appendingPathComponent("markview-preview-\(UUID().uuidString).html")
        try finalHTML.write(to: tempFile, atomically: true, encoding: .utf8)
        return tempFile
    }
}
