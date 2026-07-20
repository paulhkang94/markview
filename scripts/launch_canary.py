#!/usr/bin/env python3
"""
launch_canary.py — GUI launch canary for MarkView's restore-loop hang class
(mar-033 Tier-B "Layer 2" plan, mar-039).

Three shipped hang classes (#55, #57, #59) plus a fourth (mar-037) all lived
on the app's launch/restore-all-tabs path (MV-001) and were only ever
regression-tested via source-inspection, because the app-target Swift files
were outside MarkViewTestRunner's dependency graph until mar-033 moved them
into MarkViewAppCore. Even the resulting main-thread budget test
(MarkViewTestRunner) never constructs a real WKWebView/Coordinator — this
script closes that gap: it launches the REAL .app with a real fixture file,
the same way a user's "reopen with N tabs" launch does, and waits for a
sentinel the app only prints once the restore loop and a first-render settle
finish (see LaunchCanary in Sources/MarkView/MarkViewApp.swift). If a future
change reintroduces a main-thread block anywhere on that path, the app's
main thread never reaches the print, and this script times out.

This is advisory (continue-on-error in CI), not a required gate — WKWebView
navigation is known to be unreliable on headless CI runners (see the
existing visual-smoke job) — but is a strict pass/fail signal locally,
where a display is available.

Usage:
    python3 scripts/launch_canary.py [--app PATH] [--timeout SECONDS] [--fixture PATH]

Exit 0: the LAUNCH_OK sentinel was observed on stderr within the timeout.
Exit 1: timeout, or the app executable could not be found/launched. On
        timeout (and only for a real launch — --sample-dir is not set by the
        test suite), a best-effort `sample <pid>` spindump is captured for
        diagnosis.
"""

from __future__ import annotations

import argparse
import os
import select
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import IO, Optional, Tuple

SENTINEL = "LAUNCH_OK"
DEFAULT_APP = Path("/Applications/MarkView.app")
DEFAULT_TIMEOUT = 20.0
CANARY_ENV_VAR = "MARKVIEW_LAUNCH_CANARY"


def wait_for_sentinel(
    stream: IO[str], deadline: float, sentinel: str = SENTINEL
) -> Tuple[bool, float]:
    """Read lines from `stream` until an exact `sentinel` line appears or
    `deadline` (an absolute time.monotonic() value) passes.

    Split out of run_canary so the timeout/detection logic is testable
    against a plain io.StringIO or a stub process's real pipe, without ever
    launching the actual GUI app.

    Uses select() to bound each read to the remaining time instead of calling
    stream.readline() directly: a plain readline() blocks until data arrives
    OR the pipe's write end closes, and a subprocess's stderr fd can outlive
    the direct child (e.g. a shell that execs a background grandchild which
    inherits the fd) — in that case readline() would ignore `deadline`
    entirely and hang for however long that fd stays open, defeating the
    whole point of a bounded canary. io.StringIO (used by the pure-logic
    tests) has no real fd, so select() falls back to the plain-readline path
    for anything that isn't select()-able.
    """
    start = time.monotonic()
    fileno = None
    try:
        fileno = stream.fileno()
    except (AttributeError, OSError, ValueError):
        # io.StringIO.fileno() raises io.UnsupportedOperation (a subclass of
        # both OSError and ValueError across supported Python versions) —
        # fall back to a plain (unbounded-select, but deadline-checked-between-
        # lines) readline loop for in-memory streams used by the pure-logic tests.
        fileno = None

    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        if fileno is not None:
            ready, _, _ = select.select([fileno], [], [], remaining)
            if not ready:
                continue  # select's own timeout elapsed — loop re-checks deadline
        line = stream.readline()
        if not line:
            # EOF — the process exited (or closed stderr) without ever
            # printing the sentinel. Don't spin on an exhausted stream.
            break
        if line.strip() == sentinel:
            return True, time.monotonic() - start
    return False, time.monotonic() - start


def capture_diagnostic_sample(pid: int, out_path: Path, duration: int = 5) -> bool:
    """Best-effort `sample <pid>` spindump on timeout, for CI artifact upload
    and local debugging (this is exactly how the #48 hang report that led to
    the #55 fix was originally diagnosed — see JSBundleCache's docstring).
    Returns False (non-fatal) if `sample` itself fails or the target PID is
    invalid; a diagnostics failure must never mask the real canary failure.
    """
    try:
        subprocess.run(
            ["sample", str(pid), str(duration), "-f", str(out_path)],
            capture_output=True,
            timeout=duration + 10,
            check=False,
        )
        return out_path.exists()
    except (OSError, subprocess.SubprocessError):
        return False


