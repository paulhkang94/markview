import AppKit
import SwiftUI

@MainActor
struct WindowFrameAutosave: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowFrameAutosaveView {
        WindowFrameAutosaveView(name: "MarkView.MainWindow")
    }

    func updateNSView(_ nsView: WindowFrameAutosaveView, context: Context) {
        nsView.configureWindowIfNeeded()
    }
}

@MainActor
final class WindowFrameAutosaveView: NSView {
    private let name: String
    private weak var configuredWindow: NSWindow?

    init(name: String) {
        self.name = name
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowIfNeeded()
    }

    func configureWindowIfNeeded() {
        guard let window, window !== configuredWindow else { return }
        // AppKit reloads a saved frame when the autosave name is assigned.
        // Bind to this view's owner and never replay restoration on later updates.
        if window.frameAutosaveName == name || window.setFrameAutosaveName(name) {
            configuredWindow = window
        }
    }
}
