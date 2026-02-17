import SwiftUI

/// Severity levels for user-facing error notifications.
enum ErrorLevel {
    case info
    case warning
    case error
}

/// A single error notification to display in the banner.
struct ErrorNotification: Identifiable {
    let id = UUID()
    let level: ErrorLevel
    let message: String
    let detail: String?
    let timestamp = Date()

    init(level: ErrorLevel, message: String, detail: String? = nil) {
        self.level = level
        self.message = message
        self.detail = detail
    }
}

/// Observable state for presenting error banners in the UI.
/// Injected into the environment at ContentView level.
@MainActor
@Observable
final class ErrorPresenter {
    var currentNotification: ErrorNotification?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, level: ErrorLevel = .error, detail: String? = nil) {
        dismissTask?.cancel()
        currentNotification = ErrorNotification(level: level, message: message, detail: detail)

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s auto-dismiss
            guard !Task.isCancelled else { return }
            currentNotification = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        currentNotification = nil
    }

    /// Build a pre-filled GitHub Issue URL for error reporting.
    func reportURL(for notification: ErrorNotification) -> URL? {
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
