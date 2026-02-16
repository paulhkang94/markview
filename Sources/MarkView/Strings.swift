import Foundation
import MarkViewCore

/// Centralized user-facing strings. Swap to NSLocalizedString when adding languages.
enum Strings {
    // MARK: - Menu Items
    static let openFile = "Open..."
    static let exportHTML = "Export HTML..."
    static let exportPDF = "Export PDF..."
    static let increaseFontSize = "Increase Font Size"
    static let decreaseFontSize = "Decrease Font Size"
    static let resetFontSize = "Reset Font Size"

    // MARK: - Drop Target
    static let dropPrompt = "Drop a Markdown file here"
    static let dropSubprompt = "or use File → Open (⌘O)"

    // MARK: - Editor Toggle
    static let hideEditor = "Hide Editor (⌘E)"
    static let showEditor = "Show Editor (⌘E)"

    // MARK: - External Change Alert
    static let fileChanged = "File Changed"
    static let reload = "Reload"
    static let keepMine = "Keep Mine"
    static let externalChangeMessage = "This file has been modified externally. Reload to see changes, or keep your edits?"

    // MARK: - Status Bar
    static func words(_ count: Int) -> String { "\(count) words" }
    static func chars(_ count: Int) -> String { "\(count) chars" }
    static func lines(_ count: Int) -> String { "\(count) lines" }
    static let unsavedChanges = "Unsaved changes"

    // MARK: - Settings Tabs
    static let editorTab = "Editor"
    static let previewTab = "Preview"
    static let generalTab = "General"

    // MARK: - Settings: Editor
    static let fontSection = "Font"
    static let fontFamily = "Family"
    static let fontSize = "Size"
    static let lineSpacing = "Line Spacing"
    static let behaviorSection = "Behavior"
    static let wordWrap = "Word Wrap"
    static let spellCheck = "Spell Check"
    static let highlightCurrentLine = "Highlight Current Line"
    static let showMinimap = "Show Minimap"
    static let tabBehavior = "Tab Behavior"

    // MARK: - Settings: Preview
    static let layoutSection = "Layout"
    static let previewWidth = "Preview Width"
    static let themeSection = "Theme"
    static let appearance = "Appearance"

    // MARK: - Settings: General
    static let autoSaveSection = "Auto Save"
    static let enableAutoSave = "Enable Auto Save"
    static let interval = "Interval"
    static let windowSection = "Window"
    static let restoreLastFile = "Restore last file on launch"
    static let privacySection = "Privacy"
    static let metricsOptIn = "Opt in to anonymous usage metrics"
    static let metricsDescription = "Helps improve MarkView. No personal data or file contents are ever collected."

    // MARK: - Accessibility
    static let hideEditorPanel = "Hide editor panel"
    static let showEditorPanel = "Show editor panel"
    static let dropA11yLabel = "Drop a markdown file to open"
    static let dropA11yHint = "Or use File, Open from the menu bar"
    static let unsavedA11yLabel = "Document has unsaved changes"
    static let markdownEditor = "Markdown editor"
    static let markdownPreview = "Markdown preview"
    static let exportHTMLA11yHint = "Save the rendered HTML to a file"
    static let exportPDFA11yHint = "Save the rendered content as a PDF file"
    static func readingTimeA11y(_ time: String) -> String { "Estimated reading time: \(time)" }
    static func wordsA11y(_ count: Int) -> String { "\(count) words" }
    static func charsA11y(_ count: Int) -> String { "\(count) characters" }
    static func linesA11y(_ count: Int) -> String { "\(count) lines" }
    static func fontSizeA11y(_ size: Int) -> String { "\(size) points" }
    static func autoSaveIntervalA11y(_ seconds: Int) -> String { "\(seconds) seconds" }

    // MARK: - Save & Format
    static let saveDocument = "Save"
    static let formatOnSave = "Format on Save"
    static let formatOnSaveHint = "Auto-fix trailing whitespace and add missing blank lines when saving"

    // MARK: - Find Menu
    static let find = "Find..."
    static let findAndReplace = "Find and Replace..."
    static let findNext = "Find Next"
    static let findPrevious = "Find Previous"
    static let useSelectionForFind = "Use Selection for Find"

    // MARK: - Lint Popover
    static let lintClickHint = "Click to view lint diagnostics"
    static let lintFixAll = "Fix All"
    static let lintFixAllHint = "Auto-fix trailing whitespace and missing blank lines"
    static let lintPopoverTitle = "Diagnostics"
    static let lintPopoverA11yLabel = "Lint diagnostics panel"
    static func lintA11yLabel(errors: Int, warnings: Int) -> String {
        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) \(errors == 1 ? "error" : "errors")") }
        if warnings > 0 { parts.append("\(warnings) \(warnings == 1 ? "warning" : "warnings")") }
        return parts.joined(separator: ", ")
    }
    static func lintDiagnosticCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "issue" : "issues")"
    }
    static func lintLocation(line: Int, column: Int) -> String {
        "L\(line):\(column)"
    }
    static func lintDiagnosticA11y(_ d: LintDiagnostic) -> String {
        var label = "\(d.severity.rawValue): \(d.message) at line \(d.line)"
        if let fix = d.fix { label += ". Suggestion: \(fix)" }
        return label
    }

    // MARK: - Document
    static let untitled = "Untitled"
}
