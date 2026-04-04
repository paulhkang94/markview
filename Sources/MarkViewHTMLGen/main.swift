import Foundation
import MarkViewCore

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: MarkViewHTMLGen <input.md> [output.html]\n", stderr)
    exit(1)
}
do {
    let markdown = try String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), encoding: .utf8)
    let html = HTMLPipeline.assembleFullDocument(from: markdown)
    if CommandLine.arguments.count > 2 {
        try html.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
    } else {
        print(html)
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
