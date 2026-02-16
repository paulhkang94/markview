import SwiftUI
import MarkViewCore

/// Bottom status bar showing document stats and file info.
struct StatusBarView: View {
    let content: String
    let filePath: String?
    let isDirty: Bool
    let lintWarnings: Int
    let lintErrors: Int

    init(content: String, filePath: String?, isDirty: Bool, lintWarnings: Int = 0, lintErrors: Int = 0) {
        self.content = content
        self.filePath = filePath
        self.isDirty = isDirty
        self.lintWarnings = lintWarnings
        self.lintErrors = lintErrors
    }

    private var wordCount: Int {
        content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var charCount: Int {
        content.count
    }

    private var lineCount: Int {
        content.isEmpty ? 0 : content.components(separatedBy: .newlines).count
    }

    private var readingTime: String {
        let minutes = max(1, wordCount / 200)
        return "\(minutes) min read"
    }

    var body: some View {
        HStack(spacing: 16) {
            if isDirty {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .help("Unsaved changes")
            }

            Text("\(wordCount) words")
            Text("\(charCount) chars")
            Text("\(lineCount) lines")
            Text(readingTime)

            if lintErrors > 0 || lintWarnings > 0 {
                Divider().frame(height: 12)
                if lintErrors > 0 {
                    Label("\(lintErrors)", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                if lintWarnings > 0 {
                    Label("\(lintWarnings)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            if let path = filePath {
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
