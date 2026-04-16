import SwiftUI
import MarkViewCore
import WebKit

/// Reference-type wrapper so the NSEvent monitor can be stored in a @State.
/// Swift structs can't mutate stored var properties from closure captures,
/// but a class-based holder works cleanly as a @State reference.
private final class EscMonitorHolder {
    var monitor: Any?
}

struct ContentView: View {
    @Binding var filePath: String?
    var errorPresenter: ErrorPresenter

    @StateObject private var viewModel = PreviewViewModel()
    @StateObject private var findBar = FindBarController()
    @ObservedObject private var settings = AppSettings.shared
    /// Direct coordinator-to-coordinator scroll sync — bypasses SwiftUI entirely.
    @State private var syncController = ScrollSyncController()
    @State private var showEditor = false
    @State private var showExternalChangeAlert = false
    @State private var escMonitorHolder = EscMonitorHolder()

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Group {
                    if viewModel.isLoaded {
                        if showEditor {
                            HSplitView {
                                EditorView(
                                    text: $viewModel.editorContent,
                                    onChange: { newText in
                                        viewModel.contentDidChange(newText)
                                    },
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
                                    onWebViewCreated: { webView in viewModel.previewWebView = webView }
                                )
                                .id(viewModel.currentFilePath ?? "")
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
                                onWebViewCreated: { webView in viewModel.previewWebView = webView }
                            )
                            .id(viewModel.currentFilePath ?? "")
                        }
                    } else {
                        HomeScreenView { url in
                            viewModel.loadFile(at: url.path)
                            registerFileInWindow(url.path)
                        }
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
                            viewModel.unloadFile()
                            showEditor = false
                            filePath = nil
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
            .onChange(of: filePath) {
                if let path = filePath {
                    viewModel.loadFile(at: path)
                    syncController.reset()
                    registerFileInWindow(path)
                }
            }
            .onAppear {
                if let path = filePath {
                    viewModel.loadFile(at: path)
                    registerFileInWindow(path)
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
                do {
                    try viewModel.save()
                } catch {
                    errorPresenter.show("Save failed", detail: error.localizedDescription)
                    AppLogger.captureError(error, category: "file", message: "Manual save failed")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportHTML)) { _ in
                AppLogger.export.info("exportHTML notification received — isLoaded=\(viewModel.isLoaded)")
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
                AppLogger.export.info("exportPDF notification received — isLoaded=\(viewModel.isLoaded) hasWebView=\(viewModel.previewWebView != nil)")
                guard viewModel.isLoaded else {
                    errorPresenter.show("PDF export failed", detail: "No file loaded — open a markdown file first")
                    return
                }
                // Prefer direct reference stored at view creation; fall back to hierarchy search.
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
                if viewModel.isLoaded {
                    viewModel.unloadFile()
                    showEditor = false
                    filePath = nil
                } else {
                    NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
                }
            }

            if let notification = errorPresenter.currentNotification {
                ErrorBanner(
                    notification: notification,
                    onDismiss: { errorPresenter.dismiss() },
                    onReport: { url in NSWorkspace.shared.open(url) }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: errorPresenter.currentNotification?.id)
    }

    /// Find the WKWebView in the key window's view hierarchy.
    /// Used to pass the live webView to ExportManager at export time.
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

    /// Register the current file path with the window tracker.
    /// Window dedup is handled at the AppDelegate layer — this only tracks the mapping.
    private func registerFileInWindow(_ path: String) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow })
                    ?? NSApplication.shared.windows.first(where: { $0.isVisible }) else { return }
            WindowFileTracker.shared.register(window: window, filePath: path)
        }
    }

    /// Install an app-level NSEvent monitor that consumes Esc when the find bar is visible.
    /// NSEvent.addLocalMonitorForEvents fires regardless of which view has focus,
    /// unlike TextField.onKeyPress which only fires when the TextField is first responder.
    private func installEscMonitor() {
        guard escMonitorHolder.monitor == nil else { return }
        escMonitorHolder.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, self.findBar.isVisible else { return event }
            DispatchQueue.main.async { self.findBar.hide() }
            return nil  // consume event — prevents Esc from closing the window
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitorHolder.monitor {
            NSEvent.removeMonitor(monitor)
            escMonitorHolder.monitor = nil
        }
    }

    /// Toggle editor pane and resize window to target screen percentages.
    /// Preview-only: 55% screen width. Editor+preview: 80% screen width.
    /// Conservative: slightly wide is better than too narrow for readability.
    private func toggleEditor() {
        showEditor.toggle()

        guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.windows.first else { return }

        let screen = window.screen ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let currentFrame = window.frame

        let newWidth = WindowLayout.width(showEditor: showEditor, in: screenFrame)

        // Center horizontally, keep vertical position
        let newX = screenFrame.origin.x + (screenFrame.width - newWidth) / 2
        window.setFrame(NSRect(x: newX, y: currentFrame.origin.y, width: newWidth, height: currentFrame.height), display: true, animate: true)
    }
}

