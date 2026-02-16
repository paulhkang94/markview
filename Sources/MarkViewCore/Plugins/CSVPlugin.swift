import Foundation

/// Plugin that renders CSV files as HTML tables.
public struct CSVPlugin: LanguagePlugin {
    public let supportedExtensions: Set<String> = ["csv", "tsv"]
    public let displayName = "CSV/TSV"
    public let requiresJSExecution = false

    public init() {}

    public func render(source: String) -> String {
        let lines = source.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "<p>Empty file</p>" }

        // Detect delimiter
        let delimiter: Character = source.contains("\t") ? "\t" : ","

        var html = "<table>\n<thead>\n<tr>\n"

        // Header row
        let headers = parseCSVRow(lines[0], delimiter: delimiter)
        for header in headers {
            html += "  <th>\(escapeHTML(header))</th>\n"
        }
        html += "</tr>\n</thead>\n<tbody>\n"

        // Data rows
        for i in 1..<lines.count {
            let cells = parseCSVRow(lines[i], delimiter: delimiter)
            html += "<tr>\n"
            for cell in cells {
                html += "  <td>\(escapeHTML(cell))</td>\n"
            }
            html += "</tr>\n"
        }

        html += "</tbody>\n</table>"
        return html
    }

    private func parseCSVRow(_ row: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for ch in row {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == delimiter && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
