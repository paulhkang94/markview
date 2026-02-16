import SwiftUI
import MarkViewCore

/// Bottom status bar showing document stats and file info.
struct StatusBarView: View {
    let content: String
    let filePath: String?
    let isDirty: Bool
    let lintWarnings: Int
    let lintErrors: Int
    let lintDiagnostics: [LintDiagnostic]
    var onFixAll: (() -> Void)?

    @State private var showLintPopover = false

    init(content: String, filePath: String?, isDirty: Bool, lintWarnings: Int = 0, lintErrors: Int = 0, lintDiagnostics: [LintDiagnostic] = [], onFixAll: (() -> Void)? = nil) {
        self.content = content
        self.filePath = filePath
        self.isDirty = isDirty
        self.lintWarnings = lintWarnings
        self.lintErrors = lintErrors
        self.lintDiagnostics = lintDiagnostics
        self.onFixAll = onFixAll
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
                    .help(Strings.unsavedChanges)
                    .accessibilityLabel(Strings.unsavedA11yLabel)
            }

            Text(Strings.words(wordCount))
                .accessibilityLabel(Strings.wordsA11y(wordCount))
            Text(Strings.chars(charCount))
                .accessibilityLabel(Strings.charsA11y(charCount))
            Text(Strings.lines(lineCount))
                .accessibilityLabel(Strings.linesA11y(lineCount))
            Text(readingTime)
                .accessibilityLabel(Strings.readingTimeA11y(readingTime))

            if lintErrors > 0 || lintWarnings > 0 {
                Divider().frame(height: 12)

                Button {
                    showLintPopover.toggle()
                } label: {
                    HStack(spacing: 6) {
                        if lintErrors > 0 {
                            Label("\(lintErrors)", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        if lintWarnings > 0 {
                            Label("\(lintWarnings)", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(Strings.lintClickHint)
                .accessibilityLabel(Strings.lintA11yLabel(errors: lintErrors, warnings: lintWarnings))
                .accessibilityHint(Strings.lintClickHint)
                .popover(isPresented: $showLintPopover, arrowEdge: .top) {
                    LintPopoverView(diagnostics: lintDiagnostics, onFixAll: onFixAll)
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

/// Popover showing lint diagnostic details.
struct LintPopoverView: View {
    let diagnostics: [LintDiagnostic]
    var onFixAll: (() -> Void)?

    private var hasFixableIssues: Bool {
        diagnostics.contains { MarkdownLinter.autoFixableRules.contains($0.rule) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(Strings.lintPopoverTitle)
                    .font(.headline)
                Spacer()
                if hasFixableIssues, let onFixAll = onFixAll {
                    Button(action: onFixAll) {
                        Label(Strings.lintFixAll, systemImage: "wand.and.stars")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(Strings.lintFixAllHint)
                }
                Text(Strings.lintDiagnosticCount(diagnostics.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            // Diagnostic list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        LintDiagnosticRow(diagnostic: diagnostic)
                        Divider().padding(.leading, 32)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 400)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Strings.lintPopoverA11yLabel)
    }
}

/// Single diagnostic row in the lint popover.
struct LintDiagnosticRow: View {
    let diagnostic: LintDiagnostic

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: diagnostic.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(diagnostic.severity == .error ? .red : .orange)
                .font(.system(size: 12))
                .frame(width: 16, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostic.message)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(Strings.lintLocation(line: diagnostic.line, column: diagnostic.column))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text(diagnostic.rule.rawValue)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(3)
                }

                if let fix = diagnostic.fix {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                        Text(fix)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Strings.lintDiagnosticA11y(diagnostic))
    }
}
