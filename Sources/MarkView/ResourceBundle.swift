import Foundation

/// Safe resource bundle accessor that avoids the fatalError in SPM's generated Bundle.module.
///
/// SPM's auto-generated `Bundle.module` places the resource bundle at the `.app` root
/// (e.g., `MarkView.app/MarkView_MarkView.bundle`), which is outside `Contents/`.
/// This fails under macOS app translocation (Gatekeeper security feature) because
/// translocation only copies the `Contents/` subtree, leaving the root-level bundle behind.
///
/// This accessor checks multiple locations in priority order:
/// 1. `Contents/Resources/` — standard macOS .app location, survives translocation
/// 2. `.app` root — where SPM's Bundle.module expects it (backward compat)
/// 3. SPM build directory — for `swift run` during development
enum ResourceBundle {
    static let bundle: Bundle? = {
        let bundleName = "MarkView_MarkView.bundle"

        // 1. Standard macOS location: Contents/Resources/ (survives translocation + code signing)
        let resourcesPath = Bundle.main.bundlePath + "/Contents/Resources/" + bundleName
        if let bundle = Bundle(path: resourcesPath) {
            return bundle
        }

        // 2. App root (SPM's default expectation for Bundle.module)
        let rootPath = Bundle.main.bundleURL.appendingPathComponent(bundleName).path
        if let bundle = Bundle(path: rootPath) {
            return bundle
        }

        // 3. Adjacent to executable (for swift run / SPM development)
        let executableDir = Bundle.main.bundleURL
        let adjacentPath = executableDir.appendingPathComponent(bundleName).path
        if let bundle = Bundle(path: adjacentPath) {
            return bundle
        }

        // 4. Fall back to Bundle.main — Xcode/XcodeGen builds copy resources directly
        // into Contents/Resources/ (no SPM .bundle wrapper). This is the standard
        // macOS app bundle layout.
        return Bundle.main
    }()

    /// Load a resource URL, returning nil instead of crashing if the bundle is missing.
    /// Tries with the given subdirectory first, then without it (Xcode builds place
    /// resources directly in Contents/Resources/, not in a Resources/ subfolder).
    static func url(forResource name: String, withExtension ext: String, subdirectory: String? = nil) -> URL? {
        if let url = bundle?.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        if subdirectory != nil, let url = bundle?.url(forResource: name, withExtension: ext) {
            return url
        }
        return nil
    }
}
