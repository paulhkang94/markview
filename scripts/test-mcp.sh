#!/bin/bash
set -euo pipefail

# MCP Server Test Suite
# Tests the MarkViewMCPServer binary via stdio JSON-RPC
# Usage: bash scripts/test-mcp.sh [--skip-e2e]

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PASS=0
FAIL=0
SKIP_E2E="${1:---all}"
MCP_BIN="$PROJECT_DIR/.build/debug/MarkViewMCPServer"

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "=== MCP Server Test Suite ==="
echo ""

# --- Step 0: Build ---
echo "--- Build ---"
if swift build --product MarkViewMCPServer 2>&1 | tail -1 | grep -q "complete"; then
    pass "debug build succeeds"
else
    fail "debug build failed"
    echo "=== Results: $PASS passed, $FAIL failed ==="
    exit 1
fi

if [ ! -x "$MCP_BIN" ]; then
    fail "binary not found at $MCP_BIN"
    echo "=== Results: $PASS passed, $FAIL failed ==="
    exit 1
fi
pass "binary exists and is executable"

# --- Step 1: Binary basics ---
echo ""
echo "--- Binary Basics ---"
BINARY_TYPE=$(file "$MCP_BIN" 2>/dev/null || true)
if echo "$BINARY_TYPE" | grep -q "Mach-O"; then
    pass "binary is Mach-O"
else
    fail "binary is not Mach-O: $BINARY_TYPE"
fi

BINARY_SIZE=$(stat -f%z "$MCP_BIN" 2>/dev/null || echo "0")
if [ "$BINARY_SIZE" -gt 0 ]; then
    SIZE_MB=$(echo "scale=1; $BINARY_SIZE / 1048576" | bc)
    pass "binary size: ${SIZE_MB}MB"
else
    fail "binary has zero size"
fi

# --- Step 2: Protocol tests via Python harness ---
echo ""
echo "--- Protocol + Tool Tests (via subprocess harness) ---"

python3 -c "
import subprocess, json, sys, os, time

MCP_BIN = '$MCP_BIN'
SKIP_E2E = '$SKIP_E2E' == '--skip-e2e'
passes = 0
fails = 0

def test(name, condition):
    global passes, fails
    if condition:
        print(f'  ✓ {name}')
        passes += 1
    else:
        print(f'  ✗ {name}')
        fails += 1

def send_and_receive(proc, request):
    '''Send a JSON-RPC request and read the response line'''
    msg = json.dumps(request) + '\n'
    proc.stdin.write(msg)
    proc.stdin.flush()
    # Read response with timeout
    import select
    ready, _, _ = select.select([proc.stdout], [], [], 5.0)
    if ready:
        line = proc.stdout.readline()
        if line:
            return json.loads(line)
    return None

# Start server
proc = subprocess.Popen(
    [MCP_BIN],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1  # line-buffered
)

time.sleep(0.5)  # let server initialize

