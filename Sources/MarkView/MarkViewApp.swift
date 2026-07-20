import Combine
import MarkViewCore
import MarkViewAppCore
import SwiftUI
import Sentry

/// Intercepts file-open events at the AppKit layer before SwiftUI processes them.
/// With `Window` (not `WindowGroup`), SwiftUI never creates duplicate windows.
/// The AppDelegate routes file opens to the existing single window via @Published.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// File path requested by Finder — observed by MarkViewApp via @Published.
    @Published var pendingFilePath: String?

    /// True during the cold-launch restoration window (first 0.8s after launch).
    /// macOS calls `application(_:open:)` during this window to restore the last
    /// document. We suppress that when the user has opted out of window restore.
    private var isInLaunchRestorationPhase = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent automatic window tabbing (Cmd+T creating tabs)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Mark end of launch restoration window after a short delay.
        // Any open events after this are genuine user-initiated opens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.isInLaunchRestorationPhase = false
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.isFileURL else { return }
        // Suppress macOS launch-restoration opens when the user opted out.
        // Use UserDefaults directly (thread-safe) to avoid @MainActor dependency.
        // Default is true when the key has never been set.
        let windowRestore: Bool
        if UserDefaults.standard.object(forKey: "windowRestore") != nil {
            windowRestore = UserDefaults.standard.bool(forKey: "windowRestore")
        } else {
            windowRestore = true
        }
        let didExplicitlyClose = UserDefaults.standard.bool(forKey: "didExplicitlyCloseFile")
        if isInLaunchRestorationPhase && (!windowRestore || didExplicitlyClose) {
            return
        }
        pendingFilePath = url.path
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
    @StateObject private var tabManager = TabManager()
    @State private var errorPresenter = ErrorPresenter()

    init() {
        // Install the Sentry-backed logging bridge before any MarkViewAppCore
        // type (PreviewViewModel, moved mar-033 Tier-B / mar-038) can log
        // anything — see SentryAppCoreLogger in AppLogger.swift.
        AppCoreLog.logger = SentryAppCoreLogger()

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
            ContentView(tabManager: tabManager, errorPresenter: errorPresenter)
                .frame(minWidth: 600, minHeight: 400)
                .onAppear {
                    // ⌃Tab / ⌃⇧Tab tab cycling (MV-009) — pre-dispatch NSEvent monitor,
                    // NOT a menu key equivalent. See installTabCycleMonitor for NV-2.
                    tabManager.installTabCycleMonitor()

                    let args = CommandLine.arguments
                    if args.count > 1 {
                        // CLI argument takes precedence over auto-reopen
                        let path = args[1]
                        if FileManager.default.fileExists(atPath: path) {
                            tabManager.openFile(URL(fileURLWithPath: path))
                        }
                    } else if let session = TabSessionStore.loadSession(), !session.openPaths.isEmpty {
                        // MV-001: reopen EVERY tab that was open at quit, in the same
                        // order, then reselect the one that was frontmost. Previously
                        // only a single "last opened file" path was ever persisted, so
                        // this branch used to be able to restore at most one tab.
                        for path in session.openPaths {
                            tabManager.openFile(URL(fileURLWithPath: path))
                        }
                        if let idx = session.selectedIndex, idx >= 0, idx < tabManager.tabs.count {
                            tabManager.selectedTabID = tabManager.tabs[idx].id
                        }
                    } else if let lastURL = RecentFilesManager.shared.lastOpenedURL {
                        // Fallback for a first launch after upgrading — no multi-tab
                        // session was ever recorded yet, but a legacy single-file
                        // "last opened" record may still exist.
                        tabManager.openFile(lastURL)
                    }

                    // Defer window sizing to next run loop — window may not exist yet during onAppear.
                    // Always apply to override macOS state restoration which saves the previous frame.
                    DispatchQueue.main.async {
                        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible || $0.isKeyWindow }) ?? NSApplication.shared.windows.first else { return }
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
                        tabManager.openFile(url)
                    }
                }
                .onReceive(appDelegate.$pendingFilePath) { path in
                    if let path = path {
                        tabManager.openFile(URL(fileURLWithPath: path))
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(Strings.openFile) { openFile() }
                    .keyboardShortcut("o", modifiers: .command)

                // ⌘T opens a true untitled scratch tab (MV-007), no longer an alias
                // for ⌘O's file picker — that made ⌘T redundant with ⌘O. ⌘O below
                // stays the file picker, so the two are now genuinely distinct.
                Button("New Tab") { tabManager.newUntitledTab() }
                    .keyboardShortcut("t", modifiers: .command)

                Menu(Strings.openRecent) {
                    OpenRecentMenuItems { path in tabManager.openFile(URL(fileURLWithPath: path)) }
                }

                Button("Select Next Tab") { tabManager.selectNext() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Select Previous Tab") { tabManager.selectPrevious() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])

                // ⌃Tab / ⌃⇧Tab tab cycling (MV-009) deliberately has NO menu item here.
                // NV-2 ANSWERED (in-app, 2026-07-03): SwiftUI menu equivalents bound to
                // KeyEquivalent.tab lose to WKWebView, which consumes Tab as element-focus
                // navigation before menu matching runs. The working mechanism for Tab-key
                // shortcuts specifically is a pre-dispatch local NSEvent monitor — see
                // TabManager.installTabCycleMonitor(), installed from onAppear above.
                // Non-Tab shortcuts stay on menu key equivalents.

                Button(Strings.closeFile) {
                    NotificationCenter.default.post(name: .closeFile, object: nil)
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
            // Find bar commands — post notifications so ContentView's @StateObject
            // FindBarController can respond. Direct reference isn't possible here
            // because App-level CommandGroups can't hold references to view @StateObjects.
            // Single-window app: notifications always reach the one ContentView.
            CommandGroup(after: .textEditing) {
                Section {
                    Button(Strings.find) {
                        NotificationCenter.default.post(name: .openFindBar, object: nil)
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    Button(Strings.findNext) {
                        NotificationCenter.default.post(name: .findBarNext, object: nil)
                    }
                    .keyboardShortcut("g", modifiers: .command)
                    Button(Strings.findPrevious) {
                        NotificationCenter.default.post(name: .findBarPrev, object: nil)
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
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
            tabManager.openFile(url)
        }
    }
}

/// Renders "Open Recent" submenu items backed by RecentFilesManager.
/// Placed in `CommandGroup(replacing: .openRecent)`.
private struct OpenRecentMenuItems: View {
    let onOpen: (String) -> Void
    @ObservedObject private var recents = RecentFilesManager.shared

    var body: some View {
        if recents.recentFileURLs.isEmpty {
            Text("No Recent Items").disabled(true)
        } else {
            ForEach(recents.recentFileURLs, id: \.path) { url in
                Button(url.lastPathComponent) { onOpen(url.path) }
            }
            Divider()
            Button("Clear Menu") { recents.clearAll() }
        }
    }
}

extension Notification.Name {
    static let closeFile = Notification.Name("com.markview.closeFile")
    static let exportHTML = Notification.Name("exportHTML")
    static let exportPDF = Notification.Name("exportPDF")
    static let saveDocument = Notification.Name("saveDocument")
    // Find bar — ContentView listens on these to drive FindBarController.
    // NotificationCenter is used here because MarkViewApp's CommandGroup cannot
    // hold a direct reference to ContentView's @StateObject.
    static let openFindBar = Notification.Name("com.markview.openFindBar")
    static let findBarNext = Notification.Name("com.markview.findBarNext")
    static let findBarPrev = Notification.Name("com.markview.findBarPrev")
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
