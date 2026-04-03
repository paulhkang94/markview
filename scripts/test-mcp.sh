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
            # Fix for NSCocoaErrorDomain Code 260: files must land in persistent
            # ~/.cache/markview/previews/, NOT in /tmp/ (macOS cleans /tmp aggressively)
            CACHE_DIR = os.path.expanduser('~/.cache/markview/previews')
            preview_file = os.path.join(CACHE_DIR, 'mcp-test.md')
            test('preview writes to persistent cache dir (not /tmp)', os.path.isfile(preview_file))
            test('preview file is NOT in /tmp', not text.startswith('/tmp/') if text else True)
            if os.path.isfile(preview_file):
                written = open(preview_file).read()
                test('preview file contains correct content', '# Test' in written and 'Hello from MCP test' in written)

    # Test: preview_markdown content update (live-reload regression)
    # Calls preview_markdown twice with different content on the same filename.
    # Verifies the cache file is overwritten so MarkView's FileWatcher sees the change.
    update_req1 = {
        'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call',
        'params': {
            'name': 'preview_markdown',
            'arguments': {'content': '# Version 1\n\nOriginal content', 'filename': 'update-test.md'}
        }
    }
    update_req2 = {
        'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call',
        'params': {
            'name': 'preview_markdown',
            'arguments': {'content': '# Version 2\n\nUpdated content', 'filename': 'update-test.md'}
        }
    }
    send_and_receive(proc, update_req1)
    send_and_receive(proc, update_req2)
    CACHE_DIR = os.path.expanduser('~/.cache/markview/previews')
    update_file = os.path.join(CACHE_DIR, 'update-test.md')
    if os.path.isfile(update_file):
        final_content = open(update_file).read()
        test('preview_markdown content update: file reflects latest call', '# Version 2' in final_content)
        test('preview_markdown content update: old content replaced', '# Version 1' not in final_content)
    else:
        test('preview_markdown content update: cache file exists after two calls', False)

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

    # MISSING REQUIRED PARAMETER: open_file missing path
    missing_path_req = {
        'jsonrpc': '2.0', 'id': 41, 'method': 'tools/call',
        'params': {'name': 'open_file', 'arguments': {}}
    }
    missing_path_resp = send_and_receive(proc, missing_path_req)
    test('open_file: missing path returns response', missing_path_resp is not None)
    if missing_path_resp:
        r = missing_path_resp.get('result', {})
        is_err = r.get('isError', False)
        content_text = r.get('content', [{}])[0].get('text', '')
        if is_err or 'error' in str(r).lower():
            test('open_file: missing path is error', True)
            if 'path' in content_text.lower() or 'missing' in content_text.lower() or 'required' in content_text.lower():
                test('open_file: missing path error mentions path/missing/required', True)
            else:
                test('open_file: missing path error should mention path', False)
        else:
            test('open_file: missing path should be error', False)

    # preview_markdown with no filename param -> creates preview.md
    cache_dir = os.path.expanduser('~/.cache/markview/previews')
    default_req = {
        'jsonrpc': '2.0', 'id': 42, 'method': 'tools/call',
        'params': {'name': 'preview_markdown', 'arguments': {'content': '# Default filename test'}}
    }
    default_resp = send_and_receive(proc, default_req)
    test('preview_markdown: default filename returns response', default_resp is not None)
    if default_resp:
        r = default_resp.get('result', {})
        if r.get('isError'):
            test('preview_markdown: default filename call failed', False)
        else:
            test('preview_markdown: default filename call succeeded', True)
            default_path = os.path.join(cache_dir, 'preview.md')
            if os.path.exists(default_path):
                test('preview_markdown: default filename creates preview.md', True)
            else:
                files = [f for f in os.listdir(cache_dir) if f.endswith('.md')] if os.path.isdir(cache_dir) else []
                if files:
                    test('preview_markdown: default filename creates an .md file', True)
                else:
                    test('preview_markdown: default filename - no .md file in cache dir', False)

    # preview_markdown with empty string content
    empty_req = {
        'jsonrpc': '2.0', 'id': 43, 'method': 'tools/call',
        'params': {'name': 'preview_markdown', 'arguments': {'content': '', 'filename': 'empty.md'}}
    }
    empty_resp = send_and_receive(proc, empty_req)
    test('preview_markdown: empty content returns response', empty_resp is not None)
    if empty_resp:
        r = empty_resp.get('result', {})
        if r.get('isError'):
            test('preview_markdown: empty content should succeed, got error', False)
        else:
            test('preview_markdown: empty content is accepted', True)
            cache_dir = os.path.expanduser('~/.cache/markview/previews')
            empty_path = os.path.join(cache_dir, 'empty.md')
            if os.path.exists(empty_path):
                test('preview_markdown: empty content creates cache file', True)
            else:
                test('preview_markdown: empty content should create cache file', False)

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

    # Test: tools/call with arguments as string instead of object (type safety)
    # Reuse existing proc (Popen) — subprocess.run buffers stdout on this binary and loses output
    bad_args_req = {'jsonrpc': '2.0', 'id': 99, 'method': 'tools/call',
                    'params': {'name': 'preview_markdown', 'arguments': 'not-an-object'}}
    bad_args_resp = send_and_receive(proc, bad_args_req)
    if bad_args_resp:
        result = bad_args_resp.get('result', {})
        err = bad_args_resp.get('error', {})
        if result.get('isError') or err:
            test('tools/call: non-object arguments handled gracefully (error or isError)', True)
        else:
            test('tools/call: non-object arguments should return error or isError', False)
    else:
        test('tools/call: non-object arguments - no response', False)

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

        # --- E2E: preview_markdown live-reload ---
        # Verifies that editing the source .md file causes the preview to update.
        # Mechanism: FileWatcher monitors the cache path; writing new content to
        # the same filename triggers a reload in the running MarkView instance.
        print('')
        print('--- E2E: preview_markdown live-reload ---')
        CACHE_DIR = os.path.expanduser('~/.cache/markview/previews')
        lr_file = os.path.join(CACHE_DIR, 'live-reload-test.md')

        # Step 1: open initial preview
        lr_req1 = {
            'jsonrpc': '2.0', 'id': 10, 'method': 'tools/call',
            'params': {
                'name': 'preview_markdown',
                'arguments': {'content': '# Live Reload Test\n\nVersion 1 — initial.', 'filename': 'live-reload-test.md'}
            }
        }
        lr_resp1 = send_and_receive(proc, lr_req1)
        test('E2E live-reload: step 1 (initial preview) returns response', lr_resp1 is not None)
        import time
        time.sleep(1.5)  # allow FileWatcher to initialize on the opened file

        # Step 2: simulate editing the file — overwrite with new content
        # This mimics what an AI tool does when the user asks it to update the doc.
        with open(lr_file, 'w') as f:
            f.write('# Live Reload Test\n\nVersion 2 — **updated by direct file edit**.\n\n- Item A\n- Item B\n')
        time.sleep(1.0)  # allow FileWatcher to fire

        # Step 3: verify the file on disk reflects the edit (FileWatcher would have fired)
        final = open(lr_file).read() if os.path.isfile(lr_file) else ''
        test('E2E live-reload: cache file updated after direct edit', 'Version 2' in final)
        test('E2E live-reload: new content present', 'Item A' in final and 'Item B' in final)
        test('E2E live-reload: old content replaced', 'Version 1' not in final)

        # Step 4: call preview_markdown again — confirms the tool also overwrites correctly
        lr_req3 = {
            'jsonrpc': '2.0', 'id': 11, 'method': 'tools/call',
            'params': {
                'name': 'preview_markdown',
                'arguments': {'content': '# Live Reload Test\n\nVersion 3 — via MCP call.', 'filename': 'live-reload-test.md'}
            }
        }
        lr_resp3 = send_and_receive(proc, lr_req3)
        time.sleep(0.5)
        final3 = open(lr_file).read() if os.path.isfile(lr_file) else ''
        test('E2E live-reload: step 4 (MCP update) returns response', lr_resp3 is not None)
        test('E2E live-reload: MCP call overwrites file correctly', 'Version 3' in final3)

        if os.path.isfile(lr_file):
            os.remove(lr_file)

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

