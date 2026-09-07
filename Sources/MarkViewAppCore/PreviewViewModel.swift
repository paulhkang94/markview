import Combine
import WebKit
import MarkViewCore

/// Moved from the Xcode app target to MarkViewAppCore (mar-033 Tier-B, mar-038):
/// previously only reachable from MarkViewTestRunner via source-inspection tests
/// that grepped this file as a string (see mar-037's "no longer reads on the
/// main thread" regression test below), now directly importable and
/// behaviorally testable — including as the per-tab model driven by
/// TabManager.openFile in the restore-loop tests this move exists to enable.
///
/// AppLogger/Sentry calls became `AppCoreLog.logger` calls (see
/// AppCoreLogging.swift) so this library stays Sentry-free; the app target
/// installs the real Sentry-backed bridge once at startup
/// (`AppCoreLog.logger = SentryAppCoreLogger()` in MarkViewApp.init), so
/// production logging behavior is unchanged. Tests get the default no-op.
@MainActor
public final class PreviewViewModel: ObservableObject {
    public typealias LintOperation = @Sendable (String) -> [LintDiagnostic]
    /// Markdown -> HTML *body* render. Injectable for exactly the reason
    /// `LintOperation` is: it is CPU-bound work this class must keep OFF the
    /// main actor (mar-049 / APPLE-MACOS-4J), and proving that requires a
    /// deterministic slow/instrumented stand-in in tests. Production always
    /// gets `MarkdownRenderer.renderHTML(from:)` via the init default.
    public typealias RenderOperation = @Sendable (String) -> String

    @Published public var renderedHTML: String = ""

    /// True once this view model has content the UI can honestly display.
    ///
    /// **Contract (mar-049):** `isLoaded` flips true when the FIRST render of
    /// the current content has been *published* to `renderedHTML` — not when
    /// the file finishes being read. Rendering now runs off the main actor
    /// (see `scheduleRender`), so those are no longer the same instant, and
    /// gating on the read would reveal the preview pane while `renderedHTML`
    /// is still empty (blank flash on a cold open) or still holds the
    /// previous document (stale content). ContentView gates the entire
    /// editor/preview/status-bar/toolbar tree — plus HTML and PDF export —
    /// on this flag, so "loaded" has to mean "renderedHTML matches the
    /// content that was loaded".
    ///
    /// One deliberate exception: `startUntitled()` sets it synchronously.
    /// That buffer's content is empty, so an empty preview is already
    /// truthful and flipping on render completion would only add a frame of
    /// home screen after ⌘T.
    ///
    /// Once true it stays true until `unloadFile()`. A reload of an
    /// already-loaded document therefore keeps showing the previous render
    /// (never the home screen) for the duration of the new render.
    @Published public var isLoaded: Bool = false
    @Published public var editorContent: String = ""
    @Published public var isDirty: Bool = false
    @Published public var externalChangeConflict: Bool = false
    @Published public var lintWarnings: Int = 0
    @Published public var lintErrors: Int = 0
    @Published public var lintDiagnostics: [LintDiagnostic] = []
    @Published public var lastError: Error?

    @Published public var currentFilePath: String?
    @Published public var fileName: String = "MarkView"

    /// Directory URL of the current file, used as base URL for resolving relative paths (images, links)
    public var currentFileDirectoryURL: URL? {
        guard let path = currentFilePath else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }

    /// Direct reference to the live WKWebView, set via WebPreviewView.onWebViewCreated.
    /// Used for PDF export — avoids fragile view-hierarchy search at export time.
    public weak var previewWebView: WKWebView?

    private var fileWatcher: FileWatcher?
    private var renderTask: Task<Void, Never>?
    private var lintTask: Task<Void, Never>?
    private var lintGeneration = 0
    private var autoSaveTimer: Timer?
    private var template: String?
    private var originalContent: String = ""
    private let linter = MarkdownLinter()
    private let lintOperation: LintOperation
    private let renderOperation: RenderOperation
    /// Monotonic token for renders (mar-049 / APPLE-MACOS-4J): only the NEWEST
    /// render may publish. Renders run off the main actor and cmark cannot be
    /// interrupted mid-document, so a superseded render always runs to
    /// completion — this token, not task cancellation, is what stops it from
    /// overwriting newer HTML. Same pattern as `contentLoadGeneration`
    /// (mar-037) and `lintGeneration` (#69).
    private var renderGeneration = 0
    /// Monotonic token for loadContent (item-713 fourth hang class, mar-037):
    /// only the NEWEST in-flight read may publish. A stale completion (a
    /// newer loadFile/reloadFromDisk/watcher-triggered read started while an
    /// older one was still on disk) is dropped instead of overwriting the
    /// editor with older content — same pattern as mar-028's loadGeneration.
    private var contentLoadGeneration = 0
    /// Suppresses file watcher reload during our own saves to prevent the watcher from
    /// reading back the file we just wrote and triggering a redundant (or racy) content reload.
    private var suppressFileWatcher = false

    public init(
        lintOperation: @escaping LintOperation = { markdown in
            MarkdownLinter().lint(markdown)
        },
        renderOperation: @escaping RenderOperation = { markdown in
            MarkdownRenderer.renderHTML(from: markdown)
        }
    ) {
        self.lintOperation = lintOperation
        self.renderOperation = renderOperation
    }

