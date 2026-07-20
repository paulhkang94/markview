import Foundation
import Observation

/// Moved from the Xcode app target to MarkViewAppCore (mar-033 Tier-B, mar-038).
///
/// Severity levels for user-facing error notifications.
public enum ErrorLevel {
    case info
    case warning
    case error
}

/// A single error notification to display in the banner.
public struct ErrorNotification: Identifiable {
    public let id = UUID()
    public let level: ErrorLevel
    public let message: String
    public let detail: String?
    public let timestamp = Date()

    public init(level: ErrorLevel, message: String, detail: String? = nil) {
        self.level = level
        self.message = message
        self.detail = detail
    }
}

/// Observable state for presenting error banners in the UI.
/// Injected into the environment at ContentView level.
@MainActor
@Observable
public final class ErrorPresenter {
    public var currentNotification: ErrorNotification?
    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ message: String, level: ErrorLevel = .error, detail: String? = nil) {
        dismissTask?.cancel()
        currentNotification = ErrorNotification(level: level, message: message, detail: detail)

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s auto-dismiss
            guard !Task.isCancelled else { return }
            currentNotification = nil
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        currentNotification = nil
    }

    /// Build a pre-filled GitHub Issue URL for error reporting.
    public func reportURL(for notification: ErrorNotification) -> URL? {
        var components = URLComponents(string: "https://github.com/paulhkang94/markview/issues/new")
        let body = """
        **Error:** \(notification.message)
        \(notification.detail.map { "**Detail:** \($0)\n" } ?? "")
        **App Version:** \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        **macOS:** \(ProcessInfo.processInfo.operatingSystemVersionString)
        **Time:** \(notification.timestamp)
        """
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Error: \(notification.message)"),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: "bug"),
        ]
        return components?.url
    }
}
