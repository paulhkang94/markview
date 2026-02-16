import SwiftUI

/// A monospaced text editor for markdown content.
struct EditorView: View {
    @Binding var text: String
    let onChange: (String) -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TextEditor(text: $text)
            .font(.custom(settings.editorFontFamily, size: settings.editorFontSize).monospaced())
            .scrollContentBackground(.hidden)
            .padding(8)
            .onChange(of: text) { newValue in
                onChange(newValue)
            }
    }
}
