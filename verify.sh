#!/usr/bin/env bash
# Thin exec wrapper — all logic lives in scripts/verify.py.
# Kept for backward compatibility with any scripts or muscle memory that call verify.sh.
# To update verification behavior, edit scripts/verify.py instead.
exec python3 "$(cd "$(dirname "$0")" && pwd)/scripts/verify.py" "$@"