def _terminate_process_group(proc: "subprocess.Popen[str]") -> None:
    """Signal the whole process group (see start_new_session=True above),
    escalating from SIGTERM to SIGKILL, then reap it. Best-effort: the group
    or process may already be gone by the time we get here."""
    try:
        pgid = os.getpgid(proc.pid)
    except (ProcessLookupError, OSError):
        pgid = None

    def send(sig: int) -> None:
        if pgid is not None:
            try:
                os.killpg(pgid, sig)
                return
            except (ProcessLookupError, OSError):
                pass
        try:
            proc.send_signal(sig)
        except (ProcessLookupError, OSError):
            pass

    send(signal.SIGTERM)
    try:
        proc.wait(timeout=5)
        return
    except subprocess.TimeoutExpired:
        pass
    send(signal.SIGKILL)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass  # nothing more we can do — don't hang the caller on a stuck kill


def run_canary(
    app_path: Path,
    fixture_path: Path,
    timeout: float,
    sample_dir: Optional[Path] = None,
) -> int:
    """Launch `app_path`'s executable with `fixture_path` as argv[1] and
    MARKVIEW_LAUNCH_CANARY=1 set, then wait up to `timeout` seconds for the
    LAUNCH_OK sentinel on stderr. Returns a process-style exit code (0/1)."""
    exe = app_path / "Contents" / "MacOS" / "MarkView"
    if not exe.is_file():
        print(f"launch_canary: executable not found at {exe}", file=sys.stderr)
        return 1

    env = dict(os.environ)
    env[CANARY_ENV_VAR] = "1"

    try:
        proc = subprocess.Popen(
            [str(exe), str(fixture_path)],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            # New session/process group so cleanup below can signal any
            # grandchildren too (e.g. a test stub script's own children) —
            # without this, terminate()/kill() only reach the direct child,
            # and an orphaned grandchild can keep our stderr pipe's write end
            # open indefinitely.
            start_new_session=True,
        )
    except OSError as exc:
        print(f"launch_canary: failed to launch {exe}: {exc}", file=sys.stderr)
        return 1

    try:
        deadline = time.monotonic() + timeout
        found, elapsed = wait_for_sentinel(proc.stderr, deadline)
        if found:
            print(f"launch_canary: {SENTINEL} observed after {elapsed:.2f}s")
            return 0

        print(
            f"launch_canary: TIMEOUT after {timeout}s waiting for {SENTINEL} "
            "— a regression may have reintroduced a main-thread block on the "
            "restore-loop launch path",
            file=sys.stderr,
        )
        if sample_dir is not None:
            sample_dir.mkdir(parents=True, exist_ok=True)
            out = sample_dir / "launch-canary-hang.sample.txt"
            if capture_diagnostic_sample(proc.pid, out):
                print(f"launch_canary: captured diagnostic sample at {out}", file=sys.stderr)
        return 1
    finally:
        _terminate_process_group(proc)
        if proc.stderr is not None:
            proc.stderr.close()


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--app", type=Path, default=DEFAULT_APP, help="path to MarkView.app")
    parser.add_argument(
        "--timeout", type=float, default=DEFAULT_TIMEOUT, help="seconds to wait for the sentinel"
    )
    parser.add_argument(
        "--fixture",
        type=Path,
        default=None,
        help="markdown file to open (a small temp file is generated if omitted)",
    )
    parser.add_argument(
        "--sample-dir",
        type=Path,
        default=Path("/tmp/markview-launch-canary"),
        help="directory for the on-timeout diagnostic sample; pass an empty string to disable",
    )
    args = parser.parse_args(argv)

    fixture = args.fixture
    cleanup = False
    if fixture is None:
        fd, path = tempfile.mkstemp(suffix=".md", prefix="markview-launch-canary-")
        os.close(fd)
        fixture = Path(path)
        fixture.write_text("# Launch canary\n\nGenerated by scripts/launch_canary.py.\n")
        cleanup = True

    sample_dir = args.sample_dir if str(args.sample_dir) else None

    try:
        return run_canary(args.app, fixture, args.timeout, sample_dir=sample_dir)
    finally:
        if cleanup:
            fixture.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
