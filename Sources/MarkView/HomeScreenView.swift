import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The home screen shown when no file is loaded.
///
/// Two states:
///  - **Empty** (no recents): centered icon + prompt + "Open File..." button.
///  - **Recents** (has history): header bar, SwiftUI `List`, drop-hint footer.
///
/// The entire view is a drag target; a full-screen overlay appears when a
/// file is dragged over the window.
struct HomeScreenView: View {
    /// Called with the URL to open whenever the user picks or drops a file.
    let onFileSelected: (URL) -> Void

    @ObservedObject private var recents = RecentFilesManager.shared
    @State private var isDragTargeted = false
    @State private var isFileImporterPresented = false

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
        // .fileImporter is the SwiftUI-native file picker (avoids runModal on main thread)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: markdownContentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                onFileSelected(url)
            }
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
                .foregroundStyle(.secondary)

            Text(Strings.dropPrompt)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(Strings.dropSubprompt)
                .font(.body)
                .foregroundStyle(.secondary.opacity(0.7))

            Button(Strings.openFileButton) { isFileImporterPresented = true }
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
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(Strings.homeScreenTitle)
                    .font(.title3.weight(.semibold))
                Text(Strings.homeScreenSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(Strings.openFileButton) { isFileImporterPresented = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var sectionLabel: some View {
        Text(Strings.recentFilesHeader)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private var fileList: some View {
        // SwiftUI List provides:
        //  - Automatic accessibility (VoiceOver, keyboard navigation)
        //  - swipeActions for per-row delete
        //  - Correct macOS row separator and selection styling
        List {
            ForEach(recents.recentFileURLs, id: \.path) { url in
                RecentFileRow(url: url) {
                    onFileSelected(url)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        recents.removeFromRecents(url: url)
                    } label: {
                        Label(Strings.removeFromRecents, systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var dropFooter: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.down.to.line")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.4))
            Text(Strings.dropHint)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.4))
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
                    .foregroundStyle(.tint)
                Text(Strings.dragToOpen)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
    }
}

// MARK: - Recent File Row

private struct RecentFileRow: View {
    let url: URL
    let onOpen: () -> Void

    @State private var isHovered = false
    /// Cached modification date — loaded once in onAppear to avoid repeated disk I/O.
    @State private var modDate: Date?

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 18))
                    .foregroundStyle(.tint)
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(abbreviatedDirectory(for: url))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let date = modDate {
                    Text(RelativeDateTimeFormatter.shared.localizedString(for: date, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            // Use URL-based resource value lookup (Apple-recommended over path-based APIs)
            modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        }
        .contextMenu {
            Button(Strings.contextMenuOpen) { onOpen() }
            Divider()
            Button(Strings.showInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Divider()
            Button(Strings.removeFromRecents, role: .destructive) {
                RecentFilesManager.shared.removeFromRecents(url: url)
            }
        }
        // HIG: accessibilityLabel = what it is; accessibilityHint = imperative action verb
        .accessibilityLabel("\(url.lastPathComponent), \(abbreviatedDirectory(for: url))")
        .accessibilityHint("Opens this file in the viewer")
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
}

// MARK: - Module-level helpers

/// UTTypes for all Markdown-like file extensions MarkView accepts.
/// Computed once; avoids repeated dynamic UTType construction per open call.
private let markdownContentTypes: [UTType] = {
    var types: [UTType] = [.plainText]
    for ext in ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"] {
        if let t = UTType(filenameExtension: ext) { types.append(t) }
    }
    return types
}()

private func isMarkdownURL(_ url: URL) -> Bool {
    ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "txt"]
        .contains(url.pathExtension.lowercased())
}

// MARK: - RelativeDateTimeFormatter singleton

private extension RelativeDateTimeFormatter {
    /// Shared formatter — `RelativeDateTimeFormatter` is expensive to create; reuse it.
    /// nonisolated(unsafe): RelativeDateTimeFormatter is a non-Sendable NSObject subclass.
    /// Safe here because the formatter is only configured at initialization and treated as read-only.
    nonisolated(unsafe) static let shared: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated   // "2h ago", "3d ago"
        f.dateTimeStyle = .named      // "yesterday" instead of "1 day ago"
        return f
    }()
}
