#!/usr/bin/env python3
"""Exercise the app's actual window bridge in an isolated, invisible AppKit process."""

import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = r"""
import AppKit

@main
struct WindowFrameFixture {
    @MainActor
    static func main() {
        let failures = runChecks()
        for failure in failures { print("FAIL: \(failure)") }
        if !failures.isEmpty { exit(1) }
        print("Window frame checks: 4 passed")
    }

    @MainActor
    static func runChecks() -> [String] {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let name = "MarkViewFixture-" + UUID().uuidString
        let freshName = "MarkViewFixture-" + UUID().uuidString
        func window(_ rect: NSRect) -> NSWindow {
            let result = NSWindow(contentRect: rect, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            result.isReleasedWhenClosed = false
            return result
        }
        var failures: [String] = []
        func check(_ value: Bool, _ message: String) {
            if !value { failures.append(message) }
        }
        let saved = window(NSRect(x: 40, y: 60, width: 840, height: 560))
        let expected = saved.frame
        saved.saveFrame(usingName: name)
        let target = window(NSRect(x: 120, y: 140, width: 620, height: 420))
        let fresh = window(NSRect(x: 80, y: 100, width: 640, height: 440))
        defer {
            for item in [saved, target, fresh] {
                item.setFrameAutosaveName("")
                item.close()
            }
            NSWindow.removeFrame(usingName: name)
            NSWindow.removeFrame(usingName: freshName)
        }
        let savedBefore = saved.frame
        let probe = WindowFrameAutosaveView(name: name)
        target.contentView!.addSubview(probe)
        check(target.frame == expected, "saved frame was not restored on the owning window")
        check(target.frameAutosaveName == name && saved.frame == savedBefore, "autosave targeted another window")

        target.setFrame(NSRect(x: 90, y: 110, width: 860, height: 580), display: false)
        let userFrame = target.frame
        probe.configureWindowIfNeeded()
        check(target.frame == userFrame, "repeat configuration overwrote the user's current frame")

        let firstFrame = fresh.frame
        let firstProbe = WindowFrameAutosaveView(name: freshName)
        fresh.contentView!.addSubview(firstProbe)
        check(fresh.frame == firstFrame && fresh.frameAutosaveName == freshName, "first launch geometry changed without saved data")
        return failures
    }
}
"""


@unittest.skipUnless(sys.platform == "darwin", "AppKit requires macOS")
class WindowFrameTests(unittest.TestCase):
    def test_native_window_restore_ownership_and_repeat_behavior(self):
        with tempfile.TemporaryDirectory(prefix="markview-window-frame-") as directory:
            root = Path(directory)
            fixture = root / "Fixture.swift"
            fixture.write_text(FIXTURE)
            binary = root / ("MarkViewWindowFrameFixture-" + uuid.uuid4().hex)
            compiled = subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    str(ROOT / "Sources/MarkView/WindowFrameAutosave.swift"),
                    str(fixture),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
                timeout=120,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            try:
                result = subprocess.run(
                    [str(binary)], capture_output=True, text=True, timeout=30
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Window frame checks: 4 passed", result.stdout)
            finally:
                # The standalone binary has a unique defaults domain, never MarkView's.
                subprocess.run(
                    ["defaults", "delete", binary.name], capture_output=True, timeout=10
                )
                (Path.home() / "Library/Preferences" / f"{binary.name}.plist").unlink(
                    missing_ok=True
                )


if __name__ == "__main__":
    unittest.main()
