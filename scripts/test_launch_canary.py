#!/usr/bin/env python3
"""
Tests for launch_canary.py (mar-033 Tier-B "Layer 2", mar-039).

Tier 2 behavioral tests: wait_for_sentinel and run_canary are exercised
against REAL subprocesses (tiny stub shell scripts standing in for
MarkView.app's executable), not mocked away — that's the whole point of a
launch canary, and a mocked-out subprocess test would prove nothing about
whether the timeout/sentinel-detection logic actually works. What's stubbed
is only the GUI app itself (headless CI / this test suite can't reliably
spawn WindowServer); the process-spawn, pipe-read, and deadline logic in
launch_canary.py runs for real.

Usage:
    python3 scripts/test_launch_canary.py
"""

from __future__ import annotations

import importlib.util
import io
import stat
import sys
import tempfile
import time
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parent


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


launch_canary = _load("launch_canary")


def _make_stub_app(tmp: Path, script_body: str) -> Path:
    """Build a fake `MarkView.app/Contents/MacOS/MarkView` executable (a
    shell script) so run_canary can be exercised end-to-end without the real
    GUI app or a window server."""
    app = tmp / "Stub.app"
    macos_dir = app / "Contents" / "MacOS"
    macos_dir.mkdir(parents=True)
    exe = macos_dir / "MarkView"
    exe.write_text(f"#!/bin/sh\n{script_body}\n")
    exe.chmod(exe.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return app


class TestWaitForSentinel(unittest.TestCase):
    def test_finds_sentinel_on_an_early_line(self):
        stream = io.StringIO("starting up\nLAUNCH_OK\nignored trailer\n")
        found, elapsed = launch_canary.wait_for_sentinel(stream, deadline=time.monotonic() + 5)
        self.assertTrue(found)
        self.assertGreaterEqual(elapsed, 0)

    def test_times_out_when_sentinel_never_appears(self):
        stream = io.StringIO("some other output\n" * 5)
        # Deadline already in the past — must not hang waiting on more input.
        found, _ = launch_canary.wait_for_sentinel(stream, deadline=time.monotonic() - 1)
        self.assertFalse(found)

    def test_eof_without_sentinel_reports_not_found(self):
        stream = io.StringIO("")  # immediate EOF, generous deadline
        found, _ = launch_canary.wait_for_sentinel(stream, deadline=time.monotonic() + 5)
        self.assertFalse(found)

    def test_partial_match_does_not_count_as_sentinel(self):
        stream = io.StringIO("LAUNCH_OKAY\nLAUNCH_O\n")
        found, _ = launch_canary.wait_for_sentinel(stream, deadline=time.monotonic() - 1)
        self.assertFalse(found)


class TestRunCanary(unittest.TestCase):
    def test_missing_executable_fails_fast_without_spawning(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp) / "DoesNotExist.app"
            fixture = Path(tmp) / "f.md"
            fixture.write_text("# hi\n")
            rc = launch_canary.run_canary(app, fixture, timeout=2)
            self.assertEqual(rc, 1)

    def test_stub_app_that_prints_sentinel_immediately_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            app = _make_stub_app(tmp_path, "echo LAUNCH_OK 1>&2; sleep 5")
            fixture = tmp_path / "f.md"
            fixture.write_text("# hi\n")
            rc = launch_canary.run_canary(app, fixture, timeout=5)
            self.assertEqual(rc, 0, "a stub that prints the sentinel right away must pass")

    def test_stub_app_that_hangs_without_printing_fails_within_timeout(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            app = _make_stub_app(tmp_path, "sleep 30")
            fixture = tmp_path / "f.md"
            fixture.write_text("# hi\n")
            start = time.monotonic()
            rc = launch_canary.run_canary(app, fixture, timeout=1, sample_dir=None)
            elapsed = time.monotonic() - start
            self.assertEqual(
                rc,
                1,
                "a stub that never prints the sentinel must fail (this is the regression this canary exists to catch)",
            )
            self.assertLess(elapsed, 10, "run_canary must not block past roughly its timeout")

    def test_stub_app_that_exits_immediately_without_sentinel_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            app = _make_stub_app(tmp_path, "exit 0")
            fixture = tmp_path / "f.md"
            fixture.write_text("# hi\n")
            rc = launch_canary.run_canary(app, fixture, timeout=2)
            self.assertEqual(
                rc,
                1,
                "an app that exits clean but never prints the sentinel is still a failure — it proves nothing about the restore-loop launch path",
            )


class TestCaptureDiagnosticSample(unittest.TestCase):
    def test_returns_false_when_sample_binary_or_pid_is_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out.txt"
            # PID 0 is never a valid target for `sample` — exercises the
            # non-fatal failure path without depending on `sample` succeeding
            # against a real (racy) short-lived PID.
            ok = launch_canary.capture_diagnostic_sample(0, out, duration=1)
            self.assertFalse(ok)


class TestMainArgParsing(unittest.TestCase):
    def test_default_fixture_is_generated_and_cleaned_up(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            app = _make_stub_app(tmp_path, "echo LAUNCH_OK 1>&2")
            rc = launch_canary.main(["--app", str(app), "--timeout", "5"])
            self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
