import Foundation

/// Pure helper for mapping a selected tab's index in the FULL `tabs` array to
/// its index in the persistence-FILTERED array (untitled/no-URL tabs excluded).
///
/// MV-007 makes a tab's URL Optional: an untitled scratch tab has no file on
/// disk. `TabManager.persistSession()` therefore persists only the tabs that
/// HAVE a URL (`tabs.compactMap { $0.url?.path }`), so the persisted
/// `openPaths` array is a filtered subset of `tabs` with a DIFFERENT index
/// space. The selected index stored alongside it must be recomputed against
/// that filtered array — not the raw `tabs` index — otherwise, whenever an
/// untitled tab sits before the selected one, session restore reselects the
/// wrong tab.
///
/// This is the single highest-risk correctness point in MV-007 (it silently
/// corrupts MV-001's session restore if wrong) and the one piece genuinely
/// unit-testable in isolation — `TabManager` is app-target and not
/// SPM-importable — so it is extracted here and covered behaviorally in
/// MarkViewTestRunner.
public enum TabSelection {
    /// Map a raw selected index (into the full tab list) to its index within the
    /// URL-only filtered list that gets persisted.
    ///
    /// - Parameters:
    ///   - hasURL: one Bool per tab, in tab-bar order; `true` = the tab has a
    ///     file URL and is included in persistence, `false` = untitled/excluded.
    ///   - selectedRawIndex: index of the selected tab in the FULL tab list, or
    ///     nil if nothing is selected.
    /// - Returns: the selected tab's index within the filtered (URL-only) list,
    ///   or nil when there is nothing meaningful to persist for the selection —
    ///   i.e. no selection, an out-of-range index, or the selected tab itself is
    ///   untitled (has no URL).
    public static func filteredIndex(hasURL: [Bool], selectedRawIndex: Int?) -> Int? {
        guard let raw = selectedRawIndex, raw >= 0, raw < hasURL.count else { return nil }
        // The selected tab itself is untitled — it is not persisted, so there is
        // no meaningful position for it in the filtered list.
        guard hasURL[raw] else { return nil }
        // Position within the filtered list = number of URL-bearing tabs before it.
        return hasURL[0..<raw].lazy.filter { $0 }.count
    }
}
