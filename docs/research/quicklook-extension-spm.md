# Quick Look Preview Extension with SPM (macOS 14+)

Research date: 2026-02-17

## Executive Summary

Building a `.appex` Quick Look preview extension with SPM requires manual bundle assembly since SPM has no native appex target type. The current MarkView approach (build executable, manually assemble `.appex` directory structure in `bundle.sh`) is the correct pattern. Key findings below address each open question.

---

## 1. Building `.appex` with SPM

**SPM cannot produce `.appex` bundles natively.** There is no `.appExtension` target type in `Package.swift`. The correct approach is:

1. Define the extension as an `.executableTarget` in `Package.swift` (as MarkView already does)
2. Build with `swift build -c release`
3. Manually assemble the `.appex` bundle structure in a build script

**Required bundle structure:**
```
MarkViewQuickLook.appex/
  Contents/
    MacOS/
      MarkViewQuickLook       # The compiled binary
    Info.plist                 # Extension metadata
    PkgInfo                   # Contains "XPC!????"
```

The `.appex` must be embedded inside the host app at:
```
MarkView.app/Contents/PlugIns/MarkViewQuickLook.appex/
```

**Current MarkView `bundle.sh` does this correctly.**

---

## 2. Required Info.plist Keys

### Minimum required keys for macOS to recognize the extension:

| Key | Value | Notes |
|-----|-------|-------|
| `CFBundleExecutable` | `MarkViewQuickLook` | Must match binary name |
| `CFBundleIdentifier` | `com.markview.app.quicklook` | Must be child of host app's bundle ID |
| `CFBundleInfoDictionaryVersion` | `6.0` | Standard |
| `CFBundleName` | `MarkViewQuickLook` | Display name |
| `CFBundlePackageType` | `XPC!` | **Critical** — must be `XPC!` for appex, not `APPL` or `BNDL` |
| `CFBundleShortVersionString` | `1.1.1` | Version string |
| `CFBundleVersion` | `1` | Build number |
| `NSExtension` (dict) | see below | Extension configuration |

### NSExtension dictionary (required children):

| Key | Value | Notes |
|-----|-------|-------|
| `NSExtensionPointIdentifier` | `com.apple.quicklook.preview` | Registers as Quick Look preview provider |
| `NSExtensionPrincipalClass` | `MarkViewQuickLook.PreviewProvider` | **Module-qualified** Swift class name |
| `NSExtensionAttributes` (dict) | see below | Extension capabilities |

### NSExtensionAttributes (required children):

| Key | Value | Notes |
|-----|-------|-------|
| `QLSupportedContentTypes` | Array of UTI strings | The UTIs this extension handles |
| `QLIsDataBasedPreview` | `true` | Required when using `QLPreviewProvider` (data-based). Omit for view-controller-based. |
| `QLSupportsSearchableItems` | `true`/`false` | Optional, enables Spotlight indexing |

---

## 3. NSExtensionPrincipalClass for Swift

**Must be module-qualified**: `ModuleName.ClassName`

For MarkView: `MarkViewQuickLook.PreviewProvider`

This is equivalent to Xcode's `$(PRODUCT_MODULE_NAME).PreviewProvider`. Since SPM module names default to the target name, the module is `MarkViewQuickLook`.

**Current MarkView plist is correct.**

---

## 4. `-application-extension` Swift Flag

**Yes, it is recommended.** The `-application-extension` flag restricts the code to APIs that are safe for use in app extensions. Without it, the compiler won't warn about using APIs unavailable in extension contexts (e.g., `UIApplication.shared`).

In SPM, apply it via `swiftSettings`:

```swift
.executableTarget(
    name: "MarkViewQuickLook",
    dependencies: ["MarkViewCore"],
    swiftSettings: [
        .unsafeFlags(["-application-extension"]),
    ]
)
```

**Current MarkView Package.swift already does this correctly.**

