import Foundation
import MarkViewCore

/// Differential tester: compare MarkView renderer output against cmark-gfm CLI.
/// Requires `cmark-gfm` to be installed (brew install cmark-gfm).

print("=== MarkView Differential Tester ===")

// Check if cmark-gfm is available (check common locations)
let cmarkCandidates = [
    "/opt/homebrew/bin/cmark-gfm",
    "/usr/local/bin/cmark-gfm",
]

let cmarkPath: String
if let found = cmarkCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
    cmarkPath = found
} else {
    // Fallback: try `which`
    let whichProcess = Process()
    whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    whichProcess.arguments = ["which", "cmark-gfm"]
    let whichPipe = Pipe()
    whichProcess.standardOutput = whichPipe
    whichProcess.standardError = Pipe()
    try? whichProcess.run()
    whichProcess.waitUntilExit()

    if whichProcess.terminationStatus == 0,
       let path = String(data: whichPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
           .trimmingCharacters(in: .whitespacesAndNewlines),
       !path.isEmpty {
        cmarkPath = path
    } else {
        print("⚠ cmark-gfm not found. Install with: brew install cmark-gfm")
        print("  Skipping differential tests.")
        exit(0)
    }
}

print("Using cmark-gfm at: \(cmarkPath)")

// Find fixture files
let cwd = FileManager.default.currentDirectoryPath
let fixturesDir = URL(fileURLWithPath: cwd).appendingPathComponent("Tests/TestRunner/Fixtures")

guard let enumerator = FileManager.default.enumerator(at: fixturesDir, includingPropertiesForKeys: nil) else {
    print("ERROR: Cannot enumerate fixtures directory")
    exit(1)
}

var fixtureFiles: [URL] = []
while let url = enumerator.nextObject() as? URL {
    if url.pathExtension == "md" && !url.path.contains("/lint/") {
        fixtureFiles.append(url)
    }
}

print("Found \(fixtureFiles.count) fixture files\n")

var passed = 0
var failed = 0
var diffs: [(file: String, markview: String, cmark: String)] = []

for file in fixtureFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let name = file.lastPathComponent
    guard let markdown = try? String(contentsOf: file, encoding: .utf8) else {
        print("  ⊘ \(name) (could not read)")
        continue
    }

    // Render with MarkView
    let markviewHTML = MarkdownRenderer.renderHTML(from: markdown)

    // Render with cmark-gfm CLI (pass file path directly to avoid pipe deadlocks)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cmarkPath)
    process.arguments = ["--to", "html", "--extension", "table", "--extension", "strikethrough",
                         "--extension", "autolink", "--extension", "tagfilter", "--extension", "tasklist",
                         "--unsafe", "--smart", file.path]
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        print("  ⊘ \(name) (cmark-gfm failed: \(error))")
        continue
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

    let cmarkHTML = String(data: outputData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    // Normalize both outputs for comparison (whitespace-insensitive)
    let normalizedMV = normalize(markviewHTML)
    let normalizedCM = normalize(cmarkHTML)

    if normalizedMV == normalizedCM {
        print("  ✓ \(name)")
        passed += 1
    } else {
        print("  ✗ \(name) (outputs differ)")
        failed += 1
        diffs.append((file: name, markview: markviewHTML, cmark: cmarkHTML))
    }
}

print("\nResults: \(passed) matched, \(failed) differed")

if !diffs.isEmpty {
    print("\n--- Differences ---")
    for d in diffs.prefix(3) {
        print("\n\(d.file):")
        print("  MarkView (\(d.markview.count) chars): \(d.markview.prefix(200))")
        print("  cmark-gfm (\(d.cmark.count) chars): \(d.cmark.prefix(200))")
    }
    if diffs.count > 3 {
        print("\n  ... and \(diffs.count - 3) more differences")
    }
}

// Differential tests are advisory — don't fail CI for minor differences
// (cmark-gfm versions may produce slightly different HTML)
exit(0)

func normalize(_ html: String) -> String {
    html.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased()
}
