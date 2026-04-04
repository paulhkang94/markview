import Foundation
import Combine

/// Find bar state machine. Owned by ContentView (@StateObject).
/// WebPreviewView.Coordinator holds a reference and executes WKWebView.find(),
/// writing results back via matchCount/matchIndex/noResults.
public final class FindBarController: ObservableObject {
    @Published public var isVisible: Bool = false
    @Published public var query: String = ""
    @Published public var matchCount: Int = 0
    @Published public var caseSensitive: Bool = false
    @Published public var noResults: Bool = false  // triggers red-border flash

    // Callbacks set by Coordinator (avoids WKWebView import here)
    public var onFindNext: ((String, Bool) -> Void)?    // (query, caseSensitive)
    public var onFindPrev: ((String, Bool) -> Void)?
    public var onClear: (() -> Void)?
    public var onQueryChanged: ((String, Bool) -> Void)?  // for live search

    private let phkDebug = ProcessInfo.processInfo.environment["PHK_DEBUG"] == "1"

    public init() {}

    public func show() {
        isVisible = true
        phkLog("show=true (source: show())")
    }

    public func hide() {
        isVisible = false
        query = ""
        matchCount = 0
        noResults = false
        onClear?()
        phkLog("hide — cleared state")
    }

    public func findNext() {
        guard !query.isEmpty else { return }
        phkLog("findNext() query=\"\(query)\" caseSensitive=\(caseSensitive)")
        onFindNext?(query, caseSensitive)
    }

    public func findPrev() {
        guard !query.isEmpty else { return }
        phkLog("findPrev() query=\"\(query)\" caseSensitive=\(caseSensitive)")
        onFindPrev?(query, caseSensitive)
    }

    public func clear() {
        matchCount = 0
        noResults = false
        onClear?()
        phkLog("clear() — highlights removed")
    }

    /// Called by Coordinator after WKWebView.find() completes
    public func updateResult(matchCount: Int, found: Bool) {
        self.matchCount = matchCount
        noResults = !found && !query.isEmpty
        phkLog("updateResult(matchCount=\(matchCount) found=\(found))")
    }

    private func phkLog(_ msg: String) {
        guard phkDebug else { return }
        print("[PHK] findBar: \(msg)")
    }
}
