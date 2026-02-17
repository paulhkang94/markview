@preconcurrency import ApplicationServices
import Foundation

/// High-level E2E operations built on AXHelper + AppController.
struct E2EHelpers {
    let app: AppController

    // MARK: - Element Finders

    /// Find the editor text area (NSTextView exposed as AXTextArea).
    func findEditor(in window: AXUIElement) -> AXUIElement? {
        AXHelper.findElement(root: window, role: kAXTextAreaRole)
    }

    /// Find the web preview (WKWebView exposed as AXWebArea or AXGroup).
    func findPreview(in window: AXUIElement) -> AXUIElement? {
        // WKWebView typically exposes as AXWebArea
        if let webArea = AXHelper.findElement(root: window, role: "AXWebArea") {
            return webArea
        }
        // Fallback: look for AXGroup containing web content
        return AXHelper.findElement(root: window, role: "AXGroup", identifier: "preview")
    }

    /// Find the toolbar.
    func findToolbar(in window: AXUIElement) -> AXUIElement? {
        AXHelper.findElement(root: window, role: kAXToolbarRole)
    }

    /// Find the status bar (bottom bar with word count, lint info).
    func findStatusBar(in window: AXUIElement) -> AXUIElement? {
        // Status bar is rendered as the last AXGroup in the window hierarchy
        let groups = AXHelper.allElements(root: window, role: kAXGroupRole)
        // Look for a group containing word count text
        for group in groups.reversed() {
            let staticTexts = AXHelper.allElements(root: group, role: kAXStaticTextRole)
            for text in staticTexts {
                if let val = AXHelper.value(text), val.contains("words") {
                    return group
                }
            }
        }
        return nil
    }

    /// Find the error banner overlay.
    func findErrorBanner(in window: AXUIElement) -> AXUIElement? {
        // ErrorBanner contains text like "Save failed" or "Auto-save failed"
        let groups = AXHelper.allElements(root: window, role: kAXGroupRole)
        for group in groups {
            let staticTexts = AXHelper.allElements(root: group, role: kAXStaticTextRole)
            for text in staticTexts {
                if let val = AXHelper.value(text),
                   (val.contains("failed") || val.contains("error") || val.contains("Error")) {
                    return group
                }
            }
        }
        return nil
    }

    /// Find the drop target (shown when no file is loaded).
    func findDropTarget(in window: AXUIElement) -> AXUIElement? {
        // Drop target has accessibility label "Drop a Markdown file to preview"
        AXHelper.findElement(root: window, role: kAXGroupRole, identifier: "Drop a Markdown file to preview")
    }

    /// Check if the drop target / "no file" state is showing.
    func isDropTargetVisible(in window: AXUIElement) -> Bool {
        // When no file is loaded, there's no AXTextArea and no AXWebArea
        let hasEditor = findEditor(in: window) != nil
        let hasPreview = findPreview(in: window) != nil
        // If neither editor nor preview is visible, it's likely the drop target
        if !hasEditor && !hasPreview { return true }
        // Also check for the drop target text
        if findDropTarget(in: window) != nil { return true }
        // Check for static text containing "Drop"
        let texts = AXHelper.allElements(root: window, role: kAXStaticTextRole)
        for text in texts {
            if let val = AXHelper.value(text), val.contains("Drop") { return true }
        }
        return false
    }

    // MARK: - High-Level Actions

    /// Type text into the editor, focusing it first.
    func typeInEditor(_ text: String, window: AXUIElement) throws {
        guard let editor = findEditor(in: window) else {
            throw AXHelper.AXError.elementNotFound("editor AXTextArea")
        }
        AXHelper.setFocus(editor)
        Thread.sleep(forTimeInterval: 0.1)
        AXHelper.typeText(text)
    }

    /// Get the window title.
    func windowTitle(_ window: AXUIElement) -> String? {
        AXHelper.title(window)
    }

    /// Get the editor content.
    func editorContent(_ window: AXUIElement) -> String? {
        guard let editor = findEditor(in: window) else { return nil }
        return AXHelper.value(editor)
    }

    // MARK: - Menu Invocation via AppleScript

    /// Invoke a menu item via AppleScript (e.g. "File > Open...").
    /// More reliable than traversing AX menu hierarchy.
    func invokeMenu(_ menuPath: String) {
        let parts = menuPath.components(separatedBy: " > ")
        guard parts.count >= 2 else { return }

        let menu = parts[0]
        let item = parts[1]

        let script = """
        tell application "System Events"
            tell process "MarkView"
                click menu item "\(item)" of menu "\(menu)" of menu bar 1
            end tell
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        Thread.sleep(forTimeInterval: 0.3)
    }

    // MARK: - File Helpers

    /// Create a temporary markdown file with the given content. Returns the file path.
    func createTempMarkdown(_ content: String, name: String = "e2e-test") -> String {
        let dir = NSTemporaryDirectory() + "markview-e2e/"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "\(name)-\(UUID().uuidString.prefix(8)).md"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// Create a read-only temporary markdown file for testing permission errors.
    func createReadOnlyMarkdown(_ content: String) -> String {
        let path = createTempMarkdown(content, name: "readonly")
        // Remove write permission
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: path
        )
        return path
    }

    /// Clean up all temp files.
    func cleanupTempFiles() {
        let dir = NSTemporaryDirectory() + "markview-e2e/"
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - Lint Helpers

    /// Check if the status bar shows lint warnings/errors.
    func statusBarHasLintIssues(in window: AXUIElement) -> Bool {
        guard let statusBar = findStatusBar(in: window) else { return false }
        let buttons = AXHelper.allElements(root: statusBar, role: kAXButtonRole)
        // Lint button exists when there are warnings/errors
        return !buttons.isEmpty
    }

    /// Get text content from all static text elements in a container.
    func allStaticText(in element: AXUIElement) -> [String] {
        AXHelper.allElements(root: element, role: kAXStaticTextRole)
            .compactMap { AXHelper.value($0) }
    }

    // MARK: - Alert Helpers

    /// Find an alert/sheet (conflict dialog).
    func findAlert(in window: AXUIElement) -> AXUIElement? {
        AXHelper.findElement(root: window, role: kAXSheetRole)
            ?? AXHelper.findElement(root: window, role: "AXDialog")
    }

    /// Find a button by title within an element.
    func findButton(in element: AXUIElement, title: String) -> AXUIElement? {
        AXHelper.findElement(root: element, role: kAXButtonRole, title: title)
    }

    // MARK: - Screenshot (Debugging)

    func captureScreenshot(label: String) {
        let dir = NSTemporaryDirectory() + "markview-e2e/screenshots/"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "\(label)-\(Int(Date().timeIntervalSince1970)).png"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", path]
        try? task.run()
        task.waitUntilExit()
        if FileManager.default.fileExists(atPath: path) {
            print("    Screenshot: \(path)")
        }
    }
}
