import AppKit
import SwiftUI

/// The home screen shown when no file is loaded.
///
/// Two states:
///  - **Empty** (no recents): centered icon + prompt + "Open File..." button.
///  - **Recents** (has history): header bar, MRU file list, drop-hint footer.
///
/// The entire view is a drag target; a full-screen overlay appears when a
/// file is dragged over the window.
struct HomeScreenView: View {
    /// Called with the URL to open whenever the user picks or drops a file.
    let onFileSelected: (URL) -> Void

    @ObservedObject private var recents = RecentFilesManager.shared
    @State private var isDragTargeted = false

    var body: some View {
        ZStack {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isDragTargeted {
                dragOverlay
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.12), value: isDragTargeted)
            }
        }
        .onAppear { recents.refresh() }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url, isMarkdownURL(url) else { return }
                DispatchQueue.main.async { onFileSelected(url) }
            }
            return true
        }
        .accessibilityLabel(Strings.dropA11yLabel)
        .accessibilityHint(Strings.dropA11yHint)
    }

    // MARK: - State switching

    @ViewBuilder
    private var mainContent: some View {
        if recents.recentFileURLs.isEmpty {
            emptyStateView
        } else {
            recentsView
        }
    }

    // MARK: - Empty state (first launch / cleared recents)

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text(Strings.dropPrompt)
                .font(.title2)
                .foregroundColor(.secondary)

            Text(Strings.dropSubprompt)
                .font(.body)
                .foregroundColor(.secondary.opacity(0.7))

            Button(Strings.openFileButton) { openFilePicker() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Recents view

    private var recentsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            sectionLabel
            fileList
            dropFooter
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(Strings.homeScreenTitle)
                    .font(.title3.weight(.semibold))
                Text(Strings.homeScreenSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(Strings.openFileButton) { openFilePicker() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var sectionLabel: some View {
        Text(Strings.recentFilesHeader)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private var fileList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(recents.recentFileURLs.enumerated()), id: \.element.path) { idx, url in
                    RecentFileRow(url: url) {
                        onFileSelected(url)
                    } onRemove: {
                        recents.removeFromRecents(url: url)
                    }
                    // Divider only between rows, not after the last one
                    if idx < recents.recentFileURLs.count - 1 {
                        Divider()
                            .padding(.leading, 28 + 24 + 10) // aligned past icon column
                    }
                }
            }
        }
    }

    private var dropFooter: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.down.to.line")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.4))
            Text(Strings.dropHint)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Drag overlay

    private var dragOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.07)

            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 2.5)
                .padding(3)

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
                Text(Strings.dragToOpen)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
        }
    }

    // MARK: - File picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "markdown")!,
            .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            onFileSelected(url)
        }
    }
}

// MARK: - Recent File Row

private struct RecentFileRow: View {
    let url: URL
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    /// Cached modification date — loaded once in onAppear to avoid repeated disk I/O on render.
    @State private var modDate: Date?

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                // File-type icon
                Image(systemName: "doc.text")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, alignment: .center)

                // Filename + directory
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(abbreviatedDirectory(for: url))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Relative modification date
                if let date = modDate {
                    Text(relativeDate(from: date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(
                isHovered
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onAppear {
            modDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        }
        .contextMenu {
            Button(Strings.contextMenuOpen) { onOpen() }
            Divider()
            Button(Strings.showInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Divider()
            Button(Strings.removeFromRecents) { onRemove() }
        }
        .accessibilityLabel("\(url.lastPathComponent), \(abbreviatedDirectory(for: url))")
        .accessibilityHint("Double-click or press Space to open")
    }

    // MARK: - Helpers

    private func abbreviatedDirectory(for url: URL) -> String {
        let dir = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.hasPrefix(home) {
            let suffix = dir.dropFirst(home.count)
            return suffix.isEmpty ? "~" : "~\(suffix)"
        }
        return dir
    }

    private func relativeDate(from date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "Now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        formatter.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Helpers

private func isMarkdownURL(_ url: URL) -> Bool {
    ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "txt"]
        .contains(url.pathExtension.lowercased())
}
