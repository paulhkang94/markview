var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/index.ts
var SUPPORTED_VERSIONS = [
  "2025-11-25",
  "2025-06-18",
  "2025-03-26",
  "2024-11-05",
  "2024-10-07"
];
var LATEST_VERSION = "2025-11-25";
var TOOL_UNAVAILABLE = "MarkView is a native macOS app \u2014 this server runs in capability-listing mode only. To use MarkView's MCP tools, install the app: https://github.com/paulhkang94/markview";
var TOOLS = [
  {
    name: "preview_markdown",
    description: "Render markdown content in the MarkView macOS preview app.",
    inputSchema: {
      type: "object",
      properties: {
        content: {
          type: "string",
          description: "Markdown source text to preview"
        },
        filename: {
          type: "string",
          description: "Optional filename hint (default: preview.md)"
        }
      },
      required: ["content"]
    }
  },
  {
    name: "open_file",
    description: "Open an existing markdown file in the MarkView macOS app.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "Absolute path to the .md file"
        }
      },
      required: ["path"]
    }
  }
];
var SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Mcp-Session-Id",
  "Access-Control-Max-Age": "86400"
};
function baseHeaders(extra) {
  const h = new Headers(SECURITY_HEADERS);
  if (extra) {
    for (const [k, v] of Object.entries(extra)) h.set(k, v);
  }
  return h;
}
__name(baseHeaders, "baseHeaders");
function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: baseHeaders({ "Content-Type": "application/json" })
  });
}
__name(jsonResponse, "jsonResponse");
function rpcError(id, code, message, httpStatus = 200) {
  return jsonResponse(
    { jsonrpc: "2.0", id, error: { code, message } },
    httpStatus
  );
}
__name(rpcError, "rpcError");
function methodAllowed(status) {
  return new Response(null, {
    status,
    headers: baseHeaders({ Allow: "POST, OPTIONS" })
  });
}
__name(methodAllowed, "methodAllowed");
function isValidId(id) {
  return id === null || typeof id === "string" || typeof id === "number";
}
__name(isValidId, "isValidId");
function handleInitialize(id, params) {
  const clientVersion = typeof params.protocolVersion === "string" ? params.protocolVersion : null;
  const negotiatedVersion = clientVersion !== null && SUPPORTED_VERSIONS.includes(clientVersion) ? clientVersion : LATEST_VERSION;
  return jsonResponse({
    jsonrpc: "2.0",
    id,
    result: {
      protocolVersion: negotiatedVersion,
      capabilities: { tools: {} },
      serverInfo: {
        name: "markview",
        version: "1.0.0"
      }
    }
  });
}
__name(handleInitialize, "handleInitialize");
function handleToolsList(id) {
  return jsonResponse({
    jsonrpc: "2.0",
    id,
    result: { tools: TOOLS }
  });
}
__name(handleToolsList, "handleToolsList");
function handleToolsCall(id) {
  return jsonResponse({
    jsonrpc: "2.0",
    id,
    result: {
      isError: true,
      content: [
        {
          type: "text",
          text: TOOL_UNAVAILABLE
        }
      ]
    }
  });
}
__name(handleToolsCall, "handleToolsCall");
function handlePing(id) {
  return jsonResponse({ jsonrpc: "2.0", id, result: {} });
}
__name(handlePing, "handlePing");
function dispatchMessage(body) {
  if (Array.isArray(body)) {
    return rpcError(null, -32600, "Invalid Request", 400);
  }
  if (typeof body !== "object" || body === null) {
    return rpcError(null, -32600, "Invalid Request");
  }
  const msg = body;
  if ("id" in msg && !isValidId(msg.id)) {
    return rpcError(null, -32600, "Invalid Request");
  }
  const id = "id" in msg ? msg.id : void 0;
  const method = typeof msg.method === "string" ? msg.method : null;
  const params = typeof msg.params === "object" && msg.params !== null && !Array.isArray(msg.params) ? msg.params : {};
  if (id === void 0) {
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
      return rpcError(id, -32601, "Method not found");
  }
}
__name(dispatchMessage, "dispatchMessage");
async function handleRequest(request) {
  const url = new URL(request.url);
  if (url.pathname !== "/mcp") {
    return new Response(null, { status: 404, headers: baseHeaders() });
  }
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: baseHeaders() });
  }
  if (request.method !== "POST") {
    return methodAllowed(405);
  }
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.includes("application/json")) {
    return new Response(null, { status: 415, headers: baseHeaders() });
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return rpcError(null, -32700, "Parse error", 400);
  }
  try {
    return dispatchMessage(body);
  } catch {
    return rpcError(null, -32603, "Internal error");
  }
}
__name(handleRequest, "handleRequest");
var src_default = {
  async fetch(request) {
    try {
      return await handleRequest(request);
    } catch {
      return rpcError(null, -32603, "Internal error");
    }
  }
};

// node_modules/wrangler/templates/middleware/middleware-ensure-req-body-drained.ts
var drainBody = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } finally {
    try {
      if (request.body !== null && !request.bodyUsed) {
        const reader = request.body.getReader();
        while (!(await reader.read()).done) {
        }
      }
    } catch (e) {
      console.error("Failed to drain the unused request body.", e);
    }
  }
}, "drainBody");
var middleware_ensure_req_body_drained_default = drainBody;

