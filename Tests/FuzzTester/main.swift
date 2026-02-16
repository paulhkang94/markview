import Foundation
import MarkViewCore

/// Fuzz tester: generate random markdown inputs and verify the renderer never crashes.
/// Runs 10,000 random inputs by default. Override with FUZZ_COUNT env var.

let count = Int(ProcessInfo.processInfo.environment["FUZZ_COUNT"] ?? "10000") ?? 10000

print("=== MarkView Fuzz Tester ===")
print("Running \(count) random inputs...")

let markdownElements: [String] = [
    "# Heading\n", "## Heading\n", "### Heading\n",
    "**bold**", "*italic*", "~~struck~~", "`code`",
    "```\ncode block\n```\n",
    "- list item\n", "1. ordered item\n",
    "| a | b |\n|---|---|\n| c | d |\n",
    "[link](https://example.com)", "![img](https://example.com/img.png)",
    "> blockquote\n", "---\n", "\n",
    "- [x] task\n", "- [ ] task\n",
    "normal text ", "https://autolink.example.com ",
    String(repeating: "#", count: 100), // edge case
    String(repeating: ">", count: 50) + " deep quote\n",
    String(repeating: "- ", count: 30) + "nested\n",
    "<div>html block</div>\n",
    "\\*escaped\\*", "&amp;entity&lt;",
    "", " ", "\t", "\n\n\n",
]

var crashes = 0
let startTime = CFAbsoluteTimeGetCurrent()

for i in 0..<count {
    // Generate random markdown by combining random elements
    let elementCount = Int.random(in: 1...20)
    var markdown = ""
    for _ in 0..<elementCount {
        markdown += markdownElements.randomElement()!
    }

    // Also sometimes generate pure random bytes
    if i % 10 == 0 {
        let randomLength = Int.random(in: 0...500)
        let randomBytes = (0..<randomLength).map { _ in UInt8.random(in: 32...126) }
        markdown = String(bytes: randomBytes, encoding: .ascii) ?? ""
    }

    // Render — should never crash
    let html = MarkdownRenderer.renderHTML(from: markdown)

    // Also test template wrapping
    _ = MarkdownRenderer.wrapInTemplate(html)

    // Also test linter
    let linter = MarkdownLinter()
    _ = linter.lint(markdown)

    if (i + 1) % 2500 == 0 {
        print("  \(i + 1)/\(count) inputs processed...")
    }
}

let elapsed = CFAbsoluteTimeGetCurrent() - startTime

print("")
print("Results: \(count) inputs processed in \(String(format: "%.1f", elapsed))s")
print("  \(String(format: "%.2f", Double(count) / elapsed)) inputs/sec")
print("  \(crashes) crashes")

if crashes > 0 {
    print("\nFAILED: \(crashes) crashes detected")
    exit(1)
} else {
    print("\nPASSED: No crashes detected")
    exit(0)
}
