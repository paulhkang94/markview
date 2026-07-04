import Foundation

/// Pure, testable representation of the ordered set of currently-open tabs,
/// persisted across quit/relaunch (MV-001 fix).
///
/// `TabManager` (Sources/MarkView/TabManager.swift) owns the live `tabs` /
/// `selectedTabID` state and lives in the app target, so it can't be imported
/// into MarkViewTestRunner. This type is the serialization boundary: TabManager
/// derives one of these on every change and hands it to `TabSessionStore`
/// (app target) to persist; on launch the app decodes one back and reopens
/// every path in order. Extracting the shape (and the pruning logic) here
/// keeps the restore decision behaviorally testable.
///
/// Before this existed, only a single "last opened file" path was ever
/// persisted — `RecentFilesManager.lastOpenedFilePath` is overwritten on every
/// tab open, so relaunch could reopen at most one tab regardless of how many
/// were open at quit. This type stores the FULL ordered list plus which one
/// was selected, so all of them come back in the same order.
public struct TabSessionState: Codable, Equatable, Sendable {
    /// Open tab file paths, in tab-bar order (index 0 = leftmost tab).
    public var openPaths: [String]
    /// Index into `openPaths` of the selected/frontmost tab, or nil if none
    /// was selected.
    public var selectedIndex: Int?

    public init(openPaths: [String], selectedIndex: Int?) {
        self.openPaths = openPaths
        self.selectedIndex = selectedIndex
    }

    /// Drop paths the `reachable` predicate rejects (e.g. moved/deleted since
    /// the session was saved), re-clamping `selectedIndex` to the filtered
    /// list. `reachable` is injected so this stays pure — no FileManager/URL
    /// dependency inside MarkViewCore (mirrors the RecentFilesManager
    /// `checkResourceIsReachable()` pattern at the call site).
    public func pruningUnreachable(reachable: (String) -> Bool) -> TabSessionState {
        var keptPaths: [String] = []
        var newSelectedIndex: Int?
        for (i, path) in openPaths.enumerated() {
            guard reachable(path) else { continue }
            if i == selectedIndex { newSelectedIndex = keptPaths.count }
            keptPaths.append(path)
        }
        return TabSessionState(openPaths: keptPaths, selectedIndex: newSelectedIndex)
    }
}
