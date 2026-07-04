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

    /// Cycling direction resolved from a keyDown chord.
    public enum CycleAction: Equatable {
        case next
        case previous
    }

    /// Routing predicate for the app-startup local NSEvent monitor (MV-009).
    ///
    /// Tab's keyCode is 48 (kVK_Tab). Returns `.next` for ⌃Tab, `.previous` for
    /// ⌃⇧Tab, and nil for everything else — nil MUST make the monitor pass the
    /// event through unmodified (plain Tab / ⇧Tab are focus navigation, not ours).
    /// Kept in Core so the routing decision is behaviorally testable; the monitor
    /// closure in TabManager.installTabCycleMonitor() is a thin shim over this.
    public static func action(forKeyCode keyCode: Int, control: Bool, shift: Bool) -> CycleAction? {
        guard keyCode == 48, control else { return nil }
        return shift ? .previous : .next
    }
}
