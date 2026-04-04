# Diff Rendering Test

This fixture tests that `diff` fenced code blocks render as diff2html widgets.

## Basic Unified Diff

```diff
--- a/Sources/MarkViewCore/HTMLPipeline.swift
+++ b/Sources/MarkViewCore/HTMLPipeline.swift
@@ -1,8 +1,12 @@
 import Foundation
+import Combine
 
 /// HTML assembly pipeline for MarkView.
-/// Injects Prism, Mermaid, and KaTeX into the template.
+/// Injects Prism, diff2html, Mermaid, and KaTeX into the template.
 public struct HTMLPipeline {
-    let mermaidJS: String?
+    let diff2htmlJS: String?
+    let mermaidJS: String?
     let katexJS: String?
```

## Non-Diff Code Block (should NOT be affected by diff2html)

```swift
func hello() -> String {
    return "world"
}
```

## Multi-File Diff

```diff
--- a/Package.swift
+++ b/Package.swift
@@ -10,6 +10,7 @@
         .process("Resources/prism-bundle.min.js"),
         .process("Resources/mermaid.min.js"),
+        .process("Resources/diff2html-bundle.min.js"),
         .process("Resources/katex.min.js"),
```
