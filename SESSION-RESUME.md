# MarkView — Session Resume (2026-04-04)

Use this file to resume the next session. Start with `/catchup`.

---

## Resume Prompt

```
/catchup

Context: Completed a full v1.4.0 implementation session covering find/search (P0a),
diff2html + MCP tools (P0b), iOS MarkViewCore migration, Android device fixes,
and multi-platform E2E testing on Galaxy S25U + iPad (8).

Read first:
- /Users/pkang/repos/markview/SESSION-RESUME.md     ← this file
- /Users/pkang/repos/markview/docs/STATUS.md         ← living architecture doc
- /Users/pkang/repos/markview/docs/personal/progress-2026-04-04.md  ← week summary

Current state:
- macOS v1.4.0 shipped (commits c9c01cb + 18ea9d2), NOT yet tagged
- iOS: MarkViewCore migration complete, iPad installed, pending real-device Unicode verify
- Android: Working on Galaxy S25U, all fixes committed

PRIORITY ORDER for next session:
1. Tag v1.4.0 + push + npm bump (15 min)
2. iOS: Verify Unicode on physical iPad, E2ETester find bar tests (AX)
3. Android: File picker button + Samsung content:// intent filters + Prism.js
4. Android: Google Play developer account setup
5. macOS P1a: Diagram controls visual QA (15 min manual task)
```

---

## Prioritized Action Items

### P0 — Release v1.4.0 (15 min, do first)

```bash
cd ~/repos/markview
git tag v1.4.0
git push --tags
# Then bump npm: edit npm/package.json version 1.3.0 → 1.4.0
# npm publish from npm/ directory
```

verify.sh warns: "18 commit(s) since v1.3.0 — consider bumping version before release"

---

### P0 — Android: File Picker Button (~1 hour)

Add folder button (like iOS) to browse and open .md files using Android's system file picker.

**Pattern** (matches iOS `fileImporter` exactly):
```kotlin
// In MainActivity, add ActivityResultLauncher:
val openFileLauncher = registerForActivityResult(
    ActivityResultContracts.OpenDocument()
) { uri ->
    uri?.let {
        val text = contentResolver.openInputStream(it)?.use { s ->
            s.bufferedReader().readText()
        } ?: return@let
        currentMarkdown = text
        currentUri = it
    }
}

// In Compose, add folder button in top bar:
IconButton(onClick = { openFileLauncher.launch(arrayOf("text/markdown", "text/plain")) }) {
    Icon(Icons.Default.FolderOpen, contentDescription = "Open file")
}
```

Supports any MIME types we add in the future — just extend the array.

---

### P1 — Android: Samsung Galaxy content:// Intent Filters

Current manifest missing Samsung My Files content URI coverage. See IMPLEMENTATION-PLAN.md for full 7-filter manifest replacement. Key missing filter:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:scheme="content" android:mimeType="*/*"
          android:pathPattern=".*\\.md" />
</intent-filter>
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="application/octet-stream" />
</intent-filter>
```

Full plan: `~/repos/markview-android/IMPLEMENTATION-PLAN.md`

---

### P1 — Android: Prism.js Syntax Highlighting

Copy from macOS repo (already exists, no download needed):

```bash
cp ~/repos/markview/Sources/MarkViewCore/Resources/prism-bundle.min.js \
   ~/repos/markview-android/app/src/main/assets/
