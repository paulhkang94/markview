import os
import Sentry
import MarkViewAppCore

/// Centralized structured logging for MarkView.
/// Uses os.Logger (macOS 14+) with Sentry breadcrumb integration.
enum AppLogger {
    private static let subsystem = "dev.paulkang.MarkView"

    static let file = Logger(subsystem: subsystem, category: "file")
    static let render = Logger(subsystem: subsystem, category: "render")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let general = Logger(subsystem: subsystem, category: "general")

    fileprivate static func logger(for category: String) -> Logger {
        switch category {
        case "file": return file
        case "render": return render
        case "sync": return sync
        case "export": return export
        default: return general
        }
    }

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

/// Bridges MarkViewAppCore's Sentry-free `AppCoreLogging` seam to the real
/// AppLogger/Sentry pipeline (mar-033 Tier-B, mar-038). Installed once at
/// startup — `AppCoreLog.logger = SentryAppCoreLogger()` in MarkViewApp.init —
/// before any moved type (PreviewViewModel) can log anything.
///
/// Every moved call site paired an `AppLogger.<category>.error(message)` os_log
/// call with a separate `AppLogger.captureError(error, category:, message:)`
/// Sentry call. To keep production logging byte-for-byte unchanged, this bridge
/// preserves that same split instead of merging them: `logWarning` is exactly
/// the old os_log call, `logError` is exactly the old captureError call.
struct SentryAppCoreLogger: AppCoreLogging {
    func logError(_ error: Error, category: String, message: String) {
        AppLogger.captureError(error, category: category, message: message)
    }

    func logWarning(_ message: String, category: String) {
        AppLogger.logger(for: category).error("\(message)")
    }
}
