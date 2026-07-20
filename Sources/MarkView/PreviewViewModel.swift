import SwiftUI
import Combine
import WebKit
import MarkViewCore
import MarkViewAppCore

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

    /// Direct reference to the live WKWebView, set via WebPreviewView.onWebViewCreated.
    /// Used for PDF export — avoids fragile view-hierarchy search at export time.
    weak var previewWebView: WKWebView?

    private var fileWatcher: FileWatcher?
    private var renderTask: Task<Void, Never>?
    private var lintTask: Task<Void, Never>?
    private var autoSaveTimer: Timer?
    private var template: String?
    private var originalContent: String = ""
    private let linter = MarkdownLinter()
    /// Monotonic token for loadContent (item-713 fourth hang class, mar-037):
    /// only the NEWEST in-flight read may publish. A stale completion (a
    /// newer loadFile/reloadFromDisk/watcher-triggered read started while an
    /// older one was still on disk) is dropped instead of overwriting the
    /// editor with older content — same pattern as mar-028's loadGeneration.
    private var contentLoadGeneration = 0
    /// Suppresses file watcher reload during our own saves to prevent the watcher from
    /// reading back the file we just wrote and triggering a redundant (or racy) content reload.
    private var suppressFileWatcher = false

    func loadFile(at path: String) {
        currentFilePath = path
        fileName = URL(fileURLWithPath: path).lastPathComponent

        // Register in recents — covers all open paths (drag, menu ⌘O, MCP, CLI, auto-reopen).
        let fileURL = URL(fileURLWithPath: path)
        RecentFilesManager.shared.recordOpen(url: fileURL)

        loadTemplate()
        loadContent(from: path)
        watchFile(at: path)
        startAutoSaveTimer()
    }

    /// Start an untitled scratch buffer (MV-007): loaded and editable, but with no
    /// file on disk. Deliberately skips everything loadFile does that assumes a real
    /// path — no RecentFilesManager.recordOpen, no watchFile/FileWatcher, no
    /// startAutoSaveTimer — because there is nothing on disk yet to record, watch,
    /// or save to. The first successful ⌘S promotes the tab via
    /// TabManager.promoteUntitledTab → loadFile, which starts all of those exactly
    /// once. Loads the template + renders an empty document so typing renders live.
    func startUntitled() {
        loadTemplate()
        currentFilePath = nil
        fileName = "Untitled"
        editorContent = ""
        originalContent = ""
        isDirty = false
        renderImmediate("")
        isLoaded = true
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

    func save(applyFormat: Bool = true) throws {
        guard let path = currentFilePath else { return }
        // Format only on explicit save (Cmd+S) — never during auto-save.
        // Auto-save fires on a timer mid-typing; running autoFixLint() then rewrites
        // editorContent with reformatted text, triggering updateNSView while the cursor
        // is mid-word and the new (shorter) string makes the selection out-of-bounds.
        if applyFormat && AppSettings.shared.formatOnSave {
            autoFixLint()
        }
        // Suppress file watcher during our own write to prevent it from reloading the file
        // we just saved. The watcher fires on .write/.rename events from atomic saves, and
        // without suppression it would call loadContent → replace editor content → lose cursor.
        suppressFileWatcher = true
        try editorContent.write(toFile: path, atomically: true, encoding: .utf8)
        originalContent = editorContent
        isDirty = false
        // Re-enable watcher after a delay that exceeds the FileWatcher debounce (100ms) plus
        // the atomic-save re-watch delay (50ms). 250ms gives comfortable margin.
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            suppressFileWatcher = false
        }
    }

    func startAutoSaveTimer() {
        stopAutoSaveTimer()
        guard AppSettings.shared.autoSave else { return }
        let interval = AppSettings.shared.autoSaveInterval
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isDirty else { return }
                do {
                    try self.save(applyFormat: false)  // never auto-format during timer-based saves
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

    /// Unload the current file and return the app to the home screen.
    /// Records an explicit close so the next cold launch does not auto-reopen.
    func unloadFile() {
        fileWatcher?.stop()
        fileWatcher = nil
        stopAutoSaveTimer()
        renderTask?.cancel()
        lintTask?.cancel()
        currentFilePath = nil
        fileName = "MarkView"
        renderedHTML = ""
        editorContent = ""
        originalContent = ""
        isDirty = false
        isLoaded = false
        externalChangeConflict = false
        lintDiagnostics = []
        lintWarnings = 0
        lintErrors = 0
        previewWebView = nil
    }

    // MARK: - Private

    private func loadTemplate() {
        guard let url = ResourceBundle.url(forResource: "template", withExtension: "html", subdirectory: "Resources") else {
            AppLogger.render.error("Template resource not found in bundle — preview will use fallback template")
            AppLogger.captureError(CocoaError(.fileNoSuchFile), category: "render", message: "Template resource missing from bundle")
            assertionFailure("Template resource not found — ResourceBundle may not be resolving correctly")
            return
        }
        do {
            template = try String(contentsOf: url, encoding: .utf8)
            // Verify template contract: must contain required elements
            assert(template?.contains(TemplateConstants.contentPlaceholder) == true,
                   "Template missing \(TemplateConstants.contentPlaceholder) placeholder")
            assert(template?.contains("id=\"\(TemplateConstants.contentElementID)\"") == true,
                   "Template missing element with id=\"\(TemplateConstants.contentElementID)\"")
        } catch {
            AppLogger.render.error("Failed to load template: \(error.localizedDescription)")
            AppLogger.captureError(error, category: "render", message: "Template load failed")
        }
    }

    /// Read `path` off the main thread (item-713 fourth hang class, mar-037 /
    /// APPLE-MACOS-33) and publish the result on the main actor. Previously
    /// this read the file's content synchronously, in-line, here — for a large
    /// document, or a file on a slow/network volume, that blocks the main
    /// thread for the duration of the read on every file open, external-change
    /// reload, and file-watcher callback.
    private func loadContent(from path: String) {
        contentLoadGeneration += 1
        let generation = contentLoadGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let content = try FileContentLoader.read(from: path)
                await self?.finishLoadContent(content, generation: generation)
            } catch {
                await self?.failLoadContent(error, path: path, generation: generation)
            }
        }
    }

    /// Main-actor completion of loadContent. Superseded reads (a newer
    /// loadFile/reloadFromDisk/watcher-triggered call started while this one
    /// was still on disk) are dropped so rapid successive reloads always
    /// converge on the newest content instead of racing.
    private func finishLoadContent(_ content: String, generation: Int) {
        guard generation == contentLoadGeneration else { return }
        editorContent = content
        originalContent = content
        isDirty = false
        renderImmediate(content)
        runLint(content)
        isLoaded = true
    }

    private func failLoadContent(_ error: Error, path: String, generation: Int) {
        guard generation == contentLoadGeneration else { return }
        AppLogger.file.error("Failed to load file at \(path): \(error.localizedDescription)")
        AppLogger.captureError(error, category: "file", message: "File load failed: \(path)")
        lastError = error
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
                // Ignore file watcher events triggered by our own save operation.
                // Without this, save() → file write → watcher fires → loadContent() → replaces
                // editor content with what we just wrote, which resets cursor position.
                guard !self.suppressFileWatcher else { return }
                if self.isDirty {
                    self.externalChangeConflict = true
                } else {
                    self.loadContent(from: path)
                }
            }
        }
        fileWatcher?.start()
    }

    deinit {
        MainActor.assumeIsolated {
            fileWatcher?.stop()
            autoSaveTimer?.invalidate()
        }
    }
}
