#!/usr/bin/env bash
# bash-justified: thin wrapper — exec-delegates to metrics.py immediately
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/metrics.py" "$@"
