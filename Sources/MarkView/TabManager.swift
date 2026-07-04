import AppKit
import Foundation
import MarkViewCore
import SwiftUI

/// One open file tab. Owns its own PreviewViewModel (and therefore its own
/// FileWatcher) so each tab's live-reload, lint, and render state are isolated.
@MainActor
final class TabState: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let viewModel: PreviewViewModel

    /// Last preview scroll position as a 1-based markdown source line (0 = top).
    /// Written through continuously from ScrollSyncController.onLineChange and read
    /// to seed the recreated ActiveTabView on tab reselect (MV-003). Deliberately
    /// NOT @Published — it changes on every scroll frame and must not invalidate
    /// the tab bar or any observing view.
    var scrollLine: Int = 0

    /// Editor pane visibility for this tab (MV-003). Not @Published — ActiveTabView
    /// copies it into local @State at creation and writes back on toggle.
    var showEditor: Bool = false

    var displayName: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

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
        // Suppress relaunch auto-reopen only when the user closed the LAST tab —
        // firing on every close (the old unloadFile behavior) poisoned session
        // restore while other tabs were still open (MV-001).
        if tabs.isEmpty {
            RecentFilesManager.shared.markExplicitlyClosed()
        }
    }

    // Wrap math lives in MarkViewCore.TabCycling so MarkViewTestRunner can cover
    // cycling order + wraparound behaviorally (this class is not SPM-importable).
    func selectNext() {
        guard let cur = selectedTabID, let idx = tabs.firstIndex(where: { $0.id == cur }), tabs.count > 1 else { return }
        selectedTabID = tabs[TabCycling.nextIndex(after: idx, count: tabs.count)].id
    }

    func selectPrevious() {
        guard let cur = selectedTabID, let idx = tabs.firstIndex(where: { $0.id == cur }), tabs.count > 1 else { return }
        selectedTabID = tabs[TabCycling.previousIndex(before: idx, count: tabs.count)].id
    }

    // MARK: - ⌃Tab / ⌃⇧Tab cycling (MV-009)

    /// Local-monitor token. App-lifetime — no teardown path needed; stored so the
    /// install is provably idempotent.
    private var tabCycleMonitor: Any?

    /// Install the ⌃Tab / ⌃⇧Tab tab-cycling shortcuts. Called once at startup
    /// (MarkViewApp onAppear); idempotent.
    ///
    /// NV-2 ANSWERED (in-app, 2026-07-03): SwiftUI `.keyboardShortcut(.tab,
    /// modifiers: .control)` menu equivalents NEVER fire while the WKWebView has
    /// focus — WebKit consumes Tab as sequential element-focus navigation during
    /// the window's performKeyEquivalent pass, which runs BEFORE the main menu is
    /// consulted. An AppKit NSMenuItem with keyEquivalent "\t" loses the same
    /// race. A local NSEvent monitor receives events before NSApplication
    /// dispatches them to ANY responder (WKWebView included), so it is the one
    /// mechanism that works for Tab-key shortcuts specifically. All non-Tab
    /// shortcuts stay on main-menu key equivalents (the sanctioned mechanism).
    func installTabCycleMonitor() {
        guard tabCycleMonitor == nil else { return }
        tabCycleMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags
            guard let action = TabCycling.action(
                forKeyCode: Int(event.keyCode),
                control: flags.contains(.control),
                shift: flags.contains(.shift)
            ) else { return event }
            // No tabs (home screen): not our event — let focus navigation proceed.
            guard let self, !self.tabs.isEmpty else { return event }
            switch action {
            case .next: self.selectNext()
            case .previous: self.selectPrevious()
            }
            // Swallow the event — WKWebView must never also run Tab focus navigation.
            return nil
        }
    }
}
