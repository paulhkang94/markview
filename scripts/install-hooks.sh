#!/usr/bin/env bash
# Install tracked git hooks from scripts/. Run after cloning or when hooks change.
# SSOT: scripts/pre-commit-hook.sh — the live .git/hooks/pre-commit is a shim that calls it.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/usr/bin/env bash
# Shim — delegates to tracked SSOT: scripts/pre-commit-hook.sh
exec "$(git rev-parse --show-toplevel)/scripts/pre-commit-hook.sh" "$@"
EOF
chmod +x "$HOOKS_DIR/pre-commit"

echo "✓ Installed: .git/hooks/pre-commit → scripts/pre-commit-hook.sh"
