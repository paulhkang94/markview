#!/usr/bin/env node
/**
 * Smithery entry point — proxies to the native MarkView MCP binary.
 * The actual server is a Swift binary distributed via the npm postinstall script.
 * This file exists solely to satisfy Smithery's TypeScript bundler requirement.
 */
import { spawn } from "child_process";
import { resolve } from "path";

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
