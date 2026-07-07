#!/usr/bin/env python3
"""PostToolUse auto-formatter — universal, language-dispatched.

Reads the hook event JSON on stdin, extracts the edited file's path, and runs the
right formatter for its extension. Consolidates the former scripts/claude-format.sh
dispatcher plus the 12 scripts/formatters/{lang}.sh wrappers into one file (M7-5,
approach A): every repo installs this same script instead of a per-language copy,
so a mixed-language repo now formats every language it touches.

Each language preserves the exact tool chain and fallback order of its bash
original. Always exits 0 — a PostToolUse formatter must never fail the edit — and
formats only when the tool is actually installed. jq is replaced by the json
stdlib.

    echo "$HOOK_JSON" | ./scripts/claude_format.py
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def _run(cmd: list[str]) -> None:
    """Run a formatter, swallowing all output and errors (best-effort, in-place)."""
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except OSError:
        pass


def _fmt_python(fp: str) -> None:
    if shutil.which("ruff"):
        _run(["ruff", "format", "--quiet", fp])
        _run(["ruff", "check", "--fix", "--quiet", fp])
    elif shutil.which("black"):
        _run(["black", "--quiet", fp])
        _run(["isort", "--quiet", fp])


def _fmt_swift(fp: str) -> None:
    pods = REPO_ROOT / "Pods" / "SwiftFormat" / "CommandLineTool" / "swiftformat"
    if os.access(pods, os.X_OK):
        _run([str(pods), fp])
    elif shutil.which("swiftformat"):
        _run(["swiftformat", fp])


def _fmt_typescript(fp: str) -> None:
    npx = shutil.which("npx")
    if (REPO_ROOT / "biome.json").is_file() or (REPO_ROOT / "biome.jsonc").is_file():
        if npx:
            _run(["npx", "@biomejs/biome", "format", "--write", fp])
    elif (REPO_ROOT / "dprint.json").is_file():
        if npx:
            _run(["npx", "dprint", "fmt", fp])
    elif npx:
        _run(["npx", "prettier", "--write", fp])


def _fmt_go(fp: str) -> None:
    gopath = ""
    try:
        gopath = subprocess.run(
            ["go", "env", "GOPATH"], capture_output=True, text=True, check=False
        ).stdout.strip()
    except OSError:
        gopath = ""
    candidates = [
        f"{gopath}/bin" if gopath else "",
        str(Path.home() / "go" / "bin"),
        "/usr/local/go/bin",
        "/usr/local/bin",
        "/opt/homebrew/bin",
    ]
    for d in candidates:
        if not d:
            continue
        goimports = Path(d) / "goimports"
        if os.access(goimports, os.X_OK):
            _run([str(goimports), "-w", fp])
            return
    _run(["gofmt", "-w", fp])


def _fmt_rust(fp: str) -> None:
    if shutil.which("rustfmt"):
        _run(["rustfmt", "--edition", "2021", fp])


def _fmt_ruby(fp: str) -> None:
    if shutil.which("rubocop"):
        _run(["rubocop", "--autocorrect", "--no-color", fp])
    elif shutil.which("rufo"):
        _run(["rufo", fp])


def _fmt_java(fp: str) -> None:
    if shutil.which("google-java-format"):
        _run(["google-java-format", "--replace", fp])
    elif shutil.which("npx") and (REPO_ROOT / "node_modules" / ".bin" / "prettier").is_file():
        _run(["npx", "prettier", "--write", fp])


def _fmt_kotlin(fp: str) -> None:
    if shutil.which("ktlint"):
        _run(["ktlint", "--format", fp])
    else:
        print(
            "[WARN] ktlint not in PATH — formatting skipped. Install: brew install ktlint",
            file=sys.stderr,
        )


def _fmt_php(fp: str) -> None:
    if shutil.which("php-cs-fixer"):
        _run(["php-cs-fixer", "fix", "--quiet", fp])
    elif shutil.which("phpcbf"):
        _run(["phpcbf", "--quiet", fp])


def _fmt_csharp(fp: str) -> None:
    if shutil.which("dotnet"):
        _run(["dotnet", "format", str(REPO_ROOT), "--include", fp, "--no-restore"])
    elif shutil.which("dotnet-csharpier"):
        _run(["dotnet-csharpier", fp])


def _fmt_scala(fp: str) -> None:
    if shutil.which("scalafmt"):
        _run(["scalafmt", "--quiet", fp])
    elif shutil.which("npx"):
        _run(["npx", "scalafmt", "--quiet", fp])


def _fmt_c(fp: str) -> None:
    if shutil.which("clang-format"):
        _run(["clang-format", "-i", fp])


# Extension → formatter. Mirrors the per-language .sh dispatch in claude-format.sh.
_DISPATCH = {
    ".py": _fmt_python,
    ".swift": _fmt_swift,
    ".ts": _fmt_typescript,
    ".tsx": _fmt_typescript,
    ".js": _fmt_typescript,
    ".jsx": _fmt_typescript,
    ".mjs": _fmt_typescript,
    ".cjs": _fmt_typescript,
    ".json": _fmt_typescript,
    ".go": _fmt_go,
    ".rs": _fmt_rust,
    ".rb": _fmt_ruby,
    ".java": _fmt_java,
    ".kt": _fmt_kotlin,
    ".kts": _fmt_kotlin,
    ".php": _fmt_php,
    ".cs": _fmt_csharp,
    ".scala": _fmt_scala,
    ".sc": _fmt_scala,
    ".c": _fmt_c,
    ".cpp": _fmt_c,
    ".cc": _fmt_c,
    ".cxx": _fmt_c,
    ".h": _fmt_c,
    ".hpp": _fmt_c,
    ".hxx": _fmt_c,
}


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return 0
    if not isinstance(payload, dict):
        return 0

    tool_input = payload.get("tool_input")
    file_path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    if not file_path:
        return 0

    handler = _DISPATCH.get(Path(file_path).suffix.lower())
    if handler is not None:
        handler(file_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
