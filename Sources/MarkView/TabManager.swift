import Foundation
import SwiftUI

/// One open file tab. Owns its own PreviewViewModel (and therefore its own
/// FileWatcher) so each tab's live-reload, lint, and render state are isolated.
@MainActor
final class TabState: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let viewModel: PreviewViewModel

    var displayName: String { url.lastPathComponent }

    init(url: URL) {
        self.url = url
        self.viewModel = PreviewViewModel()
        self.viewModel.loadFile(at: url.path)
    }
}

/// Owns the ordered collection of open tabs.
/// Every file-open path (AppDelegate, ⌘O panel, CLI args, MCP open_file, auto-reopen)
/// routes through `openFile(_:)` so deduplication and selection stay consistent.
@MainActor
final class TabManager: ObservableObject {
    @Published var tabs: [TabState] = []
    @Published var selectedTabID: UUID?

    var selectedTab: TabState? {
        tabs.first { $0.id == selectedTabID }
    }

    /// Open a file. If already open, switch to it; otherwise create a new tab.
    func openFile(_ url: URL) {
        let resolved = url.resolvingSymlinksInPath()
        if let existing = tabs.first(where: { $0.url.resolvingSymlinksInPath() == resolved }) {
            selectedTabID = existing.id
            return
        }
        let tab = TabState(url: resolved)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    /// Close a tab. Selects the nearest remaining tab; returns to home if none left.
    func closeTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].viewModel.unloadFile()
        tabs.remove(at: idx)
        if selectedTabID == id {
            selectedTabID = tabs.isEmpty ? nil : tabs[min(idx, tabs.count - 1)].id
        }
    }

    func selectNext() {
        guard let cur = selectedTabID, let idx = tabs.firstIndex(where: { $0.id == cur }), tabs.count > 1 else { return }
        selectedTabID = tabs[(idx + 1) % tabs.count].id
    }

    func selectPrevious() {
        guard let cur = selectedTabID, let idx = tabs.firstIndex(where: { $0.id == cur }), tabs.count > 1 else { return }
        selectedTabID = tabs[(idx + tabs.count - 1) % tabs.count].id
    }
}
