#!/bin/bash
set -euo pipefail

# Cloudflare MCP Worker — Tiered Verification Test Suite
# Usage: bash workers/mcp/scripts/test-worker.sh [--url URL] [--tier 1|2|3]
#
# Tier 1: Static correctness (no server required)
# Tier 2: Behavioral tests (requires running server at BASE_URL)
# Tier 3: Production smoke test (requires --url with production URL)

WORKER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL="http://localhost:8787"
TIER="all"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) BASE_URL="$2"; shift 2 ;;
    --tier) TIER="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# assert_contains <haystack> <needle> <label>
assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null || true; then
    if echo "$haystack" | grep -qF "$needle"; then
      pass "$label"
    else
      fail "$label: expected to find '$needle'"
    fi
  else
    fail "$label: expected to find '$needle'"
  fi
}

# assert_not_contains <haystack> <needle> <label>
assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    fail "$label: must not contain '$needle'"
  else
    pass "$label"
  fi
}

# assert_eq <actual> <expected> <label>
assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label: expected $expected, got $actual"
  fi
}

echo "=== Cloudflare MCP Worker Test Suite ==="
echo "Worker dir: $WORKER_DIR"
echo ""

# ---------------------------------------------------------------------------
# Tier 1 — Static Correctness
# ---------------------------------------------------------------------------
run_tier1() {
  echo "--- Tier 1: Static Correctness ---"

  # wrangler.toml exists
  if [ -f "$WORKER_DIR/wrangler.toml" ]; then
    pass "wrangler.toml exists"
  else
    fail "wrangler.toml missing"
  fi

  # wrangler.toml contains correct worker name
  if [ -f "$WORKER_DIR/wrangler.toml" ]; then
    TOML_CONTENT=$(cat "$WORKER_DIR/wrangler.toml")
    assert_contains "$TOML_CONTENT" '"markview-mcp"' 'wrangler.toml has name = "markview-mcp"'
  fi

  # src/index.ts exists
  if [ -f "$WORKER_DIR/src/index.ts" ]; then
    pass "src/index.ts exists"
  else
    fail "src/index.ts missing"
    # Cannot run remaining static checks without the file
    return
  fi

  SRC=$(cat "$WORKER_DIR/src/index.ts")

  # Must contain TOOL_UNAVAILABLE constant
  assert_contains "$SRC" "TOOL_UNAVAILABLE" 'src/index.ts defines TOOL_UNAVAILABLE constant'

  # Must use "filename" (not "title") in tools definition (TS unquoted keys: filename:)
  assert_contains "$SRC" 'filename:' 'src/index.ts uses "filename" in tools definition (not "title")'

  # Must NOT set Mcp-Session-Id in response headers
  # Stateless worker: allowed to READ but never SET this header
  # Look for any header set/append call containing "Mcp-Session-Id"
  if echo "$SRC" | grep -q 'headers\.set.*Mcp-Session-Id\|headers\.append.*Mcp-Session-Id\|"Mcp-Session-Id".*:.*headers\|new Headers.*Mcp-Session-Id'; then
    fail 'src/index.ts must not set Mcp-Session-Id in response headers (stateless requirement)'
  else
    pass 'src/index.ts does not set Mcp-Session-Id in responses (stateless)'
  fi

  echo ""
}

