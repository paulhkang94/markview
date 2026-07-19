import Foundation

/// Process-wide, load-once cache for the bundled JS libraries injected into the
/// preview page (Prism, Mermaid, KaTeX, KaTeX auto-render).
///
/// Extracted from `WebPreviewView.Coordinator` (item-713 hang triage, #55 /
/// mar-033). Previously every Coordinator.init — one per tab, plus one per
/// pane-toggle view recreation — synchronously re-read ~3.2 MB from disk on the
/// main thread; mermaid.min.js alone is 2.9 MB, and Sentry hang report #48
/// sampled the main thread inside exactly that read. v1.7.0's restore-all-tabs
/// (MV-001) multiplied the cost by the number of tabs opened during launch.
///
/// `shared` is a `static let`, so the four disk reads happen exactly once per
/// process (language-guaranteed, thread-safe lazy initialization). The loader
/// is injectable so MarkViewTestRunner can assert the load-once contract
/// behaviorally instead of via source inspection.
public struct JSBundleCache: Sendable {

    public let prism: String?
    public let mermaid: String?
    public let katex: String?
    public let katexAutoRender: String?

    /// Bundles that failed to load, in load order. The app target maps these to
    /// AppLogger warnings + Sentry breadcrumbs (logging stays out of this
    /// library so it never links Sentry).
    public let failures: [LoadFailure]

    public enum LoadFailure: Equatable, Sendable {
        case resourceNotFound(label: String)
        case readFailed(label: String, message: String)
    }

    public enum LoadError: Error, Sendable {
        case resourceNotFound
        case readFailed(message: String)
    }

    /// Resolves one JS resource by SPM resource name (e.g. "mermaid.min").
    public typealias Loader = @Sendable (_ resourceName: String) -> Result<String, LoadError>

    /// The single per-process instance. First access performs the four bundle
    /// reads; every later access (every additional tab/Coordinator) is free.
    public static let shared = JSBundleCache(loader: JSBundleCache.resourceBundleLoader)

    public init(loader: Loader) {
        var failures: [LoadFailure] = []
        func load(_ name: String, label: String) -> String? {
            switch loader(name) {
            case .success(let js):
                return js
            case .failure(.resourceNotFound):
                failures.append(.resourceNotFound(label: label))
                return nil
            case .failure(.readFailed(let message)):
                failures.append(.readFailed(label: label, message: message))
                return nil
            }
        }
        self.prism = load("prism-bundle.min", label: "Prism.js")
        self.mermaid = load("mermaid.min", label: "Mermaid.js")
        self.katex = load("katex.min", label: "KaTeX")
        self.katexAutoRender = load("auto-render.min", label: "KaTeX auto-render")
        self.failures = failures
    }

    /// Production loader: reads from MarkViewCore's resource bundle via the
    /// translocation-safe ResourceBundle accessor (identical to the reads the
    /// Coordinator's static loadJSBundle helper performed before extraction).
    public static let resourceBundleLoader: Loader = { name in
        guard let url = ResourceBundle.url(forResource: name, withExtension: "js", subdirectory: "Resources") else {
            return .failure(.resourceNotFound)
        }
        do {
            return .success(try String(contentsOf: url, encoding: .utf8))
        } catch {
            return .failure(.readFailed(message: error.localizedDescription))
        }
    }
}
