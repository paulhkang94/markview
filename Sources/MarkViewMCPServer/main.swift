import Foundation
import MCP

@main
struct MarkViewMCPServer {
    static func main() async throws {
        let server = Server(
            name: "markview",
            version: "1.1.0",
            capabilities: .init(
                tools: .init(listChanged: false)
            )
        )

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
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "preview_markdown":
                return try handlePreviewMarkdown(params)
            case "open_file":
                return try handleOpenFile(params)
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

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("markview-mcp", isDirectory: true)
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
}
