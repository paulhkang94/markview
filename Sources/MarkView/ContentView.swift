import SwiftUI
import MarkViewCore

struct ContentView: View {
    let initialFilePath: String?
    var errorPresenter: ErrorPresenter

    @StateObject private var viewModel = PreviewViewModel()
    @ObservedObject private var settings = AppSettings.shared
    /// Direct coordinator-to-coordinator scroll sync — bypasses SwiftUI entirely.
    @State private var syncController = ScrollSyncController()
    @State private var showEditor = false
    @State private var showExternalChangeAlert = false

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
                                    syncController: syncController
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
                                syncController: syncController
                            )
                            .id(viewModel.currentFilePath ?? "")
                        }
                    } else {
                        DropTargetView { url in
                            viewModel.loadFile(at: url.path)
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
            .navigationTitle(viewModel.fileName)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if viewModel.isLoaded {
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
            .onChange(of: initialFilePath) {
                if let path = initialFilePath {
                    viewModel.loadFile(at: path)
                    syncController.reset()
                    registerFileInWindow(path)
                }
            }
            .onAppear {
                if let path = initialFilePath {
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

            .onReceive(viewModel.$lastError) { error in
                if let error = error {
                    errorPresenter.show("Auto-save failed", detail: error.localizedDescription)
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

    /// Register the current file path with the window tracker.
    /// Window dedup is handled at the AppDelegate layer — this only tracks the mapping.
    private func registerFileInWindow(_ path: String) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow })
                    ?? NSApplication.shared.windows.first(where: { $0.isVisible }) else { return }
            WindowFileTracker.shared.register(window: window, filePath: path)
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

        let newFrame = WindowLayout.resizedFrame(
            currentFrame: currentFrame,
            visibleFrame: screenFrame,
            showEditor: showEditor
        )
        window.setFrame(newFrame, display: true, animate: true)
    }
}

struct DropTargetView: View {
    let onDrop: (URL) -> Void
    @State private var isTargeted = false

    var body: some View {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        .accessibilityLabel(Strings.dropA11yLabel)
        .accessibilityHint(Strings.dropA11yHint)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, isMarkdownFile(url) {
                    DispatchQueue.main.async {
                        onDrop(url)
                    }
                }
            }
            return true
        }
    }

}

private func isMarkdownFile(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "txt"].contains(ext)
}
