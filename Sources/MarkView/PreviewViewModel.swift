import SwiftUI
import Combine
import MarkViewCore

@MainActor
final class PreviewViewModel: ObservableObject {
    @Published var renderedHTML: String = ""
    @Published var isLoaded: Bool = false
    @Published var editorContent: String = ""
    @Published var isDirty: Bool = false
    @Published var externalChangeConflict: Bool = false

    var currentFilePath: String?
    var fileName: String = "MarkView"

    private var fileWatcher: FileWatcher?
    private var renderTask: Task<Void, Never>?
    private var template: String?
    private var originalContent: String = ""

    func loadFile(at path: String) {
        currentFilePath = path
        fileName = URL(fileURLWithPath: path).lastPathComponent
        NSApplication.shared.mainWindow?.title = fileName

        loadTemplate()
        loadContent(from: path)
        watchFile(at: path)
    }

    func contentDidChange(_ newText: String) {
        editorContent = newText
        isDirty = newText != originalContent
        renderDebounced(newText)
    }

    func reloadFromDisk() {
        guard let path = currentFilePath else { return }
        loadContent(from: path)
        externalChangeConflict = false
    }

    func save() throws {
        guard let path = currentFilePath else { return }
        try editorContent.write(toFile: path, atomically: true, encoding: .utf8)
        originalContent = editorContent
        isDirty = false
    }

    // MARK: - Private

    private func loadTemplate() {
        if let url = Bundle.module.url(forResource: "template", withExtension: "html", subdirectory: "Resources") {
            template = try? String(contentsOf: url, encoding: .utf8)
        }
    }

    private func loadContent(from path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        editorContent = content
        originalContent = content
        isDirty = false
        renderImmediate(content)
        isLoaded = true
    }

    private func renderImmediate(_ markdown: String) {
        let bodyHTML = MarkdownRenderer.renderHTML(from: markdown)
        renderedHTML = MarkdownRenderer.wrapInTemplate(bodyHTML, template: template)
    }

    private func renderDebounced(_ markdown: String) {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
            guard !Task.isCancelled else { return }
            renderImmediate(markdown)
        }
    }

    private func watchFile(at path: String) {
        fileWatcher?.stop()
        fileWatcher = FileWatcher(path: path) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isDirty {
                    // Editor has unsaved changes — prompt user
                    self.externalChangeConflict = true
                } else {
                    // Clean state — auto-reload
                    self.loadContent(from: path)
                }
            }
        }
        fileWatcher?.start()
    }

    deinit {
        fileWatcher?.stop()
    }
}