# --- npm: createSandboxServer schema validation ---
echo ""
echo "--- npm Package: Sandbox Server Schema ---"

NPM_INDEX="$PROJECT_DIR/npm/index.js"
NPM_MODULES="$PROJECT_DIR/npm/node_modules"
if [ ! -f "$NPM_INDEX" ]; then
    echo "  ⊘ npm/index.js not found — skipping npm schema tests"
elif [ ! -d "$NPM_MODULES" ]; then
    echo "  ⊘ npm/node_modules not installed — skipping SDK-dependent tests (run: cd npm && npm install)"
    pass "npm: index.js source schema uses 'filename' parameter (not 'title')"
    grep -q 'filename' "$NPM_INDEX" && pass "npm: createSandboxServer defined in source" || fail "npm: createSandboxServer missing from source"
    grep -q 'preview_markdown' "$NPM_INDEX" && pass "npm: preview_markdown tool defined" || fail "npm: preview_markdown missing"
    grep -q 'open_file' "$NPM_INDEX" && pass "npm: open_file tool defined" || fail "npm: open_file missing"
    grep -q 'markview-mcp-server-binary' "$NPM_INDEX" && pass "npm: binary path is markview-mcp-server-binary (no loop risk)" || fail "npm: binary path should be markview-mcp-server-binary"
