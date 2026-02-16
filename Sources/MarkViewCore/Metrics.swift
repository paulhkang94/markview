import Foundation

/// Local-first, opt-in usage metrics.
/// All data stays on disk at ~/Library/Application Support/MarkView/metrics.json.
/// Never transmitted anywhere — purely for the user's own insight.
public final class MetricsCollector {
    public static let shared = MetricsCollector()

    private var isEnabled: Bool = false
    private var session: SessionMetrics
    private let storageURL: URL

    public struct SessionMetrics: Codable {
        var sessionStart: Date = Date()
        var filesOpened: Int = 0
        var totalRenders: Int = 0
        var totalRenderTimeMs: Double = 0
        var largestFileBytes: Int = 0
        var exportsHTML: Int = 0
        var exportsPDF: Int = 0
        var editorUsed: Bool = false
        var featuresUsed: Set<String> = []
    }

    public struct AggregateMetrics: Codable {
        public var totalSessions: Int = 0
        public var totalFilesOpened: Int = 0
        public var totalRenders: Int = 0
        public var avgRenderTimeMs: Double = 0
        public var largestFileEverBytes: Int = 0
        public var totalExportsHTML: Int = 0
        public var totalExportsPDF: Int = 0
        public var editorSessionCount: Int = 0
        public var firstUsed: Date?
        public var lastUsed: Date?
        public var featureUsageCounts: [String: Int] = [:]
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MarkView")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        storageURL = appDir.appendingPathComponent("metrics.json")
        session = SessionMetrics()
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    public func trackFileOpened(sizeBytes: Int) {
        guard isEnabled else { return }
        session.filesOpened += 1
        session.largestFileBytes = max(session.largestFileBytes, sizeBytes)
    }

    public func trackRender(durationMs: Double) {
        guard isEnabled else { return }
        session.totalRenders += 1
        session.totalRenderTimeMs += durationMs
    }

    public func trackExport(format: String) {
        guard isEnabled else { return }
        if format == "html" { session.exportsHTML += 1 }
        if format == "pdf" { session.exportsPDF += 1 }
    }

    public func trackFeature(_ name: String) {
        guard isEnabled else { return }
        session.featuresUsed.insert(name)
    }

    public func trackEditorUsed() {
        guard isEnabled else { return }
        session.editorUsed = true
    }

    /// Flush current session metrics to disk (call on app termination).
    public func flush() {
        guard isEnabled else { return }

        var aggregate = loadAggregate()
        aggregate.totalSessions += 1
        aggregate.totalFilesOpened += session.filesOpened
        aggregate.totalRenders += session.totalRenders
        aggregate.largestFileEverBytes = max(aggregate.largestFileEverBytes, session.largestFileBytes)
        aggregate.totalExportsHTML += session.exportsHTML
        aggregate.totalExportsPDF += session.exportsPDF
        if session.editorUsed { aggregate.editorSessionCount += 1 }
        if aggregate.firstUsed == nil { aggregate.firstUsed = session.sessionStart }
        aggregate.lastUsed = Date()

        // Update average render time
        if aggregate.totalRenders > 0 {
            let prevTotal = aggregate.avgRenderTimeMs * Double(aggregate.totalRenders - session.totalRenders)
            aggregate.avgRenderTimeMs = (prevTotal + session.totalRenderTimeMs) / Double(aggregate.totalRenders)
        }

        // Merge feature usage
        for feature in session.featuresUsed {
            aggregate.featureUsageCounts[feature, default: 0] += 1
        }

        saveAggregate(aggregate)
    }

    /// Load aggregate metrics for display in a "Your Stats" view.
    public func loadAggregate() -> AggregateMetrics {
        guard let data = try? Data(contentsOf: storageURL),
              let metrics = try? JSONDecoder().decode(AggregateMetrics.self, from: data) else {
            return AggregateMetrics()
        }
        return metrics
    }

    private func saveAggregate(_ metrics: AggregateMetrics) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(metrics) else { return }
        try? data.write(to: storageURL)
    }

    /// Clear all stored metrics.
    public func clearAll() {
        try? FileManager.default.removeItem(at: storageURL)
    }
}
