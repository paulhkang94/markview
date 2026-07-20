import SwiftUI
import MarkViewAppCore

/// Horizontal scrollable tab bar. Always visible — even with one tab open.
/// Each pill shows filename + close button. Active tab is highlighted.
/// Dirty indicator (filled circle) appears in the pill when file has unsaved changes.
struct TabBarView: View {
    @ObservedObject var tabManager: TabManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(tabManager.tabs) { tab in
                    TabPillView(
                        tab: tab,
                        isSelected: tab.id == tabManager.selectedTabID,
                        onSelect: { tabManager.selectedTabID = tab.id },
                        onClose: { tabManager.closeTab(tab.id) }
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .frame(height: 34)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct TabPillView: View {
    @ObservedObject var tab: TabState
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            // Dirty indicator — small dot to the left of filename
            Circle()
                .fill(Color.secondary)
                .frame(width: 5, height: 5)
                .opacity(tab.viewModel.isDirty ? 1 : 0)

            Text(tab.displayName)
                .lineLimit(1)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)

            // Close button — always visible on selected tab, on-hover for others
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isSelected || isHovered ? 1 : 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected
                      ? Color(.selectedContentBackgroundColor).opacity(0.15)
                      : (isHovered ? Color(.selectedContentBackgroundColor).opacity(0.07) : Color.clear))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(.separatorColor).opacity(0.5), lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}
