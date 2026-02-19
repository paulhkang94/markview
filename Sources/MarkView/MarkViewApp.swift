import Combine
import SwiftUI
import MarkViewCore
import Sentry

/// Intercepts file-open events at the AppKit layer before SwiftUI processes them.
/// With `Window` (not `WindowGroup`), SwiftUI never creates duplicate windows.
/// The AppDelegate routes file opens to the existing single window via @Published.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    /// File path requested by Finder — observed by MarkViewApp via @Published.
    @Published var pendingFilePath: String?
    private var restoreFrameAfterFullScreen: NSRect?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent automatic window tabbing (Cmd+T creating tabs)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.isFileURL else { return }
        pendingFilePath = url.path
    }

    /// Treat title-bar double-click (zoom) as a fullscreen toggle.
    /// We preserve the current frame so exiting fullscreen restores the
    /// same dynamic size chosen by the app (preview-only or split view).
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            return false
        }

        restoreFrameAfterFullScreen = window.frame
        window.toggleFullScreen(nil)
        return false
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let restoreFrameAfterFullScreen else { return }
        window.setFrame(restoreFrameAfterFullScreen, display: true)
        self.restoreFrameAfterFullScreen = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Tracks which file path is displayed in each window.
/// Simplified: only register/query — no window closing logic needed
/// because `Window` scene guarantees a single window.
@MainActor
final class WindowFileTracker {
    static let shared = WindowFileTracker()
    private var windowToPath: [ObjectIdentifier: String] = [:]

    func register(window: NSWindow, filePath: String) {
        windowToPath[ObjectIdentifier(window)] = filePath
    }

    func filePath(for window: NSWindow) -> String? {
        windowToPath[ObjectIdentifier(window)]
    }
}

@main
struct MarkViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var filePath: String?
    @State private var errorPresenter = ErrorPresenter()

    init() {
        SentrySDK.start { options in
            options.dsn = "https://b72cf30350da5450221ea62ce5dc1069@o4510904217108480.ingest.us.sentry.io/4510904219074560"
            options.enableUncaughtNSExceptionReporting = true
            options.environment = {
                #if DEBUG
                return "development"
                #else
                return "production"
                #endif
            }()
            options.releaseName = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            options.tracesSampleRate = 0.1
        }
    }

    private var defaultWindowSize: CGSize {
        WindowLayout.defaultWindowSize(for: NSScreen.main?.visibleFrame)
    }

    var body: some Scene {
        // `Window` (not `WindowGroup`) — guarantees exactly one window.
        // File opens are routed via AppDelegate.pendingFilePath, not by
        // SwiftUI creating new windows.
        Window("MarkView", id: "main") {
            ContentView(initialFilePath: filePath, errorPresenter: errorPresenter)
                .frame(minWidth: 600, minHeight: 400)
                .onAppear {
                    let args = CommandLine.arguments
                    if args.count > 1 {
                        let path = args[1]
                        if FileManager.default.fileExists(atPath: path) {
                            filePath = path
                        }
                    }

                    // Defer window sizing to next run loop — window may not exist yet during onAppear.
                    // Always apply to override macOS state restoration which saves the previous frame.
                    DispatchQueue.main.async {
                        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible || $0.isKeyWindow }) ?? NSApplication.shared.windows.first else { return }
                        window.delegate = appDelegate
                        let size = defaultWindowSize
                        let screen = window.screen ?? NSScreen.main
                        if let screenFrame = screen?.visibleFrame {
                            let x = screenFrame.origin.x + (screenFrame.width - size.width) / 2
                            let y = screenFrame.origin.y + (screenFrame.height - size.height) / 2
                            window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
                        }
                    }
                }
                .onOpenURL { url in
                    if url.isFileURL {
                        filePath = url.path
                    }
                }
                .onReceive(appDelegate.$pendingFilePath) { path in
                    if let path = path {
                        filePath = path
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(Strings.openFile) { openFile() }
                    .keyboardShortcut("o", modifiers: .command)

                Button(Strings.closeWindow) {
                    NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Button(Strings.closeWindow) {
                    NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
                }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
            }

            CommandGroup(replacing: .saveItem) {
                Button(Strings.saveDocument) {
                    NotificationCenter.default.post(name: .saveDocument, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandGroup(after: .importExport) {
                Button(Strings.exportHTML) {
                    NotificationCenter.default.post(name: .exportHTML, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .accessibilityHint(Strings.exportHTMLA11yHint)

                Button(Strings.exportPDF) {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .accessibilityHint(Strings.exportPDFA11yHint)
            }

            CommandGroup(after: .toolbar) {
                Button(Strings.increaseFontSize) {
                    let s = AppSettings.shared
                    s.editorFontSize = min(s.editorFontSize + 1, 24)
                    s.previewFontSize = min(s.previewFontSize + 1, 24)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button(Strings.decreaseFontSize) {
                    let s = AppSettings.shared
                    s.editorFontSize = max(s.editorFontSize - 1, 10)
                    s.previewFontSize = max(s.previewFontSize - 1, 12)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button(Strings.resetFontSize) {
                    let s = AppSettings.shared
                    s.editorFontSize = 14
                    s.previewFontSize = 16
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        .commands {
            // Standard Find menu — SwiftUI doesn't provide this by default,
            // so Cmd+F/Cmd+G won't work without it. These send the standard
            // performFindPanelAction: to the responder chain (NSTextView, WKWebView).
            CommandGroup(after: .textEditing) {
                Section {
                    Button(Strings.find) { FindHelper.send(.showFindPanel) }
                        .keyboardShortcut("f", modifiers: .command)
                    Button(Strings.findAndReplace) { FindHelper.send(.showFindPanel, replace: true) }
                        .keyboardShortcut("f", modifiers: [.command, .option])
                    Button(Strings.findNext) { FindHelper.send(.next) }
                        .keyboardShortcut("g", modifiers: .command)
                    Button(Strings.findPrevious) { FindHelper.send(.previous) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                    Button(Strings.useSelectionForFind) { FindHelper.send(.setFindString) }
                }
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "markdown")!,
            .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
        }
    }
}

extension Notification.Name {
    static let exportHTML = Notification.Name("exportHTML")
    static let exportPDF = Notification.Name("exportPDF")
    static let saveDocument = Notification.Name("saveDocument")
}

/// Sends performFindPanelAction: through the responder chain using a tagged NSMenuItem.
/// NSTextView's find bar uses the sender's tag to determine which action to perform.
enum FindHelper {
    @MainActor static func send(_ action: NSFindPanelAction, replace: Bool = false) {
        let item = NSMenuItem()
        item.tag = Int(action.rawValue)
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
    }
}
