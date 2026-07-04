import AppKit
import Foundation
import MarkViewCore
import SwiftUI

/// One open file tab. Owns its own PreviewViewModel (and therefore its own
/// FileWatcher) so each tab's live-reload, lint, and render state are isolated.
@MainActor
final class TabState: ObservableObject, Identifiable {
    let id = UUID()

    /// The file this tab shows, or nil for an untitled scratch tab (MV-007) with
    /// no file on disk yet. Transitions from nil to a real value exactly once, on
    /// the first successful save (TabManager.promoteUntitledTab). @Published so the
    /// tab bar re-derives displayName the moment an untitled tab is promoted.
    @Published var url: URL?

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

    /// Fixed display name for an untitled (nil-url) tab, chosen once at CREATION in
    /// TabManager.newUntitledTab() so the number ("Untitled", "Untitled 2", …) does
    /// not shift when other tabs close (MV-007). Nil for a real-file tab, whose
    /// displayName derives from `url`.
    let untitledName: String?

    var displayName: String {
        guard let url else { return untitledName ?? "Untitled" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    init(url: URL) {
        self.url = url
        self.untitledName = nil
        self.viewModel = PreviewViewModel()
        self.viewModel.loadFile(at: url.path)
    }

    /// Untitled scratch tab (MV-007): no file on disk. Skips loadFile — there is
    /// no path to load — and instead puts the viewModel in an empty-but-loaded
    /// state. No recents entry, file watcher, or auto-save timer starts until the
    /// first save promotes the tab to a real file.
    init(untitledName: String) {
        self.url = nil
        self.untitledName = untitledName
        self.viewModel = PreviewViewModel()
        self.viewModel.startUntitled()
    }
}

/// Owns the ordered collection of open tabs.
/// Every file-open path (AppDelegate, ⌘O panel, CLI args, MCP open_file, auto-reopen)
/// routes through `openFile(_:)` so deduplication and selection stay consistent.
@MainActor
final class TabManager: ObservableObject {
    // Write-through session persistence (MV-001): every add/remove/selection
    // change re-derives and saves the full ordered tab list, so relaunch can
    // reopen ALL of them — not just the single "last opened file" path that
    // RecentFilesManager tracked before this. Same continuous-capture idiom
    // as MV-003's scrollLine write-through; tab-list changes are rare enough
    // (open/close/switch) that a synchronous UserDefaults write per change is
    // cheap, unlike the higher-frequency per-scroll-frame case.
    @Published var tabs: [TabState] = [] {
        didSet { persistSession() }
    }
    @Published var selectedTabID: UUID? {
        didSet { persistSession() }
    }

    var selectedTab: TabState? {
        tabs.first { $0.id == selectedTabID }
    }

    /// Open a file. If already open, switch to it; otherwise create a new tab.
    func openFile(_ url: URL) {
        let resolved = url.resolvingSymlinksInPath()
        // Optional-chained so untitled (nil-url) tabs are silently skipped rather
        // than force-unwrapped — dedup is meaningless for a tab with no file (MV-007).
        if let existing = tabs.first(where: { $0.url?.resolvingSymlinksInPath() == resolved }) {
            selectedTabID = existing.id
            return
        }
        let tab = TabState(url: resolved)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    /// Open a fresh untitled scratch tab (⌘T, MV-007). It has no file on disk and
    /// is excluded from session persistence. Deliberately bypasses openFile(_:) —
    /// dedup is meaningless for a tab with no URL — and forces the editor pane on,
    /// since a preview with no file loaded is useless. The "Untitled" number is
    /// fixed here at creation so it does not shift when other tabs close.
    func newUntitledTab() {
        let existingUntitled = tabs.filter { $0.url == nil }.count
        let name = existingUntitled == 0 ? "Untitled" : "Untitled \(existingUntitled + 1)"
        let tab = TabState(untitledName: name)
        tab.showEditor = true
        tabs.append(tab)
        selectedTabID = tab.id
    }

    /// Promote an untitled scratch tab into a real file tab after the user picks a
    /// save location (⌘S on an untitled tab, MV-007). Writes the current editor
    /// buffer to `url`, then routes through the tab's existing loadFile(at:) — the
    /// SINGLE untitled→file transition path — so recents, the file watcher, and the
    /// auto-save timer all start correctly with zero duplicated side effects to keep
    /// in sync. Setting `url` (which is @Published) refreshes the tab bar title.
    func promoteUntitledTab(_ tab: TabState, to url: URL) throws {
        let resolved = url.resolvingSymlinksInPath()
        try tab.viewModel.editorContent.write(to: resolved, atomically: true, encoding: .utf8)
        tab.url = resolved
        tab.viewModel.loadFile(at: resolved.path)
        // The tab now has a URL, so it belongs in the persisted session. `tabs`/
        // `selectedTabID` didn't change, so didSet won't fire — persist explicitly.
        persistSession()
    }

    /// Re-derive the ordered path list + selected index from live state and
    /// persist it. The single write path for MV-001 — called from `didSet` on
    /// both `tabs` and `selectedTabID`, never invoked ad hoc from call sites,
    /// so no mutation site can forget to persist.
    private func persistSession() {
        // compactMap (not map): untitled tabs have a nil url and are intentionally
        // EXCLUDED from persistence — a scratch tab with no file has nothing to
        // reopen at relaunch (MV-007). map { $0.url.path } would also crash once
        // url is Optional, so this is a hard regression guard, not a nice-to-have.
        let paths = tabs.compactMap { $0.url?.path }
        // The filtered `paths` array has a DIFFERENT index space than `tabs` once
        // any untitled tab is excluded, so recompute the selected index against the
        // filtered array (TabSelection is behaviorally tested in MarkViewCore).
        let hasURL = tabs.map { $0.url != nil }
        let rawSelectedIndex = selectedTabID.flatMap { id in tabs.firstIndex(where: { $0.id == id }) }
        let selectedIndex = TabSelection.filteredIndex(hasURL: hasURL, selectedRawIndex: rawSelectedIndex)
        TabSessionStore.save(openPaths: paths, selectedIndex: selectedIndex)
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
