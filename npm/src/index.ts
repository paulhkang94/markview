#!/usr/bin/env node
/**
 * Smithery entry point — proxies to the native MarkView MCP binary.
 *
 * Two modes:
 *   1. Stdio (default): spawns the native Swift binary when run as main
 *   2. Sandbox: exports createSandboxServer() for Smithery capability scanning
 *      (returns a mock MCP server with tool definitions — no binary spawn)
 */
import { spawn } from "child_process";
import { resolve } from "path";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

const VERSION = "1.2.6";

const TOOLS = [
  {
    name: "preview_markdown",
    description:
      "Render a markdown string in MarkView's native macOS preview window. " +
      "Supports GFM, Mermaid diagrams, code syntax highlighting (Prism.js), " +
      "tables, task lists, and all CommonMark extensions.",
    inputSchema: {
      type: "object" as const,
      properties: {
        content: {
          type: "string",
          description: "Markdown source text to preview",
        },
        filename: {
          type: "string",
          description: "Optional filename hint (default: preview.md)",
        },
      },
      required: ["content"],
    },
  },
  {
    name: "open_file",
    description:
      "Open an existing markdown file from disk in MarkView. " +
      "The file must exist and have a markdown extension (.md, .markdown).",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: { type: "string", description: "Absolute path to the .md file" },
      },
      required: ["path"],
    },
  },
];

/**
 * Sandbox server for Smithery capability scanning.
 * Returns a mock MCP server that responds to tools/list without spawning the Swift binary.
 * Called by Smithery's CLI during `mcp publish` to enumerate available tools.
 */
export function createSandboxServer(): Server {
  const server = new Server(
    { name: "markview", version: VERSION },
    { capabilities: { tools: {} } },
  );
  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: TOOLS,
  }));
  return server;
}

/** Default export for Smithery shttp transport mode. */
export default createSandboxServer;

// Stdio entrypoint — only spawns the native binary when run as main (not imported for scanning)
if (require.main === module) {
  const binary = resolve(__dirname, "../bin/mcp-server-markview");
  const child = spawn(binary, process.argv.slice(2), {
    stdio: "inherit",
    env: process.env,
  });
  child.on("exit", (code) => process.exit(code ?? 0));
  child.on("error", (err) => {
    process.stderr.write(`MarkView MCP server error: ${err.message}\n`);
    process.exit(1);
  });
}