// node_modules/wrangler/templates/middleware/middleware-miniflare3-json-error.ts
function reduceError(e) {
  return {
    name: e?.name,
    message: e?.message ?? String(e),
    stack: e?.stack,
    cause: e?.cause === void 0 ? void 0 : reduceError(e.cause)
  };
}
__name(reduceError, "reduceError");
var jsonError = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } catch (e) {
    const error = reduceError(e);
    return Response.json(error, {
      status: 500,
      headers: { "MF-Experimental-Error-Stack": "true" }
    });
  }
}, "jsonError");
var middleware_miniflare3_json_error_default = jsonError;

// .wrangler/tmp/bundle-RGeUN5/middleware-insertion-facade.js
var __INTERNAL_WRANGLER_MIDDLEWARE__ = [
  middleware_ensure_req_body_drained_default,
  middleware_miniflare3_json_error_default
];
var middleware_insertion_facade_default = src_default;

// node_modules/wrangler/templates/middleware/common.ts
var __facade_middleware__ = [];
function __facade_register__(...args) {
  __facade_middleware__.push(...args.flat());
}
__name(__facade_register__, "__facade_register__");
function __facade_invokeChain__(request, env, ctx, dispatch, middlewareChain) {
  const [head, ...tail] = middlewareChain;
  const middlewareCtx = {
    dispatch,
    next(newRequest, newEnv) {
      return __facade_invokeChain__(newRequest, newEnv, ctx, dispatch, tail);
    }
  };
  return head(request, env, ctx, middlewareCtx);
}
__name(__facade_invokeChain__, "__facade_invokeChain__");
function __facade_invoke__(request, env, ctx, dispatch, finalMiddleware) {
  return __facade_invokeChain__(request, env, ctx, dispatch, [
    ...__facade_middleware__,
    finalMiddleware
  ]);
}
__name(__facade_invoke__, "__facade_invoke__");

// .wrangler/tmp/bundle-RGeUN5/middleware-loader.entry.ts
var __Facade_ScheduledController__ = class ___Facade_ScheduledController__ {
  constructor(scheduledTime, cron, noRetry) {
    this.scheduledTime = scheduledTime;
    this.cron = cron;
    this.#noRetry = noRetry;
  }
  static {
    __name(this, "__Facade_ScheduledController__");
  }
  #noRetry;
  noRetry() {
    if (!(this instanceof ___Facade_ScheduledController__)) {
      throw new TypeError("Illegal invocation");
    }
    this.#noRetry();
  }
};
function wrapExportedHandler(worker) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return worker;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  const fetchDispatcher = /* @__PURE__ */ __name(function(request, env, ctx) {
    if (worker.fetch === void 0) {
      throw new Error("Handler does not export a fetch() function.");
    }
    return worker.fetch(request, env, ctx);
  }, "fetchDispatcher");
  return {
    ...worker,
    fetch(request, env, ctx) {
      const dispatcher = /* @__PURE__ */ __name(function(type, init) {
        if (type === "scheduled" && worker.scheduled !== void 0) {
          const controller = new __Facade_ScheduledController__(
            Date.now(),
            init.cron ?? "",
            () => {
            }
          );
          return worker.scheduled(controller, env, ctx);
        }
      }, "dispatcher");
      return __facade_invoke__(request, env, ctx, dispatcher, fetchDispatcher);
    }
  };
}
__name(wrapExportedHandler, "wrapExportedHandler");
function wrapWorkerEntrypoint(klass) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return klass;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  return class extends klass {
    #fetchDispatcher = /* @__PURE__ */ __name((request, env, ctx) => {
      this.env = env;
      this.ctx = ctx;
      if (super.fetch === void 0) {
        throw new Error("Entrypoint class does not define a fetch() function.");
      }
      return super.fetch(request);
    }, "#fetchDispatcher");
    #dispatcher = /* @__PURE__ */ __name((type, init) => {
      if (type === "scheduled" && super.scheduled !== void 0) {
        const controller = new __Facade_ScheduledController__(
          Date.now(),
          init.cron ?? "",
          () => {
          }
        );
        return super.scheduled(controller);
      }
    }, "#dispatcher");
    fetch(request) {
      return __facade_invoke__(
        request,
        this.env,
        this.ctx,
        this.#dispatcher,
        this.#fetchDispatcher
      );
    }
  };
}
__name(wrapWorkerEntrypoint, "wrapWorkerEntrypoint");
var WRAPPED_ENTRY;
if (typeof middleware_insertion_facade_default === "object") {
  WRAPPED_ENTRY = wrapExportedHandler(middleware_insertion_facade_default);
} else if (typeof middleware_insertion_facade_default === "function") {
  WRAPPED_ENTRY = wrapWorkerEntrypoint(middleware_insertion_facade_default);
}
var middleware_loader_entry_default = WRAPPED_ENTRY;
export {
  __INTERNAL_WRANGLER_MIDDLEWARE__,
  middleware_loader_entry_default as default
};
//# sourceMappingURL=index.js.map
