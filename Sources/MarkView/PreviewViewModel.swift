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
    @Published var lintWarnings: Int = 0
    @Published var lintErrors: Int = 0
    @Published var lintDiagnostics: [LintDiagnostic] = []
    @Published var lastError: Error?

    @Published var currentFilePath: String?
    @Published var fileName: String = "MarkView"

    /// Directory URL of the current file, used as base URL for resolving relative paths (images, links)
    var currentFileDirectoryURL: URL? {
        guard let path = currentFilePath else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }

    private var fileWatcher: FileWatcher?
    private var renderTask: Task<Void, Never>?
    private var lintTask: Task<Void, Never>?
    private var autoSaveTimer: Timer?
    private var template: String?
    private var originalContent: String = ""
    private let linter = MarkdownLinter()

    func loadFile(at path: String) {
        currentFilePath = path
        fileName = URL(fileURLWithPath: path).lastPathComponent

        loadTemplate()
        loadContent(from: path)
        watchFile(at: path)
        startAutoSaveTimer()
    }

    func contentDidChange(_ newText: String) {
        editorContent = newText
        isDirty = newText != originalContent
        renderDebounced(newText)
        lintDebounced(newText)
    }

    func reloadFromDisk() {
        guard let path = currentFilePath else { return }
        loadContent(from: path)
        externalChangeConflict = false
    }

    func autoFixLint() {
        let fixed = linter.autoFix(editorContent)
        guard fixed != editorContent else { return }
        editorContent = fixed
        isDirty = fixed != originalContent
        renderImmediate(fixed)
        runLint(fixed)
    }

    func save() throws {
        guard let path = currentFilePath else { return }
        if AppSettings.shared.formatOnSave {
            autoFixLint()
        }
        try editorContent.write(toFile: path, atomically: true, encoding: .utf8)
        originalContent = editorContent
        isDirty = false
    }

    func startAutoSaveTimer() {
        stopAutoSaveTimer()
        guard AppSettings.shared.autoSave else { return }
        let interval = AppSettings.shared.autoSaveInterval
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isDirty else { return }
                do {
                    try self.save()
                } catch {
                    self.lastError = error
                    AppLogger.captureError(error, category: "file", message: "Auto-save failed")
                }
            }
        }
    }

    func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    // MARK: - Private

    private func loadTemplate() {
        guard let url = ResourceBundle.url(forResource: "template", withExtension: "html", subdirectory: "Resources") else {
            AppLogger.render.warning("Template resource not found in bundle")
            AppLogger.breadcrumb("Template resource missing", category: "render", level: .warning)
            return
        }
        do {
            template = try String(contentsOf: url, encoding: .utf8)
        } catch {
            AppLogger.render.error("Failed to load template: \(error.localizedDescription)")
            AppLogger.captureError(error, category: "render", message: "Template load failed")
        }
    }

    private func loadContent(from path: String) {
        // Resolve symlinks and normalize path to avoid file:// URL mismatches
        let resolvedPath = (path as NSString).resolvingSymlinksInPath
        let content: String
        do {
            content = try String(contentsOfFile: resolvedPath, encoding: .utf8)
        } catch {
            // Fallback: try original path in case resolution changed it incorrectly
            do {
                content = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                AppLogger.file.error("Failed to load file at \(path): \(error.localizedDescription)")
                AppLogger.captureError(error, category: "file", message: "File load failed: \(path)")
                lastError = error
                return
            }
        }
        editorContent = content
        originalContent = content
        isDirty = false
        renderImmediate(content)
        runLint(content)
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

    private func lintDebounced(_ markdown: String) {
        lintTask?.cancel()
        lintTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            runLint(markdown)
        }
    }

    private func runLint(_ markdown: String) {
        let diagnostics = linter.lint(markdown)
        lintDiagnostics = diagnostics
        lintWarnings = diagnostics.filter { $0.severity == .warning }.count
        lintErrors = diagnostics.filter { $0.severity == .error }.count
    }

    private func watchFile(at path: String) {
        fileWatcher?.stop()
        fileWatcher = FileWatcher(path: path) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isDirty {
                    self.externalChangeConflict = true
                } else {
                    self.loadContent(from: path)
                }
            }
        }
        fileWatcher?.start()
    }

    nonisolated deinit {
        // FileWatcher and Timer cleanup — both are safe to call from any context
        MainActor.assumeIsolated {
            fileWatcher?.stop()
            autoSaveTimer?.invalidate()
        }
    }
}
