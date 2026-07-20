#!/usr/bin/env python3
"""
Tests for post_launch.py.

Tier 2 behavioral tests — verify URL construction and report formatting
without ever opening a real browser tab (open_urls is never called except
through a mocked subprocess.run).

Usage:
    python3 scripts/test-post-launch.py
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
import urllib.parse
from io import StringIO
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).parent


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    # Register before exec: post_launch.Post is a dataclass, and dataclass's
    # class-creation-time introspection needs cls.__module__ resolvable via
    # sys.modules — without this, exec_module raises AttributeError.
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


class TestPostLaunchImport(unittest.TestCase):
    def test_imports_cleanly(self):
        mod = _load("post_launch")
        self.assertTrue(hasattr(mod, "main"))
        self.assertTrue(hasattr(mod, "build_urls"))
        self.assertTrue(hasattr(mod, "POSTS"))


class TestBuildUrls(unittest.TestCase):
    def setUp(self):
        self.m = _load("post_launch")

    def test_returns_one_url_per_post(self):
        urls = self.m.build_urls()
        self.assertEqual(len(urls), len(self.m.POSTS))
        for post in self.m.POSTS:
            self.assertIn(post.section, urls)

    def test_hn_url_contains_encoded_repo_and_title(self):
        urls = self.m.build_urls()
        hn_url = urls["HACKER NEWS — Show HN"]
        self.assertIn("news.ycombinator.com/submitlink", hn_url)
        self.assertIn(urllib.parse.quote(self.m.REPO_URL), hn_url)
        self.assertIn(urllib.parse.quote(self.m.HN_TITLE), hn_url)

    def test_reddit_urls_target_correct_subreddits(self):
        urls = self.m.build_urls()
        self.assertIn("r/ClaudeAI", urls["REDDIT — r/ClaudeAI"])
        self.assertIn("r/cursor", urls["REDDIT — r/cursor"])
        self.assertIn("r/macapps", urls["REDDIT — r/macapps"])

    def test_title_special_characters_are_url_safe(self):
        # Titles contain em-dashes, "+", ":" — verify no raw special chars leak.
        for url in self.m.build_urls().values():
            self.assertNotIn(" ", url)


class TestPrintReport(unittest.TestCase):
    def setUp(self):
        self.m = _load("post_launch")

    def test_report_includes_all_titles_and_urls(self):
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            self.m.print_report()
        output = mock_out.getvalue()
        for post in self.m.POSTS:
            self.assertIn(post.title, output)
            self.assertIn(post.section, output)
        self.assertIn("SUBMISSION URLS", output)


class TestOpenUrls(unittest.TestCase):
    def setUp(self):
        self.m = _load("post_launch")

    def test_calls_open_for_each_url(self):
        urls = {"a": "http://example.com/a", "b": "http://example.com/b"}
        with patch.object(self.m.subprocess, "run") as mock_run:
            self.m.open_urls(urls)
        self.assertEqual(mock_run.call_count, 2)
        called_urls = {call.args[0][-1] for call in mock_run.call_args_list}
        self.assertEqual(called_urls, set(urls.values()))


class TestMainDryRun(unittest.TestCase):
    def setUp(self):
        self.m = _load("post_launch")

    def test_dry_run_never_calls_open(self):
        with (
            patch.object(self.m.subprocess, "run") as mock_run,
            patch("sys.stdout", new_callable=StringIO) as mock_out,
        ):
            rc = self.m.main(["--dry-run"])
        self.assertEqual(rc, 0)
        mock_run.assert_not_called()
        self.assertIn("Dry run", mock_out.getvalue())

    def test_non_dry_run_opens_all_urls(self):
        with (
            patch.object(self.m.subprocess, "run") as mock_run,
            patch("sys.stdout", new_callable=StringIO),
        ):
            rc = self.m.main([])
        self.assertEqual(rc, 0)
        self.assertEqual(mock_run.call_count, len(self.m.POSTS))


class TestThinWrapper(unittest.TestCase):
    def test_post_launch_sh_delegates_to_python(self):
        wrapper = (SCRIPTS / "post-launch.sh").read_text()
        self.assertIn("post_launch.py", wrapper)
        self.assertIn("exec python3", wrapper)
        self.assertIn("bash-justified", wrapper)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(__import__("__main__"))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
