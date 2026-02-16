import SwiftUI

struct ContentView: View {
    let initialFilePath: String?

    @StateObject private var viewModel = PreviewViewModel()

    var body: some View {
        Group {
            if viewModel.isLoaded {
                WebPreviewView(html: viewModel.renderedHTML)
            } else {
                DropTargetView { url in
                    viewModel.loadFile(at: url.path)
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
        return ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "txt"].contains(ext)
    }
}
