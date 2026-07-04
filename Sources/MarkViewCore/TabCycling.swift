import Foundation

/// Pure index math for tab cycling (⌃Tab / ⌘⇧] → next, ⌃⇧Tab / ⌘⇧[ → previous).
///
/// Lives in MarkViewCore so MarkViewTestRunner can cover cycling order and
/// wraparound behaviorally — TabManager itself is @MainActor in the app target
/// and cannot be imported by the SPM test runner.
public enum TabCycling {
    /// Index of the next tab in cycling order, wrapping last → first.
    /// `index` must be a valid position in `0..<count`; `count <= 0` returns 0
    /// as a safe no-op index (callers guard emptiness before subscripting).
    public static func nextIndex(after index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + 1) % count
    }

    /// Index of the previous tab in cycling order, wrapping first → last.
    /// Same preconditions as `nextIndex(after:count:)`.
    public static func previousIndex(before index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + count - 1) % count
    }
}
