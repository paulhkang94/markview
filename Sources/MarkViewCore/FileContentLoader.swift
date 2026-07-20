import Foundation

/// Reads a markdown file's content from disk.
///
/// Extracted from `PreviewViewModel.loadContent` (item-713 fourth hang class,
/// mar-037 / APPLE-MACOS-33): every file open (`loadFile`), external-change
/// reload (`reloadFromDisk`), and file-watcher callback ran
/// `String(contentsOfFile:)` synchronously on the main actor — for a large
/// document, or a file on a slow/network volume, this blocks the main thread
/// for the duration of the read. Same hang class already fixed for JS bundles
/// (#55), doc stats (#57), and full-page assemble (mar-028/#59).
///
/// Pure function of its input — safe to call from any thread or executor.
public enum FileContentLoader {

    /// Read `path` as UTF-8 text.
    ///
    /// Resolves symlinks first (avoids `file://` URL mismatches with the
    /// FileWatcher and WKWebView base-directory logic), then falls back to
    /// the original, unresolved path if that read fails — parity with the
    /// replaced main-thread code, which used the same two-step fallback.
    ///
    /// - Throws: the fallback-path read error if BOTH reads fail (matches the
    ///   old behavior, which surfaced the original-path error to the caller).
    public static func read(from path: String) throws -> String {
        let resolvedPath = (path as NSString).resolvingSymlinksInPath
        do {
            return try String(contentsOfFile: resolvedPath, encoding: .utf8)
        } catch {
            return try String(contentsOfFile: path, encoding: .utf8)
        }
    }
}
