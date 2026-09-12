/// State for full-page preview publication and its once-per-page completion.
/// Owned by the preview coordinator on its UI execution path.
public struct PreviewLoadLifecycle {
    public private(set) var generation = 0
    private var loadedGeneration: Int?
    private var completed = false

    public init() {}

    public mutating func begin() -> Int {
        generation += 1
        return generation
    }

    @discardableResult
    public mutating func markLoaded(_ candidate: Int) -> Bool {
        guard candidate == generation, loadedGeneration != candidate else { return false }
        loadedGeneration = candidate
        completed = false
        return true
    }

    public mutating func claimCompletion(_ candidate: Int) -> Bool {
        guard candidate == generation, loadedGeneration == candidate, !completed else { return false }
        completed = true
        return true
    }
}
