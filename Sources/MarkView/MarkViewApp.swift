import SwiftUI

@main
struct MarkViewApp: App {
    @State private var filePath: String?

    var body: some Scene {
        WindowGroup {
            ContentView(initialFilePath: filePath)
                .frame(minWidth: 600, minHeight: 400)
                .onAppear {
                    let args = CommandLine.arguments
                    if args.count > 1 {
                        let path = args[1]
                        if FileManager.default.fileExists(atPath: path) {
                            filePath = path
                        }
                    }
                }
                .onOpenURL { url in
                    if url.isFileURL {
                        filePath = url.path
                    }
                }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(Strings.openFile) { openFile() }
                    .keyboardShortcut("o", modifiers: .command)
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
}
