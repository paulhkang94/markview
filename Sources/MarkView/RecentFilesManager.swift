import AppKit
import SwiftUI

/// Manages the app's recently opened files list.
///
/// **Why not NSDocumentController?**
/// `NSDocumentController.noteNewRecentDocumentURL` is a no-op for non-document-based apps
/// (apps that don't subclass NSDocument). MarkView uses a single `Window` scene, so we
/// own the recents list directly in UserDefaults.
///
/// Storage: up to `maxItems` file paths as a JSON array under `recentFilePaths` in
/// UserDefaults.standard. The list is in MRU order (most recently opened first).
@MainActor
final class RecentFilesManager: ObservableObject {
    static let shared = RecentFilesManager()
    private init() { pruneAndPublish() }

    /// Currently-known recent URLs that exist on disk, in MRU order.
    @Published private(set) var recentFileURLs: [URL] = []

    private let pathsKey = "recentFilePaths"
    private let lastFileKey = "lastOpenedFilePath"
    static let maxItems = 15

    // MARK: - Public Interface

    /// Record a file open. Call this whenever a file is successfully loaded.
    func recordOpen(url: URL) {
        var paths = storedPaths()
        // Remove any existing entry for this path, then prepend (MRU = front)
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > Self.maxItems {
            paths = Array(paths.prefix(Self.maxItems))
        }
        UserDefaults.standard.set(paths, forKey: pathsKey)
        UserDefaults.standard.set(url.path, forKey: lastFileKey)
        pruneAndPublish()
    }

    /// Re-read from UserDefaults (e.g., after external changes or on view appear).
    func refresh() {
        pruneAndPublish()
    }

    /// Remove a single URL from the list.
    func removeFromRecents(url: URL) {
        var paths = storedPaths()
        paths.removeAll { $0 == url.path }
        UserDefaults.standard.set(paths, forKey: pathsKey)
        if url.path == UserDefaults.standard.string(forKey: lastFileKey) {
            UserDefaults.standard.removeObject(forKey: lastFileKey)
        }
        pruneAndPublish()
    }

    /// Clear all recents.
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: pathsKey)
        UserDefaults.standard.removeObject(forKey: lastFileKey)
        pruneAndPublish()
    }

    /// The file to auto-reopen on cold launch, or nil if disabled or no history.
    var lastOpenedURL: URL? {
        // Read directly from UserDefaults (not @AppStorage) to ensure the value
        // is current at the time this is called, even before SwiftUI has set up
        // the @AppStorage binding. Default is true when the key has never been set.
        let windowRestore: Bool
        if UserDefaults.standard.object(forKey: "windowRestore") != nil {
            windowRestore = UserDefaults.standard.bool(forKey: "windowRestore")
        } else {
            windowRestore = true  // key absent → use default
        }
        guard windowRestore else { return nil }
        // Prefer the explicit last-opened path over recentFileURLs[0] because
        // the user might remove items from recents without changing the last-opened.
        if let path = UserDefaults.standard.string(forKey: lastFileKey),
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return recentFileURLs.first
    }

    // MARK: - Private

    private func storedPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: pathsKey) ?? []
    }

    /// Filter out missing files and publish the result.
    private func pruneAndPublish() {
        let fm = FileManager.default
        let live = storedPaths().filter { fm.fileExists(atPath: $0) }
        recentFileURLs = live.map { URL(fileURLWithPath: $0) }
    }
}
