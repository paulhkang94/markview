import SwiftUI

/// A monospaced text editor for markdown content.
struct EditorView: View {
    @Binding var text: String
    let onChange: (String) -> Void

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .onChange(of: text) { newValue in
                onChange(newValue)
            }
    }
}
