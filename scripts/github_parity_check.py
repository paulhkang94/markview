#!/usr/bin/env python3
"""
github_parity_check.py — structural comparison of MarkView vs GitHub rendering.

Uses the GitHub Markdown API to render golden-corpus.md and compares the
heading/table/code structure against MarkView's own output.

Run before major releases. Not in CI (requires GitHub API, rate-limited).
Auth recommended: GITHUB_TOKEN env var for higher rate limits.

Usage:
    python3 scripts/github_parity_check.py
    GITHUB_TOKEN=ghp_xxx python3 scripts/github_parity_check.py
    bash scripts/github-parity-check.sh   (thin wrapper)
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CORPUS = REPO_ROOT / "Tests/TestRunner/Fixtures/golden-corpus.md"
GEN_BIN = REPO_ROOT / ".build/release/MarkViewHTMLGen"

HEADING_RE = re.compile(r"<h([1-6])[^>]*>")
TABLE_RE = re.compile(r"<table")
CODE_LANG_RE = re.compile(r'class="language-([a-z]+)"')
GITHUB_TASK_RE = re.compile(r'<li class="task-list-item')
MARKVIEW_TASK_RE = re.compile(r'type="checkbox"')


# ── Structural extraction (pure functions — testable without any network) ──


def extract_heading_counts(html: str) -> Counter:
    return Counter(f"h{level}" for level in HEADING_RE.findall(html))


def extract_table_count(html: str) -> int:
    return len(TABLE_RE.findall(html))


def extract_code_lang_counts(html: str) -> Counter:
    return Counter(CODE_LANG_RE.findall(html))


def extract_task_count(html: str, *, source: str) -> int:
    pattern = GITHUB_TASK_RE if source == "github" else MARKVIEW_TASK_RE
    return len(pattern.findall(html))


# ── GitHub API ───────────────────────────────────────────────────────────────


def fetch_github_render(markdown_text: str, github_token: str | None) -> str:
    """POST to the GitHub Markdown API and return the rendered HTML.
    Raises RuntimeError on transport failure or rate limiting."""
    body = json.dumps({"text": markdown_text, "mode": "gfm"}).encode()
    headers = {
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
    }
    if github_token:
        headers["Authorization"] = f"Bearer {github_token}"

    req = urllib.request.Request(
        "https://api.github.com/markdown", data=body, headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.read().decode()
    except urllib.error.HTTPError as e:
        text = e.read().decode(errors="replace")
        if "rate limit" in text.lower() or "api rate" in text.lower():
            raise RuntimeError(
                "GitHub API rate limited. Set GITHUB_TOKEN for higher limits."
            ) from e
        raise RuntimeError(f"GitHub API request failed: {e}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"GitHub API request failed: {e}") from e


def render_markview(corpus: Path, gen_bin: Path) -> str:
    if not gen_bin.is_file():
        print("Building MarkViewHTMLGen...")
        subprocess.run(
            ["swift", "build", "-c", "release", "--product", "MarkViewHTMLGen"],
            cwd=REPO_ROOT,
            check=True,
        )
    result = subprocess.run(
        [str(gen_bin), str(corpus)], capture_output=True, text=True, check=True
    )
    return result.stdout


# ── Report ───────────────────────────────────────────────────────────────────


def format_counter(counter: Counter) -> str:
    if not counter:
        return "(none)"
    return "  ".join(f"{count} {key}" for key, count in counter.most_common())


def print_report(github_html: str, markview_html: str) -> bool:
    """Prints the structural comparison; returns True if headings match
    (used only for the summary emoji, not the exit code — this check is
    advisory by design)."""
    print()
    print("--- Heading structure ---")
    gh_headings = extract_heading_counts(github_html)
    mv_headings = extract_heading_counts(markview_html)
    print(f"GitHub:  {format_counter(gh_headings)}")
    print(f"MarkView: {format_counter(mv_headings)}")
    headings_match = gh_headings == mv_headings
    if headings_match:
        print("Headings match")
    else:
        print("Heading counts differ")

    print()
    print("--- Table structure ---")
    gh_tables = extract_table_count(github_html)
    mv_tables = extract_table_count(markview_html)
    print(f"GitHub tables:   {gh_tables}")
    print(f"MarkView tables: {mv_tables}")
    print("Table counts match" if gh_tables == mv_tables else "Table counts differ")

    print()
    print("--- Code block languages ---")
    gh_langs = extract_code_lang_counts(github_html)
    mv_langs = extract_code_lang_counts(markview_html)
    print(f"GitHub:   {format_counter(gh_langs)}")
    print(f"MarkView: {format_counter(mv_langs)}")

    print()
    print("--- Task lists ---")
    gh_tasks = extract_task_count(github_html, source="github")
    mv_tasks = extract_task_count(markview_html, source="markview")
    print(f"GitHub task items:   {gh_tasks}")
    print(f"MarkView checkboxes: {mv_tasks}")

    print()
    print("=== Parity check complete ===")
    print(
        "Note: Differences in alert/TOC/KaTeX/Mermaid are expected (MarkView extensions)."
    )

    return headings_match


def main(argv: list[str] | None = None) -> int:
    print("=== MarkView vs GitHub Parity Check ===")
    print(f"Corpus: {CORPUS}")
    print()

    if not CORPUS.is_file():
        print(f"ERROR: corpus not found at {CORPUS}", file=sys.stderr)
        return 1

    github_token = os.environ.get("GITHUB_TOKEN")

    print("Fetching GitHub rendering...")
    try:
        github_html = fetch_github_render(CORPUS.read_text(), github_token)
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1

    print("Rendering via MarkView...")
    try:
        markview_html = render_markview(CORPUS, GEN_BIN)
    except subprocess.CalledProcessError as e:
        print(f"ERROR: MarkViewHTMLGen failed: {e}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        (tmp_dir / "github.html").write_text(github_html)
        (tmp_dir / "markview.html").write_text(markview_html)
        print_report(github_html, markview_html)
        print(f"Full output saved to: {tmp_dir}/")

    return 0


if __name__ == "__main__":
    sys.exit(main())
