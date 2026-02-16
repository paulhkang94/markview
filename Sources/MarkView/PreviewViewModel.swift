import SwiftUI
import Combine
import MarkViewCore

@MainActor
final class PreviewViewModel: ObservableObject {
    @Published var renderedHTML: String = ""
    @Published var isLoaded: Bool = false
    @Published var currentFilePath: String?
    @Published var fileName: String = "MarkView"

    private var fileWatcher: FileWatcher?
    private var cancellables = Set<AnyCancellable>()

    func loadFile(at path: String) {
        currentFilePath = path
        fileName = URL(fileURLWithPath: path).lastPathComponent

        // Update window title
        NSApplication.shared.mainWindow?.title = fileName

        renderFile(at: path)
        watchFile(at: path)
    }

    private func renderFile(at path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let bodyHTML = MarkdownRenderer.renderHTML(from: content)

        // Try to load template from app resources, fall back to built-in
        var template: String?
        if let templateURL = Bundle.module.url(forResource: "template", withExtension: "html", subdirectory: "Resources") {
            template = try? String(contentsOf: templateURL, encoding: .utf8)
        }
        renderedHTML = MarkdownRenderer.wrapInTemplate(bodyHTML, template: template)
        isLoaded = true
    }

    private func watchFile(at path: String) {
        fileWatcher?.stop()
        fileWatcher = FileWatcher(path: path) { [weak self] in
            Task { @MainActor in
                self?.renderFile(at: path)
            }
        }
        fileWatcher?.start()
    }

    deinit {
        fileWatcher?.stop()
    }
}