# ---------------------------------------------------------------------------
# Tier 2 — Behavioral Tests
# ---------------------------------------------------------------------------
run_tier2() {
  echo "--- Tier 2: Behavioral Tests ($BASE_URL) ---"

  # T2.1: OPTIONS preflight → 204
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "$BASE_URL/mcp") || status="000"
  assert_eq "$status" "204" "T2.1 OPTIONS /mcp → 204"

  # T2.2: Wrong path → 404
  status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/") || status="000"
  assert_eq "$status" "404" "T2.2 GET / → 404"

  # T2.3: GET /mcp → 405
  status=$(curl -s -o /dev/null -w "%{http_code}" -X GET "$BASE_URL/mcp") || status="000"
  assert_eq "$status" "405" "T2.3 GET /mcp → 405"

  # T2.4: DELETE /mcp → 405
  status=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/mcp") || status="000"
  assert_eq "$status" "405" "T2.4 DELETE /mcp → 405"

  # T2.5: POST without Content-Type → 415
  status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/mcp" -d '{}') || status="000"
  assert_eq "$status" "415" "T2.5 POST without Content-Type → 415"

  # T2.6: POST with invalid JSON → 400, error code -32700
  local resp
  resp=$(curl -s -X POST "$BASE_URL/mcp" -H "Content-Type: application/json" -d 'not json') || resp=""
  assert_contains "$resp" '"code":-32700' "T2.6 invalid JSON → error -32700 (parse error)"

  # T2.7: POST with JSON array (batch) → 400, error code -32600
  resp=$(curl -s -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '[{"jsonrpc":"2.0","id":1,"method":"ping"}]') || resp=""
  assert_contains "$resp" '"code":-32600' "T2.7 JSON array (batch) → error -32600 (invalid request)"

  # T2.8: initialize → 200, correct fields, no Mcp-Session-Id response header
  local http_code headers
  http_code=$(curl -s -o /tmp/mcp_t28_resp.json -w "%{http_code}" \
    -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}') || http_code="000"
  resp=$(cat /tmp/mcp_t28_resp.json 2>/dev/null || echo "")
  assert_eq "$http_code" "200" "T2.8 initialize → 200"
  assert_contains "$resp" '"protocolVersion"' 'T2.8 initialize response contains protocolVersion'
  assert_contains "$resp" '"serverInfo"' 'T2.8 initialize response contains serverInfo'
  assert_contains "$resp" '"markview"' 'T2.8 initialize response contains markview'

  # Verify no Mcp-Session-Id response header (stateless)
  # Use ^mcp-session-id: to match header key only — not the Access-Control-Allow-Headers value
  t28_headers=$(curl -s -D - -o /dev/null \
    -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}') || t28_headers=""
  if echo "$t28_headers" | grep -qi "^mcp-session-id:"; then
    fail "T2.8 response must not include Mcp-Session-Id header (stateless)"
  else
    pass "T2.8 response does not include Mcp-Session-Id header (stateless)"
  fi

  # T2.9: initialized notification → 202
  status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"initialized"}') || status="000"
  assert_eq "$status" "202" "T2.9 initialized notification → 202"

  # T2.10: tools/list → 200, correct tool names and field names
  http_code=$(curl -s -o /tmp/mcp_t210_resp.json -w "%{http_code}" \
    -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}') || http_code="000"
  resp=$(cat /tmp/mcp_t210_resp.json 2>/dev/null || echo "")
  assert_eq "$http_code" "200" "T2.10 tools/list → 200"
  assert_contains "$resp" '"preview_markdown"' "T2.10 tools/list contains preview_markdown"
  assert_contains "$resp" '"open_file"' "T2.10 tools/list contains open_file"
  assert_contains "$resp" '"filename"' 'T2.10 tools/list uses "filename" (not "title")'
  assert_not_contains "$resp" '"title"' 'T2.10 tools/list does not use deprecated "title" field'

  # T2.11: tools/call → 200, isError: true, no user input echoed (security)
  http_code=$(curl -s -o /tmp/mcp_t211_resp.json -w "%{http_code}" \
    -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"preview_markdown","arguments":{"content":"INJECT_TEST_MARKER_XYZ"}}}') || http_code="000"
  resp=$(cat /tmp/mcp_t211_resp.json 2>/dev/null || echo "")
  assert_eq "$http_code" "200" "T2.11 tools/call → 200"
  assert_contains "$resp" '"isError":true' "T2.11 tools/call returns isError: true (no local app)"
  assert_not_contains "$resp" "INJECT_TEST_MARKER_XYZ" "T2.11 user input not echoed in error response (security)"

  # T2.12: ping → 200, result: {}
  http_code=$(curl -s -o /tmp/mcp_t212_resp.json -w "%{http_code}" \
    -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":4,"method":"ping"}') || http_code="000"
  resp=$(cat /tmp/mcp_t212_resp.json 2>/dev/null || echo "")
  assert_eq "$http_code" "200" "T2.12 ping → 200"
  assert_contains "$resp" '"result":{}' 'T2.12 ping returns result: {}'

  # T2.13: unknown method with id → -32601
  resp=$(curl -s -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":5,"method":"nonexistent/method"}') || resp=""
  assert_contains "$resp" '"code":-32601' "T2.13 unknown method → error -32601 (method not found)"

  # T2.14: CORS headers present
  # Use -D - (dump headers inline) instead of -I (--head) — curl -I ignores -X POST
  headers=$(curl -s -D - -o /dev/null \
    -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}') || headers=""
  if echo "$headers" | grep -qi "access-control-allow-origin: \*"; then
    pass "T2.14 CORS: access-control-allow-origin: * present"
  else
    fail "T2.14 CORS: access-control-allow-origin: * missing"
  fi

  # T2.15: Security headers present
  if echo "$headers" | grep -qi "x-content-type-options: nosniff"; then
    pass "T2.15 security: x-content-type-options: nosniff present"
  else
    fail "T2.15 security: x-content-type-options: nosniff missing"
  fi
  if echo "$headers" | grep -qi "cache-control: no-store"; then
    pass "T2.15 security: cache-control: no-store present"
  else
    fail "T2.15 security: cache-control: no-store missing"
  fi

  # T2.16: Protocol version negotiation — unknown version gets LATEST
  resp=$(curl -s -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}') || resp=""
  assert_contains "$resp" '"protocolVersion":"2025-11-25"' "T2.16 unknown protocol version → negotiated to LATEST (2025-11-25)"

  # T2.17: Protocol version negotiation — known old version echoed back
  resp=$(curl -s -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}') || resp=""
  assert_contains "$resp" '"protocolVersion":"2024-11-05"' "T2.17 known old protocol version (2024-11-05) echoed back"

  echo ""
}

# ---------------------------------------------------------------------------
# Tier 3 — Production Smoke Test
# ---------------------------------------------------------------------------
run_tier3() {
  echo "--- Tier 3: Production Smoke Test ($BASE_URL) ---"

  local http_code resp

  # T3.1: initialize (mirrors T2.8)
  http_code=$(curl -s -o /tmp/mcp_t31_resp.json -w "%{http_code}" \
    -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}') || http_code="000"
  resp=$(cat /tmp/mcp_t31_resp.json 2>/dev/null || echo "")
  assert_eq "$http_code" "200" "T3.1 [prod] initialize → 200"
  assert_contains "$resp" '"protocolVersion"' "T3.1 [prod] initialize response contains protocolVersion"
  assert_contains "$resp" '"serverInfo"' "T3.1 [prod] initialize response contains serverInfo"
  assert_contains "$resp" '"markview"' "T3.1 [prod] initialize response contains markview"

  # T3.2: tools/list (mirrors T2.10)
  http_code=$(curl -s -o /tmp/mcp_t32_resp.json -w "%{http_code}" \
    -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}') || http_code="000"
  resp=$(cat /tmp/mcp_t32_resp.json 2>/dev/null || echo "")
  assert_eq "$http_code" "200" "T3.2 [prod] tools/list → 200"
  assert_contains "$resp" '"preview_markdown"' "T3.2 [prod] tools/list contains preview_markdown"
  assert_contains "$resp" '"open_file"' "T3.2 [prod] tools/list contains open_file"
  assert_contains "$resp" '"filename"' 'T3.2 [prod] tools/list uses "filename"'

  # T3.3: tools/call isError + no input echo (mirrors T2.11)
  http_code=$(curl -s -o /tmp/mcp_t33_resp.json -w "%{http_code}" \
    -X POST "$BASE_URL/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"preview_markdown","arguments":{"content":"INJECT_TEST_MARKER_XYZ"}}}') || http_code="000"
  resp=$(cat /tmp/mcp_t33_resp.json 2>/dev/null || echo "")
  assert_eq "$http_code" "200" "T3.3 [prod] tools/call → 200"
  assert_contains "$resp" '"isError":true' "T3.3 [prod] tools/call returns isError: true"
  assert_not_contains "$resp" "INJECT_TEST_MARKER_XYZ" "T3.3 [prod] user input not echoed in error response (security)"

  echo ""
}

# ---------------------------------------------------------------------------
# Dispatch based on --tier flag
# ---------------------------------------------------------------------------
case "$TIER" in
  1)
    run_tier1
    ;;
  2)
    run_tier2
    ;;
  3)
    run_tier3
    ;;
  all)
    run_tier1
    run_tier2
    ;;
  *)
    echo "Unknown tier: $TIER (must be 1, 2, 3, or omit for all)"
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
