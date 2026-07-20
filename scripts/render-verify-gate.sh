#!/usr/bin/env bash
# bash-justified: thin wrapper — exec-delegates to render_verify_gate.py immediately
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/render_verify_gate.py" "$@"
