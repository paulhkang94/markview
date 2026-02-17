import SwiftUI

/// Non-modal notification banner that slides down from top of window.
/// Auto-dismisses after 5s or can be manually dismissed.
struct ErrorBanner: View {
    let notification: ErrorNotification
    let onDismiss: () -> Void
    let onReport: ((URL) -> Void)?

    private var backgroundColor: Color {
        switch notification.level {
        case .error: return Color.red.opacity(0.9)
        case .warning: return Color.orange.opacity(0.9)
        case .info: return Color.blue.opacity(0.9)
        }
    }

    private var iconName: String {
        switch notification.level {
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                if let detail = notification.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                }
            }

            Spacer()

            if notification.level == .error, let onReport = onReport {
                Button("Report") {
                    // Build URL from ErrorPresenter
                    let presenter = ErrorPresenter()
                    if let url = presenter.reportURL(for: notification) {
                        onReport(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.white)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
