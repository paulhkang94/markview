import SwiftUI
import MarkViewCore

/// Find bar overlay view. Floated above the status bar via .overlay(alignment: .bottom).
/// The parent (ContentView) owns the FindBarController as @StateObject and passes it here.
struct FindBarView: View {
    @ObservedObject var findBar: FindBarController

    @FocusState private var isTextFieldFocused: Bool
    @State private var showNoResultsBorder: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)

            // Query text field
            TextField(Strings.findBarPlaceholder, text: $findBar.query)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onSubmit { findBar.findNext() }
                .onChange(of: findBar.query) { newQuery in
                    findBar.onQueryChanged?(newQuery, findBar.caseSensitive)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(showNoResultsBorder ? Color.red : Color.clear, lineWidth: 1.5)
                )
                .onChange(of: findBar.noResults) { isNoResults in
                    guard isNoResults else { return }
                    showNoResultsBorder = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showNoResultsBorder = false
                        // Reset so the same query triggers again if user re-submits
                        findBar.noResults = false
                    }
                }
                .frame(minWidth: 140)

            // Match count label
            Text(Strings.findBarMatchCount(findBar.matchCount, findBar.matchCount))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
                .monospacedDigit()

            Divider()
                .frame(height: 16)

            // Case-sensitive toggle (Aa)
            Toggle(isOn: $findBar.caseSensitive) {
                Text("Aa")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help(Strings.findBarCaseSensitiveLabel)
            .accessibilityLabel(Strings.findBarCaseSensitiveA11y(findBar.caseSensitive))
            .onChange(of: findBar.caseSensitive) { _ in
                guard !findBar.query.isEmpty else { return }
                findBar.onQueryChanged?(findBar.query, findBar.caseSensitive)
            }

            // Previous match button
            Button {
                findBar.findPrev()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help(Strings.findBarPrevA11y)
            .accessibilityLabel(Strings.findBarPrevA11y)
            .disabled(findBar.query.isEmpty)
            .keyboardShortcut("g", modifiers: [.command, .shift])

            // Next match button
            Button {
                findBar.findNext()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help(Strings.findBarNextA11y)
            .accessibilityLabel(Strings.findBarNextA11y)
            .disabled(findBar.query.isEmpty)
            .keyboardShortcut("g", modifiers: .command)

            Divider()
                .frame(height: 16)

            // Done / close button
            Button(Strings.findBarClose) {
                findBar.hide()
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
}