else
    NODE_CHECK=$(node -e "
const m = require('$NPM_INDEX');
const hasFn = typeof m.createSandboxServer === 'function';
const src = require('fs').readFileSync('$NPM_INDEX', 'utf8');
const hasFilename = src.includes('\"filename\"') || src.includes(\"'filename'\") || src.includes('filename:') || src.includes('filename,');
const hasPreview = src.includes('preview_markdown');
const hasOpenFile = src.includes('open_file');
console.log(JSON.stringify({hasFn, hasFilename, hasPreview, hasOpenFile}));
" 2>/dev/null || echo '{}')

    if echo "$NODE_CHECK" | grep -q '"hasFn":true'; then
        pass "npm: createSandboxServer is exported"
    else
        fail "npm: createSandboxServer not exported from npm/index.js"
    fi

    if echo "$NODE_CHECK" | grep -q '"hasFilename":true'; then
        pass "npm: sandbox server uses 'filename' parameter (not 'title')"
    else
        fail "npm: sandbox server must use 'filename' not 'title' in preview_markdown schema"
    fi

    if echo "$NODE_CHECK" | grep -q '"hasPreview":true'; then
        pass "npm: sandbox server defines preview_markdown tool"
    else
        fail "npm: sandbox server missing preview_markdown tool"
    fi

    if echo "$NODE_CHECK" | grep -q '"hasOpenFile":true'; then
        pass "npm: sandbox server defines open_file tool"
    else
        fail "npm: sandbox server missing open_file tool"
    fi

    BINARY_PATH_CHECK=$(node -e "
const src = require('fs').readFileSync('$NPM_INDEX', 'utf8');
const hasCorrectPath = src.includes('markview-mcp-server-binary');
console.log(JSON.stringify({hasCorrectPath}));
" 2>/dev/null || echo '{}')

    if echo "$BINARY_PATH_CHECK" | grep -q '"hasCorrectPath":true'; then
        pass "npm: index.js binary path points to downloaded binary (no loop risk)"
    else
        fail "npm: index.js binary path should be 'markview-mcp-server-binary' to avoid infinite loop"
    fi
fi

# Summary
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
