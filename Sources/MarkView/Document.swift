import SwiftUI
import Combine

/// Represents an open markdown document with content tracking and dirty state.
@MainActor
final class Document: ObservableObject {
    @Published var content: String
    @Published var isDirty: Bool = false
    @Published var filePath: String?

    var fileName: String {
        guard let path = filePath else { return "Untitled" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var title: String {
        isDirty ? "\(fileName) — Edited" : fileName
    }

    private var originalContent: String

    init(filePath: String? = nil) {
        self.filePath = filePath
        if let path = filePath, let text = try? String(contentsOfFile: path, encoding: .utf8) {
            self.content = text
            self.originalContent = text
        } else {
            self.content = ""
            self.originalContent = ""
        }
    }

    func loadFromDisk() {
        guard let path = filePath,
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        content = text
        originalContent = text
        isDirty = false
    }

    func save() throws {
        guard let path = filePath else { return }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        originalContent = content
        isDirty = false
    }

    func contentDidChange(_ newContent: String) {
        content = newContent
        isDirty = newContent != originalContent
    }

    /// Called when the file changes externally.
    /// Returns true if reload happened, false if editor is dirty (needs user decision).
    func handleExternalChange() -> Bool {
        if !isDirty {
            loadFromDisk()
            return true
        }
        return false // Caller should prompt user
    }
}
