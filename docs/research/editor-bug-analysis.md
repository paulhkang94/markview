# Editor Bug Analysis: Text Corruption, Contrast, and SOTA Patterns

**Date**: 2026-02-19
**Status**: Fixed and shipped

## Root Cause: Text Corruption

The text editor had a classic NSViewRepresentable race condition that caused characters to get corrupted or deleted during typing.

### The Bug Mechanism

Three interacting problems:

**1. updateNSView overwrites NSTextView during active typing**

When the user types in the NSTextView:
1. `textDidChange` fires in the Coordinator
2. Coordinator sets `text.wrappedValue = newText` (the @Binding to `viewModel.editorContent`)
3. SwiftUI processes the @Published change and calls `updateNSView`
4. `updateNSView` compares `textView.string != text` -- but by now the user may have typed MORE characters
5. `textView.string = text` replaces NSTextView content with the stale binding value
6. The characters typed between step 2 and step 5 are lost

This is the primary corruption vector. The SwiftUI update cycle has non-zero latency, and during that window the user can type additional characters that get destroyed.

**2. Double @Published write per keystroke**

`textDidChange` sets `text.wrappedValue = newText`, which updates `viewModel.editorContent` via the binding. Then `onChange(newText)` calls `viewModel.contentDidChange(newText)`, which sets `editorContent = newText` AGAIN. Two @Published mutations = two SwiftUI update cycles per keystroke, doubling the chance of the race in problem 1.

**3. File watcher reloads content after save**

When auto-save (or manual save) writes the file:
1. `save()` writes to disk, sets `isDirty = false`
2. FileWatcher detects the write event
3. Watcher callback checks `isDirty` -- it's false (we just saved)
4. Watcher calls `loadContent(from:)` which sets `editorContent = diskContent`
5. This triggers another updateNSView that replaces NSTextView content

If the user started typing between the save and the watcher callback (100ms debounce + 50ms re-watch delay), their new keystrokes are lost.

### Fix (Applied)

**File: `Sources/MarkView/EditorView.swift`**

- Added `isUserEditing` flag to the Coordinator. Set to `true` in `textDidChange` BEFORE updating the binding. Checked in `updateNSView` -- when true, skip the `textView.string = text` replacement entirely. Reset to false after skipping.
- Added selection range clamping: when external content does need to be pushed to NSTextView, saved selection ranges are clamped to the new text length to prevent out-of-bounds crashes.

**File: `Sources/MarkView/PreviewViewModel.swift`**

- Removed redundant `editorContent = newText` in `contentDidChange`. The binding already set it.
- Added `suppressFileWatcher` flag. Set to true before `write(toFile:)`, reset to false after 250ms (exceeding the FileWatcher debounce window). Watcher callback checks this flag and ignores events during suppression.

## Contrast Fix

### The Problem

The editor had `drawsBackground = false` and no explicit text color, relying on whatever defaults NSTextView picks. In dark mode, this produces low-contrast text. Worse, `typingAttributes` only included `.font`, so newly typed text could inherit transparent or wrong-color attributes from adjacent content.

### Fix (Applied)

**File: `Sources/MarkView/EditorView.swift`**

- Set `drawsBackground = true` with `backgroundColor = .textBackgroundColor` (system-aware white/dark)
- Set `textColor = .labelColor` (system-aware black/white)
- Set `insertionPointColor = .labelColor` so the cursor is always visible
- Added `.foregroundColor: NSColor.labelColor` to `typingAttributes` so all newly typed text has proper contrast regardless of what it's adjacent to

These use system semantic colors, so they automatically adapt to light mode, dark mode, and high contrast accessibility settings.

## SOTA Editor Patterns

Research into CodeMirror 6, VS Code, and Nova editors reveals patterns worth adopting:

### CodeMirror 6's Transaction Model

CodeMirror 6 treats the editor state as immutable. Changes are applied via transactions that produce a new state. The key insight: **the view never directly mutates state**. All changes flow through a single dispatch function, making it impossible for the view to be out of sync with the state.

Our fix approximates this: the `isUserEditing` flag is a simple "who owns the truth right now?" discriminator. A more complete solution would route all changes through a single mutation point.

### Cursor Preservation via Change Mapping

CodeMirror maps cursor positions through document changes. When text is inserted/deleted, all existing selections are adjusted by the change's offset. Our current approach (save/restore NSRange) is fragile -- it works for same-content replacement but breaks for content-length changes. The clamping fix handles the crash case but doesn't preserve cursor position intelligently.

### File Watcher Best Practice (VS Code)

VS Code uses a "dirty tracking" approach: the editor maintains a version counter that increments on every edit. When the file watcher fires, it compares the disk content hash against the last-saved hash (not the current editor content). This avoids the `isDirty` boolean race entirely. Our `suppressFileWatcher` flag is a simpler version of the same idea.

### Debounce Architecture

Our current debounce (150ms render, 300ms lint) is reasonable. CodeMirror uses a different approach: changes are batched within a single animation frame using requestAnimationFrame, and the view updates synchronously within that frame. For a native app, the equivalent would be coalescing changes within a single CADisplayLink frame.

## Action Items

| Priority | Title | Scope | Complexity |
|----------|-------|-------|------------|
| P0 | Text corruption fix (isUserEditing flag) | EditorView.swift | Done |
| P0 | Remove double @Published write | PreviewViewModel.swift | Done |
| P0 | Suppress file watcher during save | PreviewViewModel.swift | Done |
| P0 | Editor contrast fix (semantic colors) | EditorView.swift | Done |
| P1 | Intelligent cursor mapping through external changes | EditorView.swift | Medium |
| P1 | Version-counter dirty tracking (replace boolean) | PreviewViewModel.swift | Medium |
| P2 | Single mutation point for all editor state changes | Architecture | Large |
| P2 | CADisplayLink-based change coalescing for render | PreviewViewModel.swift | Medium |
| P3 | Syntax highlighting in editor pane (not just preview) | EditorView.swift | Large |
