import SwiftUI
import MarkViewCore
import MarkViewAppCore
import WebKit

/// Reference-type wrapper so the NSEvent monitor can be stored in a @State.
/// Swift structs can't mutate stored var properties from closure captures,
/// but a class-based holder works cleanly as a @State reference.
private final class EscMonitorHolder {
    var monitor: Any?
}

/// Outer shell: renders the always-visible tab bar and switches between
/// the active tab's content view and the home screen.
struct ContentView: View {
    @ObservedObject var tabManager: TabManager
    var errorPresenter: ErrorPresenter

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(tabManager: tabManager)

            if let tab = tabManager.selectedTab {
                // .id(tab.id) forces SwiftUI to create a fresh ActiveTabView on tab switch,
                // giving each tab isolated @StateObjects (findBar, syncController, etc.).
                // State that must survive the switch lives in TabState (MV-003) and is
                // seeded back in by ActiveTabView.init.
                ActiveTabView(
                    tab: tab,
                    tabManager: tabManager,
                    errorPresenter: errorPresenter
                )
                .id(tab.id)
            } else {
                HomeScreenView { url in
                    tabManager.openFile(url)
                }
            }
        }
    }
}

/// Per-tab content view. @ObservedObject on the specific tab's PreviewViewModel
/// so SwiftUI re-renders when that viewModel's @Published properties change.
/// Recreated on tab switch (via .id()) — per-tab UI state (@StateObjects) is isolated.
private struct ActiveTabView: View {
    let tab: TabState
    @ObservedObject var viewModel: PreviewViewModel
    @ObservedObject var tabManager: TabManager
    var errorPresenter: ErrorPresenter

    @StateObject private var findBar = FindBarController()
    @ObservedObject private var settings = AppSettings.shared
    @State private var syncController: ScrollSyncController
    @State private var showEditor: Bool
    @State private var showExternalChangeAlert = false
    @State private var escMonitorHolder = EscMonitorHolder()

