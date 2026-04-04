import Foundation
import MCP
import MarkViewCore

@main
struct MarkViewMCPServer {
    static func main() async throws {
        let server = Server(
            name: "markview",
            version: "1.2.6",
            capabilities: .init(
                resources: .init(subscribe: false, listChanged: false),
                tools: .init(listChanged: false)
            )
        )

        await server.withMethodHandler(ListResources.self) { _ in
            let previewDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/markview/previews")
            var resources: [Resource] = [
                Resource(
                    name: "Latest Preview",
                    uri: "markview://preview/latest",
                    description: "The most recently previewed markdown content (written by preview_markdown tool).",
                    mimeType: "text/markdown"
                )
            ]
            if let files = try? FileManager.default.contentsOfDirectory(
                at: previewDir, includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) {
                let mdFiles = files.filter { ["md","markdown","mdown"].contains($0.pathExtension.lowercased()) }
                for file in mdFiles.prefix(20) {
                    let fname = file.lastPathComponent
                    resources.append(Resource(
                        name: fname,
                        uri: "markview://preview/\(fname)",
                        description: "Cached preview: \(file.path)",
                        mimeType: "text/markdown"
                    ))
                }
            }
            return .init(resources: resources)
        }

        await server.withMethodHandler(ReadResource.self) { params in
            let uri = params.uri
            let previewDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/markview/previews")

            let fileURL: URL
            if uri == "markview://preview/latest" {
                // Return the most recently modified markdown file in the cache
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: previewDir, includingPropertiesForKeys: [.contentModificationDateKey],
                    options: .skipsHiddenFiles
                ) else {
                    return .init(contents: [.text("No previews found. Call preview_markdown first.", uri: uri, mimeType: "text/plain")])
                }
                guard let latest = files
                    .filter({ ["md","markdown","mdown"].contains($0.pathExtension.lowercased()) })
                    .sorted(by: {
                        let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return d1 > d2
                    }).first
                else {
                    return .init(contents: [.text("No previews found. Call preview_markdown first.", uri: uri, mimeType: "text/plain")])
                }
                fileURL = latest
            } else if uri.hasPrefix("markview://preview/") {
                let filename = String(uri.dropFirst("markview://preview/".count))
                let safeName = filename.replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "..", with: "_")
                fileURL = previewDir.appendingPathComponent(safeName)
            } else {
                return .init(contents: [.text("Unknown resource URI: \(uri). Supported: markview://preview/latest or markview://preview/{filename}", uri: uri, mimeType: "text/plain")])
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return .init(contents: [.text("File not found or unreadable: \(fileURL.path)", uri: uri, mimeType: "text/plain")])
            }
            return .init(contents: [.text(content, uri: uri, mimeType: "text/markdown")])
        }

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [
                Tool(
                    name: "preview_markdown",
                    description: "Preview markdown content in MarkView. Writes content to a temp file and opens it in the native macOS MarkView previewer with live reload.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("Markdown content to preview")
                            ]),
                            "filename": .object([
                                "type": .string("string"),
                                "description": .string("Optional filename hint (default: preview.md)")
                            ])
                        ]),
                        "required": .array([.string("content")])
                    ])
                ),
                Tool(
                    name: "open_file",
                    description: "Open an existing markdown file in MarkView for live preview.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Absolute path to the markdown file")
                            ])
                        ]),
                        "required": .array([.string("path")])
                    ])
                ),
                Tool(
                    name: "lint_file",
                    description: "Lint a markdown file using MarkView's built-in linter. Returns line-by-line diagnostics (warnings and errors) for 9 rules: inconsistent-headings, trailing-whitespace, missing-blank-lines, duplicate-headings, broken-links, unclosed-fences, unclosed-formatting, mismatched-brackets, invalid-tables.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Absolute path to the markdown file to lint")
                            ]),
                            "rules": .object([
                                "type": .string("array"),
                                "items": .object(["type": .string("string")]),
                                "description": .string("Optional list of rule names to enable. Defaults to all rules. Valid: inconsistent-headings, trailing-whitespace, missing-blank-lines, duplicate-headings, broken-links, unclosed-fences, unclosed-formatting, mismatched-brackets, invalid-tables")
                            ])
                        ]),
                        "required": .array([.string("path")])
                    ])
                ),
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "preview_markdown":
                return try handlePreviewMarkdown(params)
            case "open_file":
                return try handleOpenFile(params)
            case "lint_file":
                return try handleLintFile(params)
            default:
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Tool Handlers

    static func handlePreviewMarkdown(_ params: CallTool.Parameters) throws -> CallTool.Result {
        guard let content = params.arguments?["content"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: content")], isError: true)
        }

        let filename = params.arguments?["filename"]?.stringValue ?? "preview.md"
        let safeName = filename.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")

        // Use a persistent cache directory instead of NSTemporaryDirectory.
        // macOS cleans /tmp aggressively; the file can vanish between write and
        // MarkView's FileWatcher initializing, causing NSCocoaErrorDomain Code 260.
        // ~/.cache/markview/previews/ persists across app launches and is safe to
        // rewrite on every preview_markdown call.
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/markview/previews", isDirectory: true)
        let tmpDir = cacheDir
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let fileURL = tmpDir.appendingPathComponent(safeName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "MarkView", fileURL.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            return .init(
                content: [.text("Failed to open MarkView (exit \(process.terminationStatus)). Is MarkView.app installed?")],
                isError: true
            )
        }

        return .init(
            content: [.text("Previewing in MarkView: \(fileURL.path)")],
            isError: false
        )
    }

    static func handleOpenFile(_ params: CallTool.Parameters) throws -> CallTool.Result {
        guard let path = params.arguments?["path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: path")], isError: true)
        }

        let resolvedPath = (path as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return .init(content: [.text("File not found: \(resolvedPath)")], isError: true)
        }

        let ext = (resolvedPath as NSString).pathExtension.lowercased()
        let markdownExtensions = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]
        guard markdownExtensions.contains(ext) else {
            return .init(
                content: [.text("Not a markdown file (.\(ext)). Supported: \(markdownExtensions.joined(separator: ", "))")],
                isError: true
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "MarkView", resolvedPath]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            return .init(
                content: [.text("Failed to open MarkView (exit \(process.terminationStatus)). Is MarkView.app installed?")],
                isError: true
            )
        }

        return .init(
            content: [.text("Opened in MarkView: \(resolvedPath)")],
            isError: false
        )
    }

    static func handleLintFile(_ params: CallTool.Parameters) throws -> CallTool.Result {
        guard let path = params.arguments?["path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: path")], isError: true)
        }

        let resolvedPath = (path as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return .init(content: [.text("File not found: \(resolvedPath)")], isError: true)
        }

        let ext = (resolvedPath as NSString).pathExtension.lowercased()
        let markdownExtensions = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]
        guard markdownExtensions.contains(ext) else {
            return .init(
                content: [.text("Not a markdown file (.\(ext)). Supported: \(markdownExtensions.joined(separator: ", "))")],
                isError: true
            )
        }

        let content: String
        do {
            content = try String(contentsOfFile: resolvedPath, encoding: .utf8)
        } catch {
            return .init(content: [.text("Failed to read file: \(error.localizedDescription)")], isError: true)
        }

        // Parse optional rules filter
        var activeRules: Set<LintRule>? = nil
        if let rulesArg = params.arguments?["rules"],
           case let .array(ruleValues) = rulesArg {
            let ruleStrings = ruleValues.compactMap { $0.stringValue }
            let parsed = ruleStrings.compactMap { LintRule(rawValue: $0) }
            if !parsed.isEmpty { activeRules = Set(parsed) }
        }

        let diagnostics = MarkdownLinter().lint(content, rules: activeRules)

        if diagnostics.isEmpty {
            return .init(content: [.text("No issues found in \(resolvedPath)")], isError: false)
        }

        let lines = diagnostics.map { d -> String in
            var line = "\(d.severity.rawValue.uppercased()) [\(d.rule.rawValue)] line \(d.line), col \(d.column): \(d.message)"
            if let fix = d.fix { line += " → Fix: \(fix)" }
            return line
        }
        let summary = "\(diagnostics.count) issue(s) found in \(resolvedPath):\n" + lines.joined(separator: "\n")
        return .init(content: [.text(summary)], isError: false)
    }
}
