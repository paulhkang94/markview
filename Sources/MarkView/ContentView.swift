import SwiftUI
import MarkViewCore

struct ContentView: View {
    let initialFilePath: String?

    @StateObject private var viewModel = PreviewViewModel()
    @State private var showEditor = false
    @State private var showExternalChangeAlert = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if viewModel.isLoaded {
                    if showEditor {
                        HSplitView {
                            EditorView(text: $viewModel.editorContent) { newText in
                                viewModel.contentDidChange(newText)
                            }
                            .frame(minWidth: 200)

                            WebPreviewView(html: viewModel.renderedHTML)
                                .frame(minWidth: 200)
                        }
                    } else {
                        WebPreviewView(html: viewModel.renderedHTML)
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
                    lintErrors: viewModel.lintErrors
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if viewModel.isLoaded {
                    Button {
                        showEditor.toggle()
                    } label: {
                        Image(systemName: showEditor ? "doc.plaintext" : "rectangle.split.2x1")
                    }
                    .help(showEditor ? "Hide Editor (⌘E)" : "Show Editor (⌘E)")
                    .keyboardShortcut("e", modifiers: .command)
                }
            }
        }
        .onChange(of: initialFilePath) { newPath in
            if let path = newPath {
                viewModel.loadFile(at: path)
            }
        }
        .onAppear {
            if let path = initialFilePath {
                viewModel.loadFile(at: path)
            }
        }
        .alert("File Changed", isPresented: $showExternalChangeAlert) {
            Button("Reload") { viewModel.reloadFromDisk() }
            Button("Keep Mine", role: .cancel) { }
        } message: {
            Text("This file has been modified externally. Reload to see changes, or keep your edits?")
        }
        .onReceive(viewModel.$externalChangeConflict) { conflict in
            if conflict { showExternalChangeAlert = true }
        }
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
            Text("Drop a Markdown file here")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("or use File → Open (⌘O)")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
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

    private func isMarkdownFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "txt"].contains(ext)
    }
}