    /// Seeds per-tab UI state from TabState (MV-003): `.id(tab.id)` destroys this
    /// view's @State on every tab switch, so anything that must survive the switch
    /// lives in TabState — copied in here at creation and written back on change
    /// (scroll line: continuously via onLineChange; pane mode: on toggle).
    /// The seeded lastPreviewLine is what handleRenderComplete restores after the
    /// recreated WKWebView finishes rendering (MV-002), so a reselected tab returns
    /// to its saved position instead of the top. A brand-new tab seeds 0, and the
    /// `line > 0` guard in handleRenderComplete keeps fresh loads at the top.
    @MainActor
    init(tab: TabState, tabManager: TabManager, errorPresenter: ErrorPresenter) {
        self.tab = tab
        self.viewModel = tab.viewModel
        self.tabManager = tabManager
        self.errorPresenter = errorPresenter
        let controller = ScrollSyncController()
        // Seed BEFORE installing the write-through so seeding is not echoed back.
        controller.lastPreviewLine = tab.scrollLine
        controller.onLineChange = { [weak tab] line in tab?.scrollLine = line }
        _syncController = State(initialValue: controller)
        _showEditor = State(initialValue: tab.showEditor)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if viewModel.isLoaded {
                    if showEditor {
                        HSplitView {
                            EditorView(
                                text: $viewModel.editorContent,
                                onChange: { viewModel.contentDidChange($0) },
                                syncController: syncController
                            )
                            .frame(minWidth: 200, idealWidth: .infinity, maxWidth: .infinity)
                            .accessibilityElement(children: .contain)

                            WebPreviewView(
                                html: viewModel.renderedHTML,
                                baseDirectoryURL: viewModel.currentFileDirectoryURL,
                                fileIdentifier: viewModel.currentFilePath,
                                previewFontSize: settings.previewFontSize,
                                previewWidth: settings.previewWidth.cssValue,
                                theme: settings.theme,
                                syncController: syncController,
                                findBar: findBar,
                                onWebViewCreated: { viewModel.previewWebView = $0 }
                            )
                            .id(tab.id)
                            .frame(minWidth: 200, idealWidth: .infinity, maxWidth: .infinity)
                            .accessibilityElement(children: .contain)
                        }
                    } else {
                        WebPreviewView(
                            html: viewModel.renderedHTML,
                            baseDirectoryURL: viewModel.currentFileDirectoryURL,
                            fileIdentifier: viewModel.currentFilePath,
                            previewFontSize: settings.previewFontSize,
                            previewWidth: settings.previewWidth.cssValue,
                            theme: settings.theme,
                            syncController: syncController,
                            findBar: findBar,
                            onWebViewCreated: { viewModel.previewWebView = $0 }
                        )
                        .id(tab.id)
                    }
                } else {
                    HomeScreenView { url in
                        viewModel.loadFile(at: url.path)
                        registerFileInWindow(url.path)
                    }
                }

                if viewModel.isLoaded {
                    StatusBarView(
                        content: viewModel.editorContent,
                        filePath: viewModel.currentFilePath,
                        isDirty: viewModel.isDirty,
                        lintWarnings: viewModel.lintWarnings,
                        lintErrors: viewModel.lintErrors,
                        lintDiagnostics: viewModel.lintDiagnostics,
                        onFixAll: { viewModel.autoFixLint() }
                    )
                }
            }
            .overlay(alignment: .bottom) {
                if findBar.isVisible {
                    FindBarView(findBar: findBar)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: findBar.isVisible)
            .onChange(of: findBar.isVisible) { visible in
                if visible { installEscMonitor() } else { removeEscMonitor() }
            }
            .navigationTitle(viewModel.fileName)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if viewModel.isLoaded {
                        Button {
                            closeCurrentTab()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .help(Strings.closeFile)

                        Button {
                            toggleEditor()
                        } label: {
                            Image(systemName: showEditor ? "doc.plaintext" : "rectangle.split.2x1")
                        }
                        .help(showEditor ? Strings.hideEditor : Strings.showEditor)
                        .accessibilityLabel(showEditor ? Strings.hideEditorPanel : Strings.showEditorPanel)
                        .keyboardShortcut("e", modifiers: .command)
                    }
                }
            }
            .alert(Strings.fileChanged, isPresented: $showExternalChangeAlert) {
                Button(Strings.reload) { viewModel.reloadFromDisk() }
                Button(Strings.keepMine, role: .cancel) { }
            } message: {
                Text(Strings.externalChangeMessage)
            }
            .onReceive(viewModel.$externalChangeConflict) { conflict in
                if conflict { showExternalChangeAlert = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveDocument)) { _ in
                if tab.url == nil {
                    // Untitled scratch tab (MV-007): no file on disk yet, so ⌘S must
                    // prompt for a location and promote the tab to a real file. This is
                    // the ONE site that intercepts save for a nil-url tab — the NSSavePanel
                    // lives here in the View layer so PreviewViewModel keeps zero AppKit
                    // panel dependencies (mirrors NSOpenPanel living in MarkViewApp).
                    saveUntitledTab()
                } else {
                    do {
                        try viewModel.save()
                    } catch {
                        errorPresenter.show("Save failed", detail: error.localizedDescription)
                        AppLogger.captureError(error, category: "file", message: "Manual save failed")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportHTML)) { _ in
                guard viewModel.isLoaded else {
                    errorPresenter.show("Export failed", detail: "No file loaded — open a markdown file first")
                    return
                }
                ExportManager.exportHTML(
                    html: viewModel.renderedHTML,
                    suggestedName: viewModel.fileName,
                    errorPresenter: errorPresenter
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
                guard viewModel.isLoaded else {
                    errorPresenter.show("PDF export failed", detail: "No file loaded — open a markdown file first")
                    return
                }
                let resolvedWebView: WKWebView? = viewModel.previewWebView ?? findPreviewWebView()
                guard let webView = resolvedWebView else {
                    errorPresenter.show("PDF export failed", detail: "Preview not loaded")
                    return
                }
                ExportManager.exportPDF(
                    from: webView,
                    suggestedName: viewModel.fileName,
                    errorPresenter: errorPresenter
                )
            }
            .onReceive(viewModel.$lastError) { error in
                if let error = error {
                    errorPresenter.show("Auto-save failed", detail: error.localizedDescription)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFindBar)) { _ in
                findBar.show()
            }
            .onReceive(NotificationCenter.default.publisher(for: .findBarNext)) { _ in
                findBar.findNext()
            }
            .onReceive(NotificationCenter.default.publisher(for: .findBarPrev)) { _ in
                findBar.findPrev()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeFile)) { _ in
                closeCurrentTab()
            }

            if let notification = errorPresenter.currentNotification {
                ErrorBanner(
                    notification: notification,
                    onDismiss: { errorPresenter.dismiss() },
                    onReport: { NSWorkspace.shared.open($0) }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: errorPresenter.currentNotification?.id)
    }

    // MARK: - Actions

    /// Close the current tab. If multiple tabs are open, removes this tab and selects
    /// the adjacent one. If this is the last tab, unloads the file and shows the home
    /// screen by removing the tab from TabManager (which sets selectedTabID to nil).
    private func closeCurrentTab() {
        if tabManager.tabs.count > 1 {
            tabManager.closeTab(tab.id)
        } else if viewModel.isLoaded {
            // Last tab — unload to home screen but keep the tab shell so the tab bar stays.
            // Actually per UX decision: all-tabs-closed → home screen.
            tabManager.closeTab(tab.id)
        } else {
            // Already on home screen — close window.
            NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
        }
    }

    /// ⌘S on an untitled tab (MV-007): run an NSSavePanel, then promote the tab to
    /// a real file via TabManager. Kept in the View layer so PreviewViewModel stays
    /// free of AppKit panel dependencies (mirrors NSOpenPanel living in MarkViewApp).
    private func saveUntitledTab() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "markdown")!,
        ]
        panel.nameFieldStringValue = "Untitled.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tabManager.promoteUntitledTab(tab, to: url)
            registerFileInWindow(url.path)
        } catch {
            errorPresenter.show("Save failed", detail: error.localizedDescription)
            AppLogger.captureError(error, category: "file", message: "Untitled tab save failed")
        }
    }

    private func findPreviewWebView() -> WKWebView? {
        func search(in view: NSView) -> WKWebView? {
            if let wk = view as? WKWebView { return wk }
            for sub in view.subviews {
                if let found = search(in: sub) { return found }
            }
            return nil
        }
        guard let contentView = NSApp.keyWindow?.contentView else { return nil }
        return search(in: contentView)
    }

    private func registerFileInWindow(_ path: String) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow })
                    ?? NSApplication.shared.windows.first(where: { $0.isVisible }) else { return }
            WindowFileTracker.shared.register(window: window, filePath: path)
        }
    }

    private func installEscMonitor() {
        guard escMonitorHolder.monitor == nil else { return }
        escMonitorHolder.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, self.findBar.isVisible else { return event }
            DispatchQueue.main.async { self.findBar.hide() }
            return nil
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitorHolder.monitor {
            NSEvent.removeMonitor(monitor)
            escMonitorHolder.monitor = nil
        }
    }

    private func toggleEditor() {
        showEditor.toggle()
        // Pane mode is per-tab state — persist so it survives tab switches (MV-003).
        tab.showEditor = showEditor
        guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.windows.first else { return }
        let screen = window.screen ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let newWidth = WindowLayout.width(showEditor: showEditor, in: screenFrame)
        let newX = screenFrame.origin.x + (screenFrame.width - newWidth) / 2
        window.setFrame(NSRect(x: newX, y: window.frame.origin.y, width: newWidth, height: window.frame.height), display: true, animate: true)
    }
}