# Test: Initialize
init_req = {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'test-harness', 'version': '0.1'}
    }
}
resp = send_and_receive(proc, init_req)
test('initialize returns response', resp is not None)
if resp:
    result = resp.get('result', {})
    test('server name is markview', result.get('serverInfo', {}).get('name') == 'markview')
    expected_ver = subprocess.run(['plutil', '-extract', 'CFBundleShortVersionString', 'raw', '$PROJECT_DIR/Sources/MarkView/Info.plist'], capture_output=True, text=True).stdout.strip()
    actual_ver = result.get('serverInfo', {}).get('version', '')
    test(f'server version is {expected_ver}', actual_ver == expected_ver)
    test('declares tools capability', 'tools' in result.get('capabilities', {}))

    # Send initialized notification
    notif = {'jsonrpc': '2.0', 'method': 'notifications/initialized'}
    proc.stdin.write(json.dumps(notif) + '\n')
    proc.stdin.flush()
    time.sleep(0.3)

    # Test: List tools
    list_req = {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list', 'params': {}}
    list_resp = send_and_receive(proc, list_req)
    test('tools/list returns response', list_resp is not None)
    if list_resp:
        tools = list_resp.get('result', {}).get('tools', [])
        tool_names = [t['name'] for t in tools]
        test('lists preview_markdown tool', 'preview_markdown' in tool_names)
        test('lists open_file tool', 'open_file' in tool_names)
        test('exactly 2 tools', len(tools) == 2)

        # Check schema structure
        for t in tools:
            if t['name'] == 'preview_markdown':
                schema = t.get('inputSchema', {})
                props = schema.get('properties', {})
                test('preview_markdown has content param', 'content' in props)
                test('preview_markdown has filename param', 'filename' in props)

    # Test: preview_markdown
    call_req = {
        'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call',
        'params': {
            'name': 'preview_markdown',
            'arguments': {'content': '# Test\\n\\nHello from MCP test', 'filename': 'mcp-test.md'}
        }
    }
    call_resp = send_and_receive(proc, call_req)
    test('preview_markdown returns response', call_resp is not None)
    if call_resp:
        result = call_resp.get('result', {})
        content_items = result.get('content', [])
        text = content_items[0].get('text', '') if content_items else ''
        has_error = result.get('isError', False)
        # Note: may fail if MarkView.app not installed, that's OK
        if has_error:
            test('preview_markdown error is informative', 'MarkView' in text)
        else:
            test('preview_markdown mentions temp path', 'markview-mcp' in text)
            test('preview_markdown success', 'Previewing' in text or 'markview-mcp' in text)

    # Test: preview_markdown missing content
    err_req = {
        'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call',
        'params': {'name': 'preview_markdown', 'arguments': {}}
    }
    err_resp = send_and_receive(proc, err_req)
    test('missing content returns response', err_resp is not None)
    if err_resp:
        result = err_resp.get('result', {})
        is_err = result.get('isError', False)
        text = result.get('content', [{}])[0].get('text', '')
        test('missing content is error', is_err == True)
        test('missing content error message', 'Missing required' in text)

    # Test: open_file with nonexistent path
    nofile_req = {
        'jsonrpc': '2.0', 'id': 5, 'method': 'tools/call',
        'params': {'name': 'open_file', 'arguments': {'path': '/nonexistent/file.md'}}
    }
    nofile_resp = send_and_receive(proc, nofile_req)
    test('nonexistent file returns response', nofile_resp is not None)
    if nofile_resp:
        result = nofile_resp.get('result', {})
        test('nonexistent file is error', result.get('isError', False) == True)
        text = result.get('content', [{}])[0].get('text', '')
        test('nonexistent file error message', 'not found' in text.lower())

    # Test: open_file with non-markdown extension
    os.makedirs('/tmp/markview-mcp-test', exist_ok=True)
    with open('/tmp/markview-mcp-test/test.txt', 'w') as f:
        f.write('not markdown')
    ext_req = {
        'jsonrpc': '2.0', 'id': 6, 'method': 'tools/call',
        'params': {'name': 'open_file', 'arguments': {'path': '/tmp/markview-mcp-test/test.txt'}}
    }
    ext_resp = send_and_receive(proc, ext_req)
    test('non-md extension returns response', ext_resp is not None)
    if ext_resp:
        result = ext_resp.get('result', {})
        test('non-md extension is error', result.get('isError', False) == True)
        text = result.get('content', [{}])[0].get('text', '')
        test('non-md extension error message', 'Not a markdown' in text)
    os.remove('/tmp/markview-mcp-test/test.txt')
    os.rmdir('/tmp/markview-mcp-test')

    # Test: unknown tool
    unk_req = {
        'jsonrpc': '2.0', 'id': 7, 'method': 'tools/call',
        'params': {'name': 'bogus_tool', 'arguments': {}}
    }
    unk_resp = send_and_receive(proc, unk_req)
    test('unknown tool returns response', unk_resp is not None)
    if unk_resp:
        result = unk_resp.get('result', {})
        test('unknown tool is error', result.get('isError', False) == True)
        text = result.get('content', [{}])[0].get('text', '')
        test('unknown tool error message', 'Unknown tool' in text)

    # Test: path traversal prevention in filename
    trav_req = {
        'jsonrpc': '2.0', 'id': 8, 'method': 'tools/call',
        'params': {
            'name': 'preview_markdown',
            'arguments': {'content': 'test', 'filename': '../../etc/passwd'}
        }
    }
    trav_resp = send_and_receive(proc, trav_req)
    test('path traversal returns response', trav_resp is not None)
    if trav_resp:
        text = trav_resp.get('result', {}).get('content', [{}])[0].get('text', '')
        test('path traversal sanitized (no ../)', '..' not in text.split('markview-mcp/')[-1] if 'markview-mcp' in text else True)

    # Test: open_file with valid markdown (E2E)
    if not SKIP_E2E and os.path.isdir('/Applications/MarkView.app'):
        print('')
        print('--- E2E: Real MarkView Launch ---')
        os.makedirs('/tmp/markview-mcp', exist_ok=True)
        test_md = '/tmp/markview-mcp/e2e-test.md'
        with open(test_md, 'w') as f:
            f.write('# E2E Test\n\nCreated by MCP test harness.\n')
        e2e_req = {
            'jsonrpc': '2.0', 'id': 9, 'method': 'tools/call',
            'params': {'name': 'open_file', 'arguments': {'path': test_md}}
        }
        e2e_resp = send_and_receive(proc, e2e_req)
        test('E2E: open_file returns response', e2e_resp is not None)
        if e2e_resp:
            text = e2e_resp.get('result', {}).get('content', [{}])[0].get('text', '')
            test('E2E: MarkView opened file', 'Opened in MarkView' in text)
        os.remove(test_md)
    elif SKIP_E2E:
        print('')
        print('--- E2E: Skipped (--skip-e2e) ---')
    else:
        print('')
        print('--- E2E: Skipped (MarkView.app not installed) ---')

else:
    print('  ✗ No init response — skipping remaining tests')
    fails += 20

# Cleanup
proc.stdin.close()
proc.wait(timeout=3)
import shutil
shutil.rmtree('/tmp/markview-mcp', ignore_errors=True)

# Report back to shell
print(f'  [python harness: {passes} passed, {fails} failed]')
sys.exit(1 if fails > 0 else 0)
"
PYTHON_EXIT=$?

if [ "$PYTHON_EXIT" -eq 0 ]; then
    pass "all protocol + tool tests passed"
else
    fail "some protocol/tool tests failed"
fi

# Summary
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
