#!/usr/bin/env node
/**
 * index.js — Smithery capability scanning entry point.
 *
 * Two modes:
 *   1. Imported by Smithery: exports createSandboxServer() — returns a mock MCP
 *      server with tool definitions. No binary spawned, works on any platform.
 *   2. Run directly (main): proxies to the native MarkView MCP binary via stdio.
 */
"use strict";

const { Server } = require("@modelcontextprotocol/sdk/server/index.js");
const {
  ListToolsRequestSchema,
} = require("@modelcontextprotocol/sdk/types.js");

const VERSION = "1.2.7";

const TOOLS = [
  {
    name: "preview_markdown",
    description:
      "Render a markdown string in MarkView's native macOS preview window. " +
      "Supports GFM, Mermaid diagrams, code syntax highlighting (Prism.js), " +
      "tables, task lists, and all CommonMark extensions.",
    inputSchema: {
      type: "object",
      properties: {
        content: {
          type: "string",
          description: "Markdown source text to preview",
        },
        title: { type: "string", description: "Optional window title" },
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
      type: "object",
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
 */
function createSandboxServer() {
  const server = new Server(
    { name: "markview", version: VERSION },
    { capabilities: { tools: {} } },
  );
  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: TOOLS,
  }));
  return server;
}

module.exports = { createSandboxServer };
module.exports.default = createSandboxServer;

// Stdio entrypoint — only spawns the native binary when run directly.
if (require.main === module) {
  const { spawn } = require("child_process");
  const { resolve } = require("path");
  const binary = resolve(__dirname, "bin/mcp-server-markview");
  const child = spawn(binary, process.argv.slice(2), {
    stdio: "inherit",
    env: process.env,
  });
  child.on("exit", (code) => process.exit(code != null ? code : 0));
  child.on("error", (err) => {
    process.stderr.write("MarkView MCP server error: " + err.message + "\n");
    process.exit(1);
  });
}
