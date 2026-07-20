import Foundation
import MarkViewCore

/// Moved from the Xcode app target to MarkViewAppCore (mar-033 Tier-B, mar-038).
///
/// Persists the ordered list of currently-open tabs (MV-001 fix).
///
/// Before this existed, the only thing persisted across quit/relaunch was
/// `RecentFilesManager.lastOpenedFilePath` — a single string, overwritten on
/// every tab open — so relaunch could reopen at most one tab no matter how
/// many were open at quit. This stores the full ordered `TabSessionState`
/// (see MarkViewCore/TabSession.swift) as JSON under one UserDefaults key,
/// matching RecentFilesManager's existing storage convention (no new sidecar
/// file — the SSOT explicitly rejects per-file sidecars for a Viewer-role
/// app handling other people's files).
@MainActor
public enum TabSessionStore {
    public static let sessionKey = "openTabSession"

    /// Write-through save, called from `TabManager.persistSession()` on every
    /// tabs/selectedTabID change. Not debounced — see TabManager for why a
    /// synchronous write is fine at this change frequency.
    public static func save(openPaths: [String], selectedIndex: Int?) {
        let state = TabSessionState(openPaths: openPaths, selectedIndex: selectedIndex)
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: sessionKey)
    }

    /// Load the previous session, respecting the same `windowRestore` /
    /// `didExplicitlyCloseFile` guards as `RecentFilesManager.lastOpenedURL`,
    /// and pruning paths that no longer exist on disk. Returns nil when there
    /// is nothing to restore (restore disabled, user explicitly closed
    /// everything last session, no session ever recorded, or every recorded
    /// path is now unreachable).
    public static func loadSession() -> TabSessionState? {
        let windowRestore: Bool
        if UserDefaults.standard.object(forKey: "windowRestore") != nil {
            windowRestore = UserDefaults.standard.bool(forKey: "windowRestore")
        } else {
            windowRestore = true
        }
        guard windowRestore else { return nil }
        guard !UserDefaults.standard.bool(forKey: "didExplicitlyCloseFile") else { return nil }
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let state = try? JSONDecoder().decode(TabSessionState.self, from: data) else {
            return nil
        }
        let pruned = state.pruningUnreachable { path in
            (try? URL(fileURLWithPath: path).checkResourceIsReachable()) == true
        }
        return pruned.openPaths.isEmpty ? nil : pruned
    }
}
