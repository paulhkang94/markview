import SwiftUI

// Moved from the Xcode app target to MarkViewAppCore (mar-033 Tier-B, mar-038).
// SettingsView (the Form-based UI) stays in the app target's Settings.swift as a
// thin shell and imports these types from here — same PR1 split as
// StatusBarStatsModel (model in the library) / StatusBarView (view stays app-side).

// MARK: - Setting Enums

public enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, system
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}

public enum PreviewWidth: String, CaseIterable, Identifiable {
    case narrow, medium, wide, full
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .narrow: return "Narrow (700px)"
        case .medium: return "Medium (900px)"
        case .wide: return "Wide (1200px)"
        case .full: return "Full Width"
        }
    }
    public var cssValue: String {
        switch self {
        case .narrow: return "700px"
        case .medium: return "900px"
        case .wide: return "1200px"
        case .full: return "100%"
        }
    }
}

public enum TabBehavior: String, CaseIterable, Identifiable {
    case twoSpaces, fourSpaces, tab
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .twoSpaces: return "2 Spaces"
        case .fourSpaces: return "4 Spaces"
        case .tab: return "Tab"
        }
    }
    public var insertionString: String {
        switch self {
        case .twoSpaces: return "  "
        case .fourSpaces: return "    "
        case .tab: return "\t"
        }
    }
}

// MARK: - Settings Model

/// Persistent user settings stored in UserDefaults.
@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private init() {}

    // Existing settings
    @AppStorage("editorFontSize") public var editorFontSize: Double = 14
    @AppStorage("previewFontSize") public var previewFontSize: Double = 16
    @AppStorage("editorLineSpacing") public var editorLineSpacing: Double = 1.4
    @AppStorage("showLineNumbers") public var showLineNumbers: Bool = false
    @AppStorage("wordWrap") public var wordWrap: Bool = true
    @AppStorage("autoSave") public var autoSave: Bool = false
    @AppStorage("autoSaveInterval") public var autoSaveInterval: Double = 5.0
    @AppStorage("metricsOptIn") public var metricsOptIn: Bool = false

    // New settings
    @AppStorage("theme") public var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("previewWidth") public var previewWidthRaw: String = PreviewWidth.full.rawValue
    @AppStorage("editorFontFamily") public var editorFontFamily: String = "SF Mono"
    @AppStorage("tabBehavior") public var tabBehaviorRaw: String = TabBehavior.fourSpaces.rawValue
    @AppStorage("spellCheck") public var spellCheck: Bool = true
    @AppStorage("defaultOpenDir") public var defaultOpenDir: String = ""
    @AppStorage("windowRestore") public var windowRestore: Bool = true
    @AppStorage("lineHighlight") public var lineHighlight: Bool = false
    @AppStorage("minimapEnabled") public var minimapEnabled: Bool = false
    @AppStorage("formatOnSave") public var formatOnSave: Bool = true

    public var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }

    public var previewWidth: PreviewWidth {
        get { PreviewWidth(rawValue: previewWidthRaw) ?? .medium }
        set { previewWidthRaw = newValue.rawValue }
    }

    public var tabBehavior: TabBehavior {
        get { TabBehavior(rawValue: tabBehaviorRaw) ?? .fourSpaces }
        set { tabBehaviorRaw = newValue.rawValue }
    }

    public var defaultOpenDirURL: URL? {
        get { defaultOpenDir.isEmpty ? nil : URL(fileURLWithPath: defaultOpenDir) }
        set { defaultOpenDir = newValue?.path ?? "" }
    }
}
