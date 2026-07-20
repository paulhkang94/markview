import Foundation

/// Structured error/warning reporting seam for MarkViewAppCore types.
///
/// MarkViewAppCore must never link Sentry directly (mar-033 phase-1 precedent:
/// JSBundleCache reports structured `LoadFailure`s instead of logging). Types
/// moved from the app target in the mar-033 Tier-B pass (PreviewViewModel, and
/// any future addition) previously called `AppLogger`/`SentrySDK` inline —
/// this protocol replaces those call sites with an injected seam so the
/// library stays Sentry-free while production behavior (capture + breadcrumb)
/// is unchanged: the app target installs a bridge (`AppCoreLog.logger = ...`)
/// once at startup, before any moved type can log anything.
///
/// Defaults to a no-op so MarkViewTestRunner (and any future test target)
/// needs zero configuration; tests that care can install a spy.
public protocol AppCoreLogging: Sendable {
    func logError(_ error: Error, category: String, message: String)
    func logWarning(_ message: String, category: String)
}

public struct NoopAppCoreLogger: AppCoreLogging {
    public init() {}
    public func logError(_ error: Error, category: String, message: String) {}
    public func logWarning(_ message: String, category: String) {}
}

/// Process-wide logger seam, mirroring the `.shared` singleton idiom already
/// used throughout this library (JSBundleCache.shared, and the app target's
/// RecentFilesManager.shared / AppSettings.shared). Mutable (unlike those
/// `let shared`s) because the real implementation lives in the app target and
/// must be injected after the library is loaded — see `SentryAppCoreLogger`
/// in Sources/MarkView/AppLogger.swift and its installation in MarkViewApp.init.
@MainActor
public enum AppCoreLog {
    public static var logger: AppCoreLogging = NoopAppCoreLogger()
}
