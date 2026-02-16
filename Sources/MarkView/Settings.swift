import SwiftUI

// MARK: - Setting Enums

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}

enum PreviewWidth: String, CaseIterable, Identifiable {
    case narrow, medium, wide, full
    var id: String { rawValue }
    var label: String {
        switch self {
        case .narrow: return "Narrow (700px)"
        case .medium: return "Medium (900px)"
        case .wide: return "Wide (1200px)"
        case .full: return "Full Width"
        }
    }
    var cssValue: String {
        switch self {
        case .narrow: return "700px"
        case .medium: return "900px"
        case .wide: return "1200px"
        case .full: return "100%"
        }
    }
}

enum TabBehavior: String, CaseIterable, Identifiable {
    case twoSpaces, fourSpaces, tab
    var id: String { rawValue }
    var label: String {
        switch self {
        case .twoSpaces: return "2 Spaces"
        case .fourSpaces: return "4 Spaces"
        case .tab: return "Tab"
        }
    }
    var insertionString: String {
        switch self {
        case .twoSpaces: return "  "
        case .fourSpaces: return "    "
        case .tab: return "\t"
        }
    }
}

// MARK: - Settings Model

/// Persistent user settings stored in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Existing settings
    @AppStorage("editorFontSize") var editorFontSize: Double = 14
    @AppStorage("previewFontSize") var previewFontSize: Double = 16
    @AppStorage("editorLineSpacing") var editorLineSpacing: Double = 1.4
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = false
    @AppStorage("wordWrap") var wordWrap: Bool = true
    @AppStorage("autoSave") var autoSave: Bool = false
    @AppStorage("autoSaveInterval") var autoSaveInterval: Double = 5.0
    @AppStorage("metricsOptIn") var metricsOptIn: Bool = false

    // New settings
    @AppStorage("theme") var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("previewWidth") var previewWidthRaw: String = PreviewWidth.medium.rawValue
    @AppStorage("editorFontFamily") var editorFontFamily: String = "SF Mono"
    @AppStorage("tabBehavior") var tabBehaviorRaw: String = TabBehavior.fourSpaces.rawValue
    @AppStorage("spellCheck") var spellCheck: Bool = true
    @AppStorage("defaultOpenDir") var defaultOpenDir: String = ""
    @AppStorage("windowRestore") var windowRestore: Bool = true
    @AppStorage("lineHighlight") var lineHighlight: Bool = false
    @AppStorage("minimapEnabled") var minimapEnabled: Bool = false
    @AppStorage("formatOnSave") var formatOnSave: Bool = true

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }

    var previewWidth: PreviewWidth {
        get { PreviewWidth(rawValue: previewWidthRaw) ?? .medium }
        set { previewWidthRaw = newValue.rawValue }
    }

    var tabBehavior: TabBehavior {
        get { TabBehavior(rawValue: tabBehaviorRaw) ?? .fourSpaces }
        set { tabBehaviorRaw = newValue.rawValue }
    }

    var defaultOpenDirURL: URL? {
        get { defaultOpenDir.isEmpty ? nil : URL(fileURLWithPath: defaultOpenDir) }
        set { defaultOpenDir = newValue?.path ?? "" }
    }
}

// MARK: - Settings UI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        TabView {
            editorTab
                .tabItem { Label(Strings.editorTab, systemImage: "square.and.pencil") }

            previewTab
                .tabItem { Label(Strings.previewTab, systemImage: "doc.richtext") }

            generalTab
                .tabItem { Label(Strings.generalTab, systemImage: "gear") }
        }
        .frame(width: 450, height: 350)
        .padding()
    }

    private var editorTab: some View {
        Form {
            Section(Strings.fontSection) {
                Picker(Strings.fontFamily, selection: $settings.editorFontFamily) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Courier").tag("Courier")
                    Text("Monaco").tag("Monaco")
                }

                HStack {
                    Text(Strings.fontSize)
                    Slider(value: $settings.editorFontSize, in: 10...24, step: 1)
                        .accessibilityValue(Strings.fontSizeA11y(Int(settings.editorFontSize)))
                    Text("\(Int(settings.editorFontSize))pt")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                HStack {
                    Text(Strings.lineSpacing)
                    Slider(value: $settings.editorLineSpacing, in: 1.0...2.0, step: 0.1)
                        .accessibilityValue(String(format: "%.1f", settings.editorLineSpacing))
                    Text(String(format: "%.1f", settings.editorLineSpacing))
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }
            .accessibilityElement(children: .contain)

            Section(Strings.behaviorSection) {
                Toggle(Strings.wordWrap, isOn: $settings.wordWrap)
                Toggle(Strings.spellCheck, isOn: $settings.spellCheck)
                Toggle(Strings.highlightCurrentLine, isOn: $settings.lineHighlight)
                Toggle(Strings.showMinimap, isOn: $settings.minimapEnabled)
                Toggle(Strings.formatOnSave, isOn: $settings.formatOnSave)
                    .help(Strings.formatOnSaveHint)

                Picker(Strings.tabBehavior, selection: Binding(
                    get: { settings.tabBehavior },
                    set: { settings.tabBehavior = $0 }
                )) {
                    ForEach(TabBehavior.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
            }
        }
    }

    private var previewTab: some View {
        Form {
            Section(Strings.fontSection) {
                HStack {
                    Text(Strings.fontSize)
                    Slider(value: $settings.previewFontSize, in: 12...24, step: 1)
                        .accessibilityValue(Strings.fontSizeA11y(Int(settings.previewFontSize)))
                    Text("\(Int(settings.previewFontSize))pt")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
            .accessibilityElement(children: .contain)

            Section(Strings.layoutSection) {
                Picker(Strings.previewWidth, selection: Binding(
                    get: { settings.previewWidth },
                    set: { settings.previewWidth = $0 }
                )) {
                    ForEach(PreviewWidth.allCases) { width in
                        Text(width.label).tag(width)
                    }
                }
            }

            Section(Strings.themeSection) {
                Picker(Strings.appearance, selection: Binding(
                    get: { settings.theme },
                    set: { settings.theme = $0 }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
            }
        }
    }

    private var generalTab: some View {
        Form {
            Section(Strings.autoSaveSection) {
                Toggle(Strings.enableAutoSave, isOn: $settings.autoSave)
                if settings.autoSave {
                    HStack {
                        Text(Strings.interval)
                        Slider(value: $settings.autoSaveInterval, in: 1...30, step: 1)
                            .accessibilityValue(Strings.autoSaveIntervalA11y(Int(settings.autoSaveInterval)))
                        Text("\(Int(settings.autoSaveInterval))s")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
            }
            .accessibilityElement(children: .contain)

            Section(Strings.windowSection) {
                Toggle(Strings.restoreLastFile, isOn: $settings.windowRestore)
            }

            Section(Strings.privacySection) {
                Toggle(Strings.metricsOptIn, isOn: $settings.metricsOptIn)
                Text(Strings.metricsDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
