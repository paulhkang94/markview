/**
 * MarkView MCP Cloudflare Worker
 *
 * Implements MCP Streamable HTTP transport (spec 2025-03-26).
 * Capability-listing only — tools are advertised but calls return a macOS-only error.
 *
 * Design decisions:
 * - TRUE STATELESS: no Mcp-Session-Id header emitted (stateless Workers can't track sessions)
 * - Protocol version negotiation against SUPPORTED_VERSIONS
 * - All error messages are compile-time constants (no user-controlled bytes in responses)
 */

import type { ExportedHandler } from "@cloudflare/workers-types";

// ---------------------------------------------------------------------------
// Protocol constants
// ---------------------------------------------------------------------------

const SUPPORTED_VERSIONS = [
  "2025-11-25",
  "2025-06-18",
  "2025-03-26",
  "2024-11-05",
  "2024-10-07",
] as const;

const LATEST_VERSION = "2025-11-25";

// Compile-time constant — never interpolate user input into this string.
const TOOL_UNAVAILABLE =
  "MarkView is a native macOS app — this server runs in capability-listing mode only. To use MarkView's MCP tools, install the app: https://github.com/paulhkang94/markview";

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: "preview_markdown",
    description: "Render markdown content in the MarkView macOS preview app.",
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
    description: "Open an existing markdown file in the MarkView macOS app.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "Absolute path to the .md file",
        },
      },
      required: ["path"],
    },
  },
];

// ---------------------------------------------------------------------------
// Response helpers
// ---------------------------------------------------------------------------

const SECURITY_HEADERS: Record<string, string> = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Mcp-Session-Id",
  "Access-Control-Max-Age": "86400",
};

function baseHeaders(extra?: Record<string, string>): Headers {
  const h = new Headers(SECURITY_HEADERS);
  if (extra) {
    for (const [k, v] of Object.entries(extra)) h.set(k, v);
  }
  return h;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: baseHeaders({ "Content-Type": "application/json" }),
  });
}

function rpcError(
  id: string | number | null,
  code: number,
  message: string,
  httpStatus = 200,
): Response {
  return jsonResponse(
    { jsonrpc: "2.0", id, error: { code, message } },
    httpStatus,
  );
}

function methodAllowed(status: 405): Response {
  return new Response(null, {
    status,
    headers: baseHeaders({ Allow: "POST, OPTIONS" }),
  });
}

// ---------------------------------------------------------------------------
// JSON-RPC id validation
// ---------------------------------------------------------------------------

function isValidId(id: unknown): id is string | number | null {
  return id === null || typeof id === "string" || typeof id === "number";
}

// ---------------------------------------------------------------------------
// MCP method handlers
// ---------------------------------------------------------------------------

function handleInitialize(
  id: string | number | null,
  params: Record<string, unknown>,
): Response {
  const clientVersion =
    typeof params.protocolVersion === "string" ? params.protocolVersion : null;

  const negotiatedVersion =
    clientVersion !== null &&
    (SUPPORTED_VERSIONS as readonly string[]).includes(clientVersion)
      ? clientVersion
      : LATEST_VERSION;

  return jsonResponse({
    jsonrpc: "2.0",
    id,
    result: {
      protocolVersion: negotiatedVersion,
      capabilities: { tools: {} },
      serverInfo: {
        name: "markview",
        version: "1.0.0",
      },
    },
  });
}

function handleToolsList(id: string | number | null): Response {
  return jsonResponse({
    jsonrpc: "2.0",
    id,
    result: { tools: TOOLS },
  });
}

function handleToolsCall(id: string | number | null): Response {
  // Tool errors use the MCP content array format so LLMs can read them.
  // This is isError: true in result, NOT a JSON-RPC error object.
  return jsonResponse({
    jsonrpc: "2.0",
    id,
    result: {
      isError: true,
      content: [
        {
          type: "text",
          text: TOOL_UNAVAILABLE,
        },
      ],
    },
  });
}

function handlePing(id: string | number | null): Response {
  return jsonResponse({ jsonrpc: "2.0", id, result: {} });
}

// ---------------------------------------------------------------------------
// Main dispatch
// ---------------------------------------------------------------------------

function dispatchMessage(body: unknown): Response {
  // Reject JSON arrays (batch not supported) — HTTP 400 per MCP spec
  if (Array.isArray(body)) {
    return rpcError(null, -32600, "Invalid Request", 400);
  }

  if (typeof body !== "object" || body === null) {
    return rpcError(null, -32600, "Invalid Request");
  }

  const msg = body as Record<string, unknown>;

  // Validate id type before using it
  if ("id" in msg && !isValidId(msg.id)) {
    return rpcError(null, -32600, "Invalid Request");
  }

  const id = "id" in msg ? (msg.id as string | number | null) : undefined;
  const method = typeof msg.method === "string" ? msg.method : null;
  const params =
    typeof msg.params === "object" &&
    msg.params !== null &&
    !Array.isArray(msg.params)
      ? (msg.params as Record<string, unknown>)
      : {};

  // Notifications (no id field) — acknowledge with 202, no body
  if (id === undefined) {
    return new Response(null, { status: 202, headers: baseHeaders() });
  }

  if (method === null) {
    return rpcError(id, -32600, "Invalid Request");
  }

  switch (method) {
    case "initialize":
      return handleInitialize(id, params);
    case "tools/list":
      return handleToolsList(id);
    case "tools/call":
      return handleToolsCall(id);
    case "ping":
      return handlePing(id);
    default:
      // Do NOT echo method name — prevents log injection
      return rpcError(id, -32601, "Method not found");
  }
}

// ---------------------------------------------------------------------------
// Fetch handler
// ---------------------------------------------------------------------------

async function handleRequest(request: Request): Promise<Response> {
  const url = new URL(request.url);

  // All paths except /mcp → 404
  if (url.pathname !== "/mcp") {
    return new Response(null, { status: 404, headers: baseHeaders() });
  }

  // CORS preflight
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: baseHeaders() });
  }

  // Only POST is allowed on /mcp
  if (request.method !== "POST") {
    return methodAllowed(405);
  }

  // Validate Content-Type
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.includes("application/json")) {
    return new Response(null, { status: 415, headers: baseHeaders() });
  }

  // Parse body — JSON parse failures are protocol errors (400), not internal errors
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return rpcError(null, -32700, "Parse error", 400);
  }

  // Dispatch — catch unexpected handler failures without leaking internals
  try {
    return dispatchMessage(body);
  } catch {
    return rpcError(null, -32603, "Internal error");
  }
}

export default {
  async fetch(request: Request): Promise<Response> {
    try {
      return await handleRequest(request);
    } catch {
      return rpcError(null, -32603, "Internal error");
    }
  },
} satisfies ExportedHandler;
