import Combine
import Foundation
import MarkViewCore

/// Owns the off-main document-stats computation for the status bar.
///
/// Extracted from `StatusBarView` (item-713 second hang class, #57 / mar-033):
/// the view previously recomputed word/char/line counts with full-document
/// scans on EVERY SwiftUI body evaluation, on the main thread (Sentry
/// APPLE-MACOS-34/-37). The fix — one `DocumentStats.compute` pass on a
/// detached utility task, published back on the main actor — lived inline in
/// the view's `.task(id:)` where only source inspection could cover it. As a
/// model it is behaviorally testable from MarkViewTestRunner.
///
/// `compute` is injectable so tests can probe which thread the scan runs on;
/// production uses `DocumentStats.compute` unchanged.
@MainActor
public final class StatusBarStatsModel: ObservableObject {

    @Published public private(set) var stats: DocumentStats = .zero

    private let compute: @Sendable (String) -> DocumentStats

    public init(compute: @escaping @Sendable (String) -> DocumentStats = { DocumentStats.compute(from: $0) }) {
        self.compute = compute
    }

    /// Recompute stats for `content` off the main thread, then publish the
    /// result on the main actor. Drive this from `.task(id: content)` so a
    /// content change cancels the in-flight pass and starts a fresh one.
    public func update(for content: String) async {
        let compute = self.compute
        let computed = await Task.detached(priority: .utility) {
            compute(content)
        }.value
        stats = computed
    }
}
