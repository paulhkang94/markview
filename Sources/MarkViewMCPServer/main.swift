import Foundation
import MCP
import MarkViewCore

@main
struct MarkViewMCPServer {
    static func main() async throws {
        let server = Server(
            name: "markview",
            version: "1.4.3",
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
                Tool(
                    name: "render_diff_file",
                    description: "Run git diff on a repository and render the output in MarkView with diff2html syntax highlighting. Supports side-by-side and line-by-line views.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Absolute path to the git repository root")
                            ]),
                            "format": .object([
                                "type": .string("string"),
                                "enum": .array([.string("side-by-side"), .string("line-by-line"), .string("unified")]),
                                "description": .string("Diff display format (default: side-by-side)")
                            ]),
                            "range": .object([
                                "type": .string("string"),
                                "description": .string("Git range, e.g. 'HEAD~1..HEAD' or 'main..feature'. Default '' = uncommitted changes.")
                            ])
                        ]),
                        "required": .array([.string("path")])
                    ])
                ),
                Tool(
                    name: "render_diff_raw",
                    description: "Render a raw unified diff string in MarkView with diff2html syntax highlighting. Pass the output of 'git diff' or any unified diff directly.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "diff": .object([
                                "type": .string("string"),
                                "description": .string("Raw unified diff string (output of git diff or similar)")
                            ]),
                            "format": .object([
                                "type": .string("string"),
                                "enum": .array([.string("side-by-side"), .string("line-by-line"), .string("unified")]),
                                "description": .string("Diff display format (default: side-by-side)")
                            ])
                        ]),
                        "required": .array([.string("diff")])
                    ])
                ),
                Tool(
                    name: "get_changed_files",
                    description: "List all changed files in a git repository (staged, unstaged, and untracked). Returns structured JSON and a markdown table.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Absolute path to the git repository root")
                            ])
                        ]),
                        "required": .array([.string("path")])
                    ])
                ),
                Tool(
                    name: "lint_content",
                    description: "Lint raw markdown content using MarkView's built-in linter. Returns line-by-line diagnostics (warnings and errors) for 9 rules: inconsistent-headings, trailing-whitespace, missing-blank-lines, duplicate-headings, broken-links, unclosed-fences, unclosed-formatting, mismatched-brackets, invalid-tables. Unlike lint_file, no file path is required — pass content directly.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("Raw markdown content to lint")
                            ]),
                            "rules": .object([
                                "type": .string("array"),
                                "items": .object(["type": .string("string")]),
                                "description": .string("Optional list of rule names to enable. Defaults to all rules. Valid: inconsistent-headings, trailing-whitespace, missing-blank-lines, duplicate-headings, broken-links, unclosed-fences, unclosed-formatting, mismatched-brackets, invalid-tables")
                            ])
                        ]),
                        "required": .array([.string("content")])
                    ])
                ),
                Tool(
                    name: "get_word_count",
                    description: "Count words, characters, lines, and estimated tokens in markdown content. Returns structured JSON with word_count, char_count, line_count, and estimated_token_count (approximated as ceil(char_count / 4)).",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("Markdown content to count")
                            ])
                        ]),
                        "required": .array([.string("content")])
                    ])
                ),
                Tool(
                    name: "outline",
                    description: "Extract the heading tree from markdown content. Returns a JSON array of headings with their level (1–6), text, and 1-based line number. Useful for navigating large documents or verifying document structure.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("Markdown content to extract headings from")
                            ])
                        ]),
                        "required": .array([.string("content")])
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
            case "render_diff_file":
                return try handleRenderDiffFile(params)
            case "render_diff_raw":
                return try handleRenderDiffRaw(params)
            case "get_changed_files":
                return try handleGetChangedFiles(params)
            case "lint_content":
                return try handleLintContent(params)
            case "get_word_count":
                return try handleGetWordCount(params)
            case "outline":
                return try handleOutline(params)
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

        // File write succeeded — that is the primary success criterion.
        // App launch is best-effort: if MarkView.app is not installed (e.g. on CI),
        // we still return success so agents know the content is staged at fileURL.path.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "MarkView", fileURL.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            return .init(
                content: [.text("Content written to \(fileURL.path). Note: could not open MarkView.app (exit \(process.terminationStatus)) — is MarkView installed?")],
                isError: false
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

    // MARK: - render_diff_file

    static func handleRenderDiffFile(_ params: CallTool.Parameters) throws -> CallTool.Result {
        guard let path = params.arguments?["path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: path")], isError: true)
        }

        let resolvedPath = (path as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return .init(content: [.text("File not found: \(resolvedPath)")], isError: true)
        }

        guard FileManager.default.fileExists(atPath: resolvedPath + "/.git") else {
            return .init(content: [.text("Not a git repository: \(resolvedPath)")], isError: true)
        }

        let format = params.arguments?["format"]?.stringValue ?? "side-by-side"
        let range = params.arguments?["range"]?.stringValue ?? ""

        fputs("[PHK] render_diff_file: path=\(resolvedPath) range=\(range) format=\(format)\n", stderr)

        var gitArgs = ["git", "-C", resolvedPath, "diff"]
        if !range.isEmpty {
            gitArgs.append(range)
        }

        let (output, _) = runProcess(gitArgs, timeoutSeconds: 10.0)

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .init(content: [.text("No changes found")], isError: false)
        }

        fputs("[PHK] render_diff_file: git diff output \(output.count)b → writing to cache\n", stderr)

        let diffContent = "```diff\n\(output)\n```\n"
        let fileURL = try writePreviewCache(content: diffContent, filename: "diff-preview.md")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "MarkView", fileURL.path]
        try process.run()
        process.waitUntilExit()

        return .init(
            content: [.text("Diff rendered in MarkView: \(fileURL.path)")],
            isError: false
        )
    }

    // MARK: - render_diff_raw

    static func handleRenderDiffRaw(_ params: CallTool.Parameters) throws -> CallTool.Result {
        guard let diff = params.arguments?["diff"]?.stringValue, !diff.isEmpty else {
            return .init(content: [.text("Missing required parameter: diff")], isError: true)
        }

        let format = params.arguments?["format"]?.stringValue ?? "side-by-side"

        fputs("[PHK] render_diff_raw: diffSize=\(diff.count)b format=\(format)\n", stderr)

        let diffContent = "```diff\n\(diff)\n```\n"
        let fileURL = try writePreviewCache(content: diffContent, filename: "diff-preview.md")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "MarkView", fileURL.path]
        try process.run()
        process.waitUntilExit()

        return .init(
            content: [.text("Diff rendered in MarkView: \(fileURL.path)")],
            isError: false
        )
    }

    // MARK: - get_changed_files

    static func handleGetChangedFiles(_ params: CallTool.Parameters) throws -> CallTool.Result {
        guard let path = params.arguments?["path"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: path")], isError: true)
        }

        let resolvedPath = (path as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return .init(content: [.text("File not found: \(resolvedPath)")], isError: true)
        }

        guard FileManager.default.fileExists(atPath: resolvedPath + "/.git") else {
            return .init(content: [.text("Not a git repository: \(resolvedPath)")], isError: true)
        }

        let (output, _) = runProcess(["git", "-C", resolvedPath, "status", "--porcelain=v1"])

        // Parse porcelain v1 output: "XY filename" (X=staged, Y=unstaged)
        struct FileEntry: Encodable {
            let path: String
            let status: String
        }

        var staged: [FileEntry] = []
        var unstaged: [FileEntry] = []
        var untracked: [FileEntry] = []

        for line in output.components(separatedBy: "\n") {
            guard line.count >= 3 else { continue }
            let x = String(line[line.startIndex])   // staged status
            let y = String(line[line.index(line.startIndex, offsetBy: 1)])  // unstaged status
            let filePath = String(line.dropFirst(3))
            guard !filePath.isEmpty else { continue }

            if x == "?" && y == "?" {
                untracked.append(FileEntry(path: filePath, status: "?"))
            } else {
                if x != " " && x != "?" {
                    staged.append(FileEntry(path: filePath, status: x))
                }
                if y != " " && y != "?" {
                    unstaged.append(FileEntry(path: filePath, status: y))
                }
            }
        }

        fputs("[PHK] get_changed_files: path=\(resolvedPath) staged=\(staged.count) unstaged=\(unstaged.count) untracked=\(untracked.count)\n", stderr)

        // Build JSON output
        struct ChangedFilesResult: Encodable {
            let staged: [FileEntry]
            let unstaged: [FileEntry]
            let untracked: [FileEntry]
            let summary: String
        }

        let result = ChangedFilesResult(
            staged: staged,
            unstaged: unstaged,
            untracked: untracked,
            summary: "\(staged.count + unstaged.count) changed, \(untracked.count) untracked"
        )

        let jsonData = (try? JSONEncoder().encode(result)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        // Build markdown pipe table
        var tableLines = ["| Status | File |", "|--------|------|"]
        for entry in staged {
            tableLines.append("| \(entry.status) staged | \(entry.path) |")
        }
        for entry in unstaged {
            tableLines.append("| \(entry.status) unstaged | \(entry.path) |")
        }
        for entry in untracked {
            tableLines.append("| ? untracked | \(entry.path) |")
        }
        let tableString = tableLines.joined(separator: "\n")

        let combinedOutput = jsonString + "\n\n" + tableString

        return .init(
            content: [.text(combinedOutput)],
            isError: false
        )
    }

    // MARK: - lint_content

    static func handleLintContent(_ params: CallTool.Parameters) throws -> CallTool.Result {
        guard let content = params.arguments?["content"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: content")], isError: true)
        }

        // Parse optional rules filter (same logic as lint_file)
        var activeRules: Set<LintRule>? = nil
        if let rulesArg = params.arguments?["rules"],
           case let .array(ruleValues) = rulesArg {
            let ruleStrings = ruleValues.compactMap { $0.stringValue }
            let parsed = ruleStrings.compactMap { LintRule(rawValue: $0) }
            if !parsed.isEmpty { activeRules = Set(parsed) }
        }

        let diagnostics = MarkdownLinter().lint(content, rules: activeRules)

        if diagnostics.isEmpty {
            return .init(content: [.text("No issues found.")], isError: false)
        }

        let lines = diagnostics.map { d -> String in
            var line = "\(d.severity.rawValue.uppercased()) [\(d.rule.rawValue)] line \(d.line), col \(d.column): \(d.message)"
            if let fix = d.fix { line += " → Fix: \(fix)" }
            return line
        }
        let summary = "\(diagnostics.count) issue(s) found:\n" + lines.joined(separator: "\n")
        return .init(content: [.text(summary)], isError: false)
    }

    // MARK: - get_word_count

    static func handleGetWordCount(_ params: CallTool.Parameters) throws -> CallTool.Result {
        guard let content = params.arguments?["content"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: content")], isError: true)
        }

        let lineCount = content.components(separatedBy: "\n").count
        let charCount = content.unicodeScalars.count
        // Word count: split on whitespace, filter empty components
        let wordCount = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
        // Token estimate: ~4 chars per token (GPT/Claude approximation), round up
        let estimatedTokenCount = (charCount + 3) / 4

        struct WordCountResult: Encodable {
            let word_count: Int
            let char_count: Int
            let line_count: Int
            let estimated_token_count: Int
        }

        let result = WordCountResult(
            word_count: wordCount,
            char_count: charCount,
            line_count: lineCount,
            estimated_token_count: estimatedTokenCount
        )
        let jsonData = (try? JSONEncoder().encode(result)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        return .init(content: [.text(jsonString)], isError: false)
    }

    // MARK: - outline

    static func handleOutline(_ params: CallTool.Parameters) throws -> CallTool.Result {
        guard let content = params.arguments?["content"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: content")], isError: true)
        }

        struct HeadingEntry: Encodable {
            let level: Int
            let text: String
            let line: Int
        }

        var headings: [HeadingEntry] = []
        var inFence = false
        let lines = content.components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Toggle fence state on ``` lines
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }

            // Detect ATX headings: 1–6 # chars followed by a space (or end of line)
            guard trimmed.hasPrefix("#") else { continue }
            var level = 0
            for ch in trimmed {
                if ch == "#" { level += 1 } else { break }
            }
            guard level >= 1, level <= 6 else { continue }
            // Must have a space after the hashes (or be just hashes — treat as empty heading)
            let afterHashes = trimmed.dropFirst(level)
            guard afterHashes.isEmpty || afterHashes.first == " " else { continue }
            let headingText = afterHashes.trimmingCharacters(in: .whitespaces)
            headings.append(HeadingEntry(level: level, text: headingText, line: i + 1))
        }

        let jsonData = (try? JSONEncoder().encode(headings)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        return .init(content: [.text(jsonString)], isError: false)
    }

    // MARK: - Helpers

    /// Write content to the persistent preview cache and return the file URL.
    @discardableResult
    static func writePreviewCache(content: String, filename: String) throws -> URL {
        let safeName = filename
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/markview/previews", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let fileURL = cacheDir.appendingPathComponent(safeName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Run a subprocess and return (stdout, exitCode). Enforces a timeout and a 2MB output cap.
    static func runProcess(_ args: [String], timeoutSeconds: Double = 10.0) -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: watchdog)

        do {
            try process.run()
            var outputData = Data()
            let maxBytes = 2_000_000
            while process.isRunning {
                let chunk = pipe.fileHandleForReading.availableData
                if !chunk.isEmpty {
                    outputData.append(chunk)
                    if outputData.count > maxBytes {
                        process.terminate()
                        break
                    }
                }
            }
            // Drain any remaining buffered bytes (up to cap)
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            let remainingCapped = remaining.prefix(max(0, maxBytes - outputData.count))
            outputData.append(contentsOf: remainingCapped)
            process.waitUntilExit()
            watchdog.cancel()
            var output = String(data: outputData, encoding: .utf8) ?? ""
            if outputData.count >= maxBytes { output += "\n[Output truncated at 2MB]" }
            return (output, process.terminationStatus)
        } catch {
            watchdog.cancel()
            return ("", 1)
        }
    }
}