    public func loadFile(at path: String) {
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
    public func startUntitled() {
        loadTemplate()
        currentFilePath = nil
        fileName = "Untitled"
        editorContent = ""
        originalContent = ""
        isDirty = false
        renderImmediate("")
        // The one synchronous isLoaded flip (mar-049): this buffer's content is
        // empty, so an empty preview is already truthful and waiting for the
        // render would only show the home screen for a frame after ⌘T.
        isLoaded = true
    }

    public func contentDidChange(_ newText: String) {
        editorContent = newText
        isDirty = newText != originalContent
        renderDebounced(newText)
        lintDebounced(newText)
    }

    public func reloadFromDisk() {
        guard let path = currentFilePath else { return }
        loadContent(from: path)
        externalChangeConflict = false
    }

    public func autoFixLint() {
        let fixed = linter.autoFix(editorContent)
        guard fixed != editorContent else { return }
        editorContent = fixed
        isDirty = fixed != originalContent
        renderImmediate(fixed)
        runLint(fixed)
    }

    public func save(applyFormat: Bool = true) throws {
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

    public func startAutoSaveTimer() {
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
                    AppCoreLog.logger.logError(error, category: "file", message: "Auto-save failed")
                }
            }
        }
    }

    public func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    /// Unload the current file and return the app to the home screen.
    /// Records an explicit close so the next cold launch does not auto-reopen.
    public func unloadFile() {
        fileWatcher?.stop()
        fileWatcher = nil
        stopAutoSaveTimer()
        renderTask?.cancel()
        lintTask?.cancel()
        // Cancellation alone cannot stop a render that is already inside cmark
        // (mar-049), so invalidate it by generation too — otherwise it would
        // republish HTML and re-set isLoaded for a document just closed.
        renderGeneration += 1
        lintGeneration += 1
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
            AppCoreLog.logger.logWarning("Template resource not found in bundle — preview will use fallback template", category: "render")
            AppCoreLog.logger.logError(CocoaError(.fileNoSuchFile), category: "render", message: "Template resource missing from bundle")
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
            AppCoreLog.logger.logWarning("Failed to load template: \(error.localizedDescription)", category: "render")
            AppCoreLog.logger.logError(error, category: "render", message: "Template load failed")
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
        // isLoaded is deliberately NOT set here (mar-049). The render is now
        // asynchronous, so the flag flips when the first render publishes —
        // the instant renderedHTML actually matches this content. Setting it
        // here would reveal the preview pane over empty (cold open) or
        // previous-document (reload) HTML. See the isLoaded contract.
        renderImmediate(content)
        runLint(content)
    }

    private func failLoadContent(_ error: Error, path: String, generation: Int) {
        guard generation == contentLoadGeneration else { return }
        AppCoreLog.logger.logWarning("Failed to load file at \(path): \(error.localizedDescription)", category: "file")
        AppCoreLog.logger.logError(error, category: "file", message: "File load failed: \(path)")
        lastError = error
    }

    /// Start a render of `markdown` with no debounce. "Immediate" is about when
    /// the render *starts*, not when it finishes: since mar-049 the render runs
    /// off the main actor and `renderedHTML` is published later (see
    /// `scheduleRender`). Callers must not assume `renderedHTML` — or
    /// `isLoaded` — has changed by the time this returns.
    private func renderImmediate(_ markdown: String) {
        scheduleRender(markdown)
    }

    private func renderDebounced(_ markdown: String) {
        scheduleRender(markdown, debounceNanoseconds: 150_000_000) // 150ms debounce
    }

    /// Rendering markdown to HTML is CPU-bound and, on large or node-dense
    /// documents, slow: cmark's HTML writer measured >2s on realistic corpora,
    /// which is exactly the >=2000ms main-thread block Sentry reported as the
    /// APPLE-MACOS-4J App Hang (mar-049). It used to run synchronously here on
    /// the main actor for every file open, keystroke debounce, auto-fix and
    /// file-watcher reload. Run it away from the main actor and publish only
    /// the newest result — the same shape as `scheduleLint` (#69) and
    /// `loadContent`'s generation guard (mar-037).
    ///
    /// Correctness rests on `renderGeneration`, NOT on task cancellation: a
    /// superseded render already inside cmark cannot be interrupted, so it runs
    /// to completion and is dropped here. That is also why `unloadFile()` bumps
    /// the generation — without it, a render started for a document that has
    /// since been closed would republish HTML and re-set `isLoaded`.
    ///
    /// Publishing sets `isLoaded`: see the contract on that property. This is
    /// the single site that flips it for file-backed content, which is what
    /// keeps all four render entry points consistent.
    private func scheduleRender(_ markdown: String, debounceNanoseconds: UInt64? = nil) {
        renderTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        let operation = renderOperation
        let currentTemplate = template
        renderTask = Task {
            if let debounceNanoseconds {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
                guard !Task.isCancelled else { return }
            }
            let html = await Task.detached(priority: .userInitiated) {
                MarkdownRenderer.wrapInTemplate(operation(markdown), template: currentTemplate)
            }.value
            guard generation == renderGeneration else { return }
            renderedHTML = html
            isLoaded = true
        }
    }

    private func lintDebounced(_ markdown: String) {
        scheduleLint(markdown, debounceNanoseconds: 300_000_000)
    }

    private func runLint(_ markdown: String) {
        scheduleLint(markdown)
    }

    /// Markdown linting is CPU-bound and can be expensive for large documents.
    /// Run it away from the main actor, then publish only the newest result.
    private func scheduleLint(_ markdown: String, debounceNanoseconds: UInt64? = nil) {
        lintTask?.cancel()
        lintGeneration += 1
        let generation = lintGeneration
        let operation = lintOperation
        lintTask = Task {
            if let debounceNanoseconds {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
                guard !Task.isCancelled else { return }
            }
            let diagnostics = await Task.detached(priority: .userInitiated) {
                operation(markdown)
            }.value
            guard !Task.isCancelled, generation == lintGeneration else { return }
            lintDiagnostics = diagnostics
            lintWarnings = diagnostics.filter { $0.severity == .warning }.count
            lintErrors = diagnostics.filter { $0.severity == .error }.count
        }
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
