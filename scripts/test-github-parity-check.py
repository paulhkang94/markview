#!/usr/bin/env python3
"""
Tests for github_parity_check.py.

Tier 2 behavioral tests — verify HTML structural extraction and report
formatting against fixture HTML strings. GitHub API and MarkViewHTMLGen
calls are mocked; no live network, no swift build.

Usage:
    python3 scripts/test-github-parity-check.py
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).parent


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestImport(unittest.TestCase):
    def test_imports_cleanly(self):
        mod = _load("github_parity_check")
        self.assertTrue(hasattr(mod, "main"))
        self.assertTrue(hasattr(mod, "print_report"))


class TestExtraction(unittest.TestCase):
    def setUp(self):
        self.m = _load("github_parity_check")

    def test_extract_heading_counts(self):
        html = '<h1>A</h1><h2>B</h2><h2 class="x">C</h2>'
        counts = self.m.extract_heading_counts(html)
        self.assertEqual(counts["h1"], 1)
        self.assertEqual(counts["h2"], 2)

    def test_extract_table_count(self):
        html = "<table><tr></tr></table><table></table>"
        self.assertEqual(self.m.extract_table_count(html), 2)

    def test_extract_table_count_zero(self):
        self.assertEqual(self.m.extract_table_count("<p>no tables</p>"), 0)

    def test_extract_code_lang_counts(self):
        html = '<code class="language-python">x</code><code class="language-python">y</code><code class="language-swift">z</code>'
        counts = self.m.extract_code_lang_counts(html)
        self.assertEqual(counts["python"], 2)
        self.assertEqual(counts["swift"], 1)

    def test_extract_task_count_github(self):
        html = '<li class="task-list-item">a</li><li class="task-list-item">b</li><li>c</li>'
        self.assertEqual(self.m.extract_task_count(html, source="github"), 2)

    def test_extract_task_count_markview(self):
        html = '<input type="checkbox"><input type="checkbox">'
        self.assertEqual(self.m.extract_task_count(html, source="markview"), 2)


class TestPrintReport(unittest.TestCase):
    def setUp(self):
        self.m = _load("github_parity_check")

    def test_matching_headings_reported(self):
        html = "<h1>A</h1>"
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            matched = self.m.print_report(html, html)
        self.assertTrue(matched)
        self.assertIn("Headings match", mock_out.getvalue())

    def test_differing_headings_reported(self):
        gh = "<h1>A</h1><h2>B</h2>"
        mv = "<h1>A</h1>"
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            matched = self.m.print_report(gh, mv)
        self.assertFalse(matched)
        self.assertIn("Heading counts differ", mock_out.getvalue())

    def test_report_includes_all_sections(self):
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            self.m.print_report("<h1>x</h1>", "<h1>x</h1>")
        output = mock_out.getvalue()
        for heading in (
            "Heading structure",
            "Table structure",
            "Code block languages",
            "Task lists",
            "Parity check complete",
        ):
            self.assertIn(heading, output)


class TestFetchGithubRender(unittest.TestCase):
    def setUp(self):
        self.m = _load("github_parity_check")

    def test_rate_limit_raises_runtime_error(self):
        import urllib.error

        import io

        err = urllib.error.HTTPError(
            "url",
            403,
            "Forbidden",
            {},
            io.BytesIO(b'{"message": "API rate limit exceeded"}'),
        )
        with patch.object(self.m.urllib.request, "urlopen", side_effect=err):
            with self.assertRaises(RuntimeError) as ctx:
                self.m.fetch_github_render("# hi", None)
        self.assertIn("rate limit", str(ctx.exception).lower())

    def test_successful_fetch_returns_html(self):
        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

            def read(self):
                return b"<h1>rendered</h1>"

        with patch.object(
            self.m.urllib.request, "urlopen", return_value=FakeResponse()
        ):
            html = self.m.fetch_github_render("# hi", "faketoken")
        self.assertEqual(html, "<h1>rendered</h1>")


class TestThinWrapper(unittest.TestCase):
    def test_sh_delegates_to_python(self):
        wrapper = (SCRIPTS / "github-parity-check.sh").read_text()
        self.assertIn("github_parity_check.py", wrapper)
        self.assertIn("exec python3", wrapper)
        self.assertIn("bash-justified", wrapper)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(__import__("__main__"))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
