import SwiftUI

/// Persistent user settings stored in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("editorFontSize") var editorFontSize: Double = 14
    @AppStorage("previewFontSize") var previewFontSize: Double = 16
    @AppStorage("editorLineSpacing") var editorLineSpacing: Double = 1.4
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = false
    @AppStorage("wordWrap") var wordWrap: Bool = true
    @AppStorage("autoSave") var autoSave: Bool = false
    @AppStorage("autoSaveInterval") var autoSaveInterval: Double = 5.0
    @AppStorage("metricsOptIn") var metricsOptIn: Bool = false
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        TabView {
            editorTab
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }

            previewTab
                .tabItem { Label("Preview", systemImage: "doc.richtext") }

            generalTab
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 450, height: 300)
        .padding()
    }

    private var editorTab: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Size")
                    Slider(value: $settings.editorFontSize, in: 10...24, step: 1)
                    Text("\(Int(settings.editorFontSize))pt")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                HStack {
                    Text("Line Spacing")
                    Slider(value: $settings.editorLineSpacing, in: 1.0...2.0, step: 0.1)
                    Text(String(format: "%.1f", settings.editorLineSpacing))
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }

            Section("Behavior") {
                Toggle("Word Wrap", isOn: $settings.wordWrap)
            }
        }
    }

    private var previewTab: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Size")
                    Slider(value: $settings.previewFontSize, in: 12...24, step: 1)
                    Text("\(Int(settings.previewFontSize))pt")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
        }
    }

    private var generalTab: some View {
        Form {
            Section("Auto Save") {
                Toggle("Enable Auto Save", isOn: $settings.autoSave)
                if settings.autoSave {
                    HStack {
                        Text("Interval")
                        Slider(value: $settings.autoSaveInterval, in: 1...30, step: 1)
                        Text("\(Int(settings.autoSaveInterval))s")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
            }

            Section("Privacy") {
                Toggle("Opt in to anonymous usage metrics", isOn: $settings.metricsOptIn)
                Text("Helps improve MarkView. No personal data or file contents are ever collected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