```

Add to template.html before `</body>`:
```html
<script src="prism-bundle.min.js"></script>
```

Prism auto-highlights `<code class="language-*">` which marked.js already produces. Zero JS changes needed.

---

### P1 — Android: Google Play Developer Account

1. Go to https://play.google.com/console
2. One-time $25 registration fee
3. Accept developer agreement
4. Create app listing: "MarkView — Markdown Viewer"
5. Generate signed release APK: `./gradlew bundleRelease` → AAB format for Play Store
6. Create keystore: `keytool -genkey -v -keystore markview-release.jks ...`

Store keystore in macOS Keychain, NOT in repo.

---

### P2 — iOS: E2ETester Find Bar Tests

9 test stubs already in `Tests/E2ETester/main.swift`. Need Accessibility permission to implement. Tests:
- findBar_opensOnCmdF, findBar_closesOnEsc, findBar_closesOnDoneButton
- findBar_matchCountForKnownDocument, findBar_wrapAroundForward, findBar_wrapAroundBackward
- findBar_caseSensitiveToggle, findBar_survivesJSContentUpdate, findBar_zeroResultsShowsRedBorder

Enable AX: `swift run MarkViewE2ETester` — will prompt for permission on first run.

---

### P2 — macOS: P1a Diagram Controls Visual QA (15 min)

Manual check only — no code changes needed. Open golden-corpus.md in MarkView and verify at 3 window sizes:
- 8 SVG icons: ↑↓←→ arrows, ↺ reset, ＋ zoom in, － zoom out, ⎘ copy + ✓ feedback
- clamp() scaling: 32px (normal) → 42px (full-screen)

---

### P2 — macOS: LOOP Template Sync

After P0 tags are pushed, extract these patterns to the LOOP template:
- Per-repo verify stamp paths (two-gate system)
- Auto-install after playwright passes
- Render-verify gate pre-commit hook

---

### P3 — iOS Screen Mirroring (research done, install pending)

`quicktime_video_hack` is the SOTA tool — native USB H.264 protocol, ~50ms latency, open source.

**No brew tap exists.** Compile from source:
```bash
brew install libusb pkg-config gstreamer gst-plugins-bad gst-plugins-good gst-plugins-base
git clone https://github.com/danielpaulus/quicktime_video_hack
cd quicktime_video_hack
go run main.go  # starts live mirror
```

For now: QuickTime Player → New Movie Recording → select iPad as source (already working).
`pymobiledevice3` for CLI screenshots: `pip3 install pymobiledevice3` → `pymobiledevice3 developer dvt screenshot /tmp/ipad.png`

---

## Session Commits (2026-04-04)

### markview (macOS)
| Hash | Description |
|------|-------------|
| `18ea9d2` | feat(ios): iOS platform support + mobile TOC responsive hide |
| `c9c01cb` | feat: v1.4.0 — find/search (P0a) + diff viewer + MCP tools (P0b) |

### markview-ios
| Hash | Description |
|------|-------------|
| `3c4b577` | chore: add development team for iPad device builds |
| `99e3476` | feat: migrate to MarkViewCore rendering — fixes Unicode, images, footnotes |

### markview-android
| Hash | Description |
|------|-------------|
| `53944b6` | fix: table horizontal scroll scoped to table, pinch-to-zoom enabled |
| `08c564c` | fix: status bar edge-to-edge + file:// URI handler + PHK logging |

---

## Key Infrastructure Notes

### Device UDIDs
- iPad (8), iOS 18.6.2: `00008103-000D306E140B001E`
- Galaxy S25U, Android 15: `R5CXC2YSECW` (adb)
- MarkView-iPhone17 simulator: `F1A7A709-35C0-4CCF-8E35-6E56CEDF21E8`

### Build Commands (cross-platform)
```bash
# macOS
cd ~/repos/markview && swift run MarkViewTestRunner   # 292 tests
make playwright                                        # 150 Playwright tests
bash verify.sh                                         # full gate

# iOS simulator build
xcodebuild -project markview-ios/MarkView.xcodeproj -scheme MarkView \
  -destination 'platform=iOS Simulator,id=F1A7A709-35C0-4CCF-8E35-6E56CEDF21E8' \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

# iOS device build (iPad)
xcodebuild -project markview-ios/MarkView.xcodeproj -scheme MarkView \
  -destination 'id=00008103-000D306E140B001E' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

# Android
cd ~/repos/markview-android && ./gradlew assembleDebug
adb -s R5CXC2YSECW install -r app/build/outputs/apk/debug/app-debug.apk
adb -s R5CXC2YSECW exec-out screencap -p > screenshot.png

# Android file push for testing (run-as for private dir)
cat file.md | adb shell "run-as dev.paulkang.markview sh -c 'cat > /data/data/dev.paulkang.markview/files/file.md'"
adb shell am start -a android.intent.action.VIEW \
  -d "file:///data/data/dev.paulkang.markview/files/file.md" \
  -n dev.paulkang.markview/.MainActivity
```

### TV Stamp Paths (two-gate system)
```bash
date +%s > ~/repos/claude-loop/.claude/memory/.last-verify-at      # commit-gate
date +%s > ~/repos/markview/.last-render-verify-at                  # render-verify
# Must be SEPARATE bash calls — hook reads before command executes
```

### Critical: diff2html Bundle
Use `diff2html.min.js` (core, 77KB) — NOT `diff2html-ui-base.min.js`.
Core bundle exports `Diff2Html.html()`. UI-base exports `Diff2HtmlUI` class only.
Verified: `node -e "const vm=require('vm'),fs=require('fs'),c={};vm.runInNewContext(fs.readFileSync('bundle.js','utf8'),c);console.log(Object.keys(c))"`

### iOS Simulator [?] Boxes
Not a code bug. iOS Simulator WKWebView lacks CJK/Arabic/emoji fonts.
All real devices (iPad, Galaxy S25U) render correctly.
Don't debug Unicode in simulator — connect a real device.

### SourceKit False Positives (iOS files)
All `~/repos/markview-ios/Sources/*.swift` are wrapped in `#if canImport(UIKit)`.
macOS SourceKit reports errors for UIKit types — expected, build is clean.
Test with: `xcodebuild ... build` not SourceKit diagnostics.

---

## Android Rendering Clarification

**Samsung Files + My Files apps ARE opening files via MarkView** — not native rendering.
Both apps fire `ACTION_VIEW` intent → MarkView registered for `text/markdown` → MarkView's MainActivity renders via marked.js → rendered HTML displayed.
The Files apps have no built-in markdown rendering. MarkView is the handler.
Confirmed: styling matches MarkView template.html exactly (GitHub dark theme, identical font sizes).