Note: There is an [open SPM issue](https://github.com/swiftlang/swift-package-manager/issues/4402) about SPM sometimes applying this flag globally to all targets. This was a known bug in Xcode 13 era. Using `.unsafeFlags` on just the extension target is the correct workaround.

---

## 5. Getting `pluginkit -m` to List the Extension

### Requirements for pluginkit discovery:

1. **Host app must be launched at least once** — macOS discovers extensions via LaunchServices database. The appex is registered when the host `.app` is first opened.
2. **lsregister the host app**: `lsregister -f /Applications/MarkView.app`
3. **pluginkit -a** to explicitly register: `pluginkit -a /path/to/MarkViewQuickLook.appex`
4. **Code signing matters** — unsigned or ad-hoc signed extensions may not register with pluginkit in all macOS versions. Developer ID signing is most reliable.

### Diagnostic commands:

```bash
# List all Quick Look preview extensions
pluginkit -mAvvv -p com.apple.quicklook.preview

# Check if your extension appears (+ = enabled, - = disabled)
pluginkit -m -p com.apple.quicklook.preview | grep MarkView

# Force re-register
pluginkit -a /Applications/MarkView.app/Contents/PlugIns/MarkViewQuickLook.appex

# Reset Quick Look daemon
killall QuickLookUIService 2>/dev/null; killall Finder

# Test preview directly (bypasses pluginkit)
qlmanage -p /path/to/file.md
```

### If pluginkit shows `-` (disabled):
Go to **System Settings > General > Login Items & Extensions > Quick Look** and enable the extension.

---

## 6. Handling UTI Conflicts (e.g., with Glance)

**macOS has no documented priority API for Quick Look extensions.** When multiple extensions claim the same UTI:

- The system picks one (often the most recently registered or the one from a more "trusted" app)
- Users can manage priority in **System Settings > General > Login Items & Extensions > Quick Look** — only one extension per UTI can be active
- There is **no programmatic way** to force your extension to take priority

### Practical strategies:

1. **Use specific UTIs, not broad ones.** `net.daringfireball.markdown` is better than `public.plain-text`. Claiming `public.plain-text` conflicts with many extensions (Glance, SourceCodeSyntaxHighlight, etc.).
2. **Check the file's actual UTI**: `mdls -name kMDItemContentType /path/to/file.md`
3. **Markdown UTIs to consider**: `net.daringfireball.markdown`, `com.unknown.md`, `dyn.ah62d4rv4ge8043a` (dynamic UTI for `.md`)
4. **Document for users**: Tell them to disable competing extensions in System Settings if they want MarkView's previewer.

### Recommendation for MarkView:
**Remove `public.plain-text`** from `QLSupportedContentTypes`. It will conflict with many other extensions and is not specific to Markdown. Use only markdown-specific UTIs:
```xml
<key>QLSupportedContentTypes</key>
<array>
    <string>net.daringfireball.markdown</string>
    <string>dyn.ah62d4rv4ge8043a</string>        <!-- .md dynamic UTI -->
    <string>dyn.ah62d4rv4ge8042pwrrwg875s</string> <!-- .markdown dynamic UTI -->
</array>
```

---

## 7. Xcode-Generated vs Hand-Crafted Plist Differences

Xcode-generated plists use build variables (`$(PRODUCT_MODULE_NAME)`, `$(EXECUTABLE_NAME)`, etc.) that get resolved at build time. Hand-crafted plists must use literal values.

### Keys Xcode adds that you may be missing:

| Key | Xcode default | Hand-crafted equivalent | Required? |
|-----|---------------|------------------------|-----------|
| `CFBundleDevelopmentRegion` | `$(DEVELOPMENT_LANGUAGE)` | `en` | Optional but recommended |
| `CFBundlePackageType` | `$(PRODUCT_BUNDLE_PACKAGE_TYPE)` | `XPC!` | **Required** |
| `NSHumanReadableCopyright` | varies | Your copyright string | Optional |

### Key that MarkView's plist is missing:

- **`QLIsDataBasedPreview`**: Should be `<true/>` since `PreviewProvider` extends `QLPreviewProvider` (data-based). This key is present in SourceCodeSyntaxHighlight's plist but missing from MarkView's. **This could be why the extension isn't loading.**

---

## 8. CFBundleSupportedPlatforms and LSMinimumSystemVersion

### CFBundleSupportedPlatforms
- **Recommended but not strictly required** for pluginkit registration
- SourceCodeSyntaxHighlight includes it: `<array><string>MacOSX</string></array>`
- MarkView already includes this correctly

### LSMinimumSystemVersion
- **Recommended** — tells macOS the minimum OS version for the extension
- If the running macOS version is below this value, the extension won't load
- MarkView correctly sets this to `14.0`

Neither key is likely the cause of registration failures, but including them is best practice and MarkView already does.

---

## 9. Setting Preview Window/Content Size

**You cannot directly control the Quick Look preview panel size from within an extension.** The panel size is determined by Finder/macOS.

What you CAN control:

1. **`contentSize` parameter in `QLPreviewReply`** — This specifies the **rendering canvas size**, not the preview window size. It determines the coordinate space for drawing-based replies and the aspect ratio hint for data-based replies. The preview panel scales the content to fit.

2. **For view-controller-based extensions** (using `QLPreviewingController`), you can set `preferredContentSize` on the view controller, which macOS *may* use as a sizing hint.

3. **For data-based extensions** (using `QLPreviewProvider`, which is MarkView's approach), the `contentSize` in `QLPreviewReply(dataOfContentType:contentSize:)` is a **content rendering hint**, not a window size control. macOS determines the actual panel dimensions.

### Recommendation for MarkView:
The current `preferredContentSize` computation (50% screen width) is reasonable as a content rendering size hint, but understand it will not force the preview panel to that size. The HTML content should be responsive/fluid so it renders well at any panel size the system chooses.

---

## 10. QLPreviewReply API Details

### `QLPreviewReply(dataOfContentType:contentSize:)` — Yes, this is the correct API for data-based previews.

**Init methods available (macOS 12+):**

| Method | Use case |
|--------|----------|
| `init(dataOfContentType:contentSize:createDataUsing:)` | Generate data (HTML, PDF, etc.) on demand |
| `init(fileURL:)` | Return a file URL for preview |
| `init(forPDFWithPageSize:documentCreationBlock:)` | Generate PDF pages |
| `init(contextSize:isBitmap:drawUsing:)` | Draw into a Core Graphics context |

### For MarkView (HTML-based preview):
`init(dataOfContentType:contentSize:createDataUsing:)` with `UTType.html` is correct. The closure receives a `QLPreviewReply` to update and returns `Data` (the HTML).

### `contentSize` behavior:
- For HTML content, this is the **initial viewport hint**. The actual rendering will adapt to the panel's actual size since HTML is inherently flexible.
- Setting `CGSize.zero` means "use system default" — this may actually be preferable for HTML content since the system will pick a reasonable size and the HTML will reflow.

---

## Action Items for MarkView

| Priority | Title | Scope | Complexity |
|----------|-------|-------|------------|
| P0 | Add `QLIsDataBasedPreview = true` to QuickLook Info.plist | Info.plist | Trivial |
| P1 | Remove `public.plain-text` from QLSupportedContentTypes, add markdown-specific dynamic UTIs | Info.plist | Low |
| P1 | Add `CFBundleDevelopmentRegion = en` to QuickLook Info.plist | Info.plist | Trivial |
| P2 | Consider using `CGSize.zero` for contentSize (let system decide) | PreviewProvider.swift | Trivial |
| P2 | Make HTML template responsive for variable preview panel sizes | MarkViewCore | Medium |
| P3 | Document Quick Look troubleshooting in README (pluginkit commands, System Settings toggle) | README.md | Low |

---

## Sources

- [Eclectic Light: QuickLook and its problems](https://eclecticlight.co/2024/04/05/a-quick-look-at-quicklook-and-its-problems/)
- [Eclectic Light: How QuickLook creates Thumbnails and Previews](https://eclecticlight.co/2024/11/04/how-does-quicklook-create-thumbnails-and-previews-with-an-update-to-mints/)
- [Eclectic Light: How PlugInKit enables app extensions](https://eclecticlight.co/2025/04/16/how-pluginkit-enables-app-extensions/)
- [Apple: QLPreviewProvider documentation](https://developer.apple.com/documentation/quicklookui/qlpreviewprovider)
- [Apple: QLPreviewReply documentation](https://developer.apple.com/documentation/quicklookui/qlpreviewreply)
- [Apple: App Extension Keys reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html)
- [Swift Forums: APPLICATION_EXTENSION_API_ONLY in SPM](https://forums.swift.org/t/set-application-extension-api-only-on-a-spm-package/39333)
- [SwiftPM issue #4402: App extension flag](https://github.com/swiftlang/swift-package-manager/issues/4402)
- [sbarex/SourceCodeSyntaxHighlight](https://github.com/sbarex/SourceCodeSyntaxHighlight) — reference appex Info.plist
- [samuelmeuli/glance](https://github.com/samuelmeuli/glance) — reference appex Info.plist
- [Michael Tsai: Sequoia drops qlgenerator support](https://mjtsai.com/blog/2024/11/05/sequoia-no-longer-supports-quicklook-generator-plug-ins/)
- [Apple Forums: Setting preferredContentSize of QL extensions](https://forums.developer.apple.com/forums/thread/673369)
- [Apple Forums: How to debug Quick Look Preview Extension](https://developer.apple.com/forums/thread/760892)
