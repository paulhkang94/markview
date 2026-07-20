import SwiftUI
import MarkViewAppCore

// AppTheme, PreviewWidth, TabBehavior, and the AppSettings model moved to
// MarkViewAppCore (mar-033 Tier-B, mar-038) — see Sources/MarkViewAppCore/AppSettings.swift.
// This file keeps only the Form-based settings UI, which stays app-target
// (SwiftUI View, not test-relevant logic).

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
