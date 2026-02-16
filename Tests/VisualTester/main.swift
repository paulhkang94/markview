import AppKit
import Foundation
import MarkViewCore

// =============================================================================
// MARK: - Configuration
// =============================================================================

let fixtureNames = [
    "basic", "gfm-tables", "gfm-tasklists", "gfm-strikethrough",
    "gfm-autolinks", "code-blocks", "links-and-images", "edge-cases"
]

let projectDir = FileManager.default.currentDirectoryPath
let fixturesDir = URL(fileURLWithPath: projectDir).appendingPathComponent("Tests/TestRunner/Fixtures")
let goldensDir = URL(fileURLWithPath: projectDir).appendingPathComponent("Tests/VisualTester/Goldens")

// =============================================================================
// MARK: - CLI Argument Parsing
// =============================================================================

let args = CommandLine.arguments
let generateGoldens = args.contains("--generate-goldens")
let thresholdArg = args.firstIndex(of: "--threshold").flatMap { idx in
    idx + 1 < args.count ? Double(args[idx + 1]) : nil
} ?? 0.995

// =============================================================================
// MARK: - Helpers
// =============================================================================

func loadFixture(_ name: String) -> String? {
    let url = fixturesDir.appendingPathComponent("\(name).md")
    return try? String(contentsOf: url, encoding: .utf8)
}

func renderFixtureToHTML(_ name: String) -> String? {
    guard let md = loadFixture(name) else { return nil }
    let body = MarkdownRenderer.renderHTML(from: md)
    return MarkdownRenderer.wrapInTemplate(body)
}

func goldenPath(fixture: String, theme: String) -> URL {
    goldensDir.appendingPathComponent(theme).appendingPathComponent("\(fixture).png")
}

// =============================================================================
// MARK: - Test Runner
// =============================================================================

struct VisualTestRunner {
    var passed = 0
    var failed = 0

    mutating func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("  \u{2713} \(name)")
        } catch {
            failed += 1
            print("  \u{2717} \(name): \(error)")
        }
    }

    func summary() {
        print("\nResults: \(passed) passed, \(failed) failed")
    }
}

enum VisualTestError: Error, CustomStringConvertible {
    case fixtureNotFound(String)
    case goldenNotFound(String)
    case renderFailed(String)
    case mismatch(fixture: String, theme: String, match: Double, threshold: Double)
    case contrastFailed(String)

    var description: String {
        switch self {
        case .fixtureNotFound(let n): return "Fixture not found: \(n)"
        case .goldenNotFound(let p): return "Golden not found: \(p) (run with --generate-goldens first)"
        case .renderFailed(let n): return "Render failed for: \(n)"
        case .mismatch(let f, let t, let m, let th):
            return "\(f) (\(t)): \(String(format: "%.2f%%", m * 100)) match (threshold: \(String(format: "%.2f%%", th * 100)))"
        case .contrastFailed(let msg): return "Contrast check failed: \(msg)"
        }
    }
}

// =============================================================================
// MARK: - Main Entry Point
// =============================================================================

// NSApplication is required for WKWebView to work (even headless).
// Test logic runs on a background thread; main thread pumps the run loop
// so WKWebView navigation/snapshot callbacks can fire.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

DispatchQueue.global(qos: .userInitiated).async {
    let exitCode = runAllTests()
    exit(exitCode)
}

RunLoop.main.run()

// =============================================================================
// MARK: - Test Logic (runs on background thread)
// =============================================================================

