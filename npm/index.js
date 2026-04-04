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
      type: "object",
      properties: {
        path: { type: "string", description: "Absolute path to the .md file" },
      },
      required: ["path"],
    },
  },
  {
    name: "lint_file",
    description:
      "Lint a markdown file using MarkView's built-in linter. Returns line-by-line " +
      "diagnostics (warnings and errors) for 9 rules: inconsistent-headings, " +
      "trailing-whitespace, missing-blank-lines, duplicate-headings, broken-links, " +
      "unclosed-fences, unclosed-formatting, mismatched-brackets, invalid-tables.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "Absolute path to the markdown file to lint",
        },
        rules: {
          type: "array",
          items: { type: "string" },
          description:
            "Optional list of rule names to enable. Defaults to all rules.",
        },
      },
      required: ["path"],
    },
  },
  {
    name: "render_diff_file",
    description:
      "Run git diff on a repository and render the output in MarkView with diff2html " +
      "syntax highlighting. Supports side-by-side and line-by-line views.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "Absolute path to the git repository root",
        },
        format: {
          type: "string",
          enum: ["side-by-side", "line-by-line", "unified"],
          description: "Diff display format (default: side-by-side)",
        },
        range: {
          type: "string",
          description:
            "Git range, e.g. 'HEAD~1..HEAD' or 'main..feature'. Default '' = uncommitted changes.",
        },
      },
      required: ["path"],
    },
  },
  {
    name: "render_diff_raw",
    description:
      "Render a raw unified diff string in MarkView with diff2html syntax highlighting. " +
      "Pass the output of 'git diff' or any unified diff directly.",
    inputSchema: {
      type: "object",
      properties: {
        diff: {
          type: "string",
          description:
            "Raw unified diff string (output of git diff or similar)",
        },
        format: {
          type: "string",
          enum: ["side-by-side", "line-by-line", "unified"],
          description: "Diff display format (default: side-by-side)",
        },
      },
      required: ["diff"],
    },
  },
  {
    name: "get_changed_files",
    description:
      "List all changed files in a git repository (staged, unstaged, and untracked). " +
      "Returns structured JSON and a markdown table.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "Absolute path to the git repository root",
        },
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
  const { resolve } = require("path");
  const fs = require("fs");
  // Downloaded binary path — written here by postinstall.js (different name from the
  // shell bin script at bin/mcp-server-markview to avoid an infinite spawn loop).
  const binary = resolve(__dirname, "bin/markview-mcp-server-binary");

  if (process.platform === "darwin" && fs.existsSync(binary)) {
    const { spawn } = require("child_process");
    const child = spawn(binary, process.argv.slice(2), {
      stdio: "inherit",
      env: process.env,
    });
    child.on("exit", (code) => process.exit(code != null ? code : 0));
    child.on("error", (err) => {
      process.stderr.write("MarkView MCP server error: " + err.message + "\n");
      process.exit(1);
    });
  } else {
    // Non-macOS or binary unavailable: run capability-only sandbox server over stdio.
    // Used by Smithery's scanner and other non-macOS environments.
    const {
      StdioServerTransport,
    } = require("@modelcontextprotocol/sdk/server/stdio.js");
    (async () => {
      const server = createSandboxServer();
      const transport = new StdioServerTransport();
      await server.connect(transport);
    })().catch((err) => {
      process.stderr.write(
        "MarkView sandbox server error: " + err.message + "\n",
      );
      process.exit(1);
    });
  }
}
