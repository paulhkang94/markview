import os
import Sentry

/// Centralized structured logging for MarkView.
/// Uses os.Logger (macOS 14+) with Sentry breadcrumb integration.
enum AppLogger {
    private static let subsystem = "dev.paulkang.MarkView"

    static let file = Logger(subsystem: subsystem, category: "file")
    static let render = Logger(subsystem: subsystem, category: "render")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let general = Logger(subsystem: subsystem, category: "general")

    /// Log an error and capture it in Sentry with context.
    static func captureError(_ error: Error, category: String, message: String) {
        let breadcrumb = Breadcrumb(level: .error, category: category)
        breadcrumb.message = message
        SentrySDK.addBreadcrumb(breadcrumb)
        SentrySDK.capture(error: error)
    }

    /// Add a Sentry breadcrumb without capturing an event.
    static func breadcrumb(_ message: String, category: String, level: SentryLevel = .info) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }
}