func runAllTests() -> Int32 {
    let renderer = OffscreenRenderer(width: 900, height: 800)
    var runner = VisualTestRunner()

    // --- Golden generation mode ---
    if generateGoldens {
        print("=== Generating Visual Golden Screenshots ===")

        for theme in ["light", "dark"] {
            let dir = goldensDir.appendingPathComponent(theme)
            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            for name in fixtureNames {
                guard var html = renderFixtureToHTML(name) else {
                    print("  \u{2717} Could not load fixture: \(name)")
                    continue
                }
                if theme == "dark" {
                    html = injectDarkMode(into: html)
                }

                do {
                    let pngData = try renderer.renderToPNG(html: html)
                    let path = goldenPath(fixture: name, theme: theme)
                    try pngData.write(to: path)
                    print("  Generated: \(theme)/\(name).png (\(pngData.count) bytes)")
                } catch {
                    print("  \u{2717} Failed to render \(theme)/\(name): \(error)")
                }
            }
        }
        print("\nGolden screenshots generated. Commit these to lock in the baseline.")
        return 0
    }

    // --- Visual regression tests ---
    print("=== Visual Regression Tests ===")
    print("Threshold: \(String(format: "%.2f%%", thresholdArg * 100))")

    let comparator = PixelComparator(tolerance: 2, threshold: thresholdArg)

    for theme in ["light", "dark"] {
        print("\n--- \(theme.capitalized) Mode ---")

        for name in fixtureNames {
            runner.test("\(name) (\(theme))") {
                guard var html = renderFixtureToHTML(name) else {
                    throw VisualTestError.fixtureNotFound(name)
                }
                if theme == "dark" {
                    html = injectDarkMode(into: html)
                }

                let goldenURL = goldenPath(fixture: name, theme: theme)
                guard FileManager.default.fileExists(atPath: goldenURL.path) else {
                    throw VisualTestError.goldenNotFound(goldenURL.path)
                }
                let goldenData = try Data(contentsOf: goldenURL)
                let actualData = try renderer.renderToPNG(html: html)

                guard let result = comparator.compare(actual: actualData, golden: goldenData) else {
                    throw VisualTestError.renderFailed(name)
                }

                if !result.passed {
                    throw VisualTestError.mismatch(
                        fixture: name, theme: theme,
                        match: result.matchPercentage, threshold: result.threshold
                    )
                }
            }
        }
    }

    // --- WCAG Contrast Spot-Checks ---
    print("\n--- WCAG Contrast Spot-Checks (Dark Mode) ---")

    if var html = renderFixtureToHTML("code-blocks") {
        html = injectDarkMode(into: html)
        runner.test("dark mode: inline code contrast >= 4.5:1") {
            let pngData = try renderer.renderToPNG(html: html)
            // Inline code: text #e6edf3 on background #343942
            let codeBg = NSColor(srgbRed: 0x34/255.0, green: 0x39/255.0, blue: 0x42/255.0, alpha: 1.0)
            let codeText = NSColor(srgbRed: 0xe6/255.0, green: 0xed/255.0, blue: 0xf3/255.0, alpha: 1.0)
            let ratio = ContrastChecker.contrastRatio(codeText, codeBg)
            guard ratio >= 4.5 else {
                throw VisualTestError.contrastFailed(
                    "Inline code text (#e6edf3) on bg (#343942): \(String(format: "%.2f", ratio)):1, need >= 4.5:1")
            }
            _ = pngData
        }
    }

    if var html = renderFixtureToHTML("gfm-tables") {
        html = injectDarkMode(into: html)
        runner.test("dark mode: table text contrast >= 4.5:1") {
            let pngData = try renderer.renderToPNG(html: html)
            let bodyBg = NSColor(srgbRed: 0x0d/255.0, green: 0x11/255.0, blue: 0x17/255.0, alpha: 1.0)
            let bodyText = NSColor(srgbRed: 0xe6/255.0, green: 0xed/255.0, blue: 0xf3/255.0, alpha: 1.0)
            let ratio = ContrastChecker.contrastRatio(bodyText, bodyBg)
            guard ratio >= 4.5 else {
                throw VisualTestError.contrastFailed(
                    "Table text (#e6edf3) on bg (#0d1117): \(String(format: "%.2f", ratio)):1, need >= 4.5:1")
            }
            _ = pngData
        }
    }

    if var html = renderFixtureToHTML("basic") {
        html = injectDarkMode(into: html)
        runner.test("dark mode: blockquote text contrast >= 4.5:1") {
            let pngData = try renderer.renderToPNG(html: html)
            let bodyBg = NSColor(srgbRed: 0x0d/255.0, green: 0x11/255.0, blue: 0x17/255.0, alpha: 1.0)
            let bqText = NSColor(srgbRed: 0x8b/255.0, green: 0x94/255.0, blue: 0x9e/255.0, alpha: 1.0)
            let ratio = ContrastChecker.contrastRatio(bqText, bodyBg)
            guard ratio >= 4.5 else {
                throw VisualTestError.contrastFailed(
                    "Blockquote text (#8b949e) on bg (#0d1117): \(String(format: "%.2f", ratio)):1, need >= 4.5:1")
            }
            _ = pngData
        }
    }

    print("")
    runner.summary()
    return runner.failed > 0 ? 1 : 0
}
