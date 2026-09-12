import Foundation

/// Owns completion identity across preparation and WebKit navigation.
@MainActor
public final class QuickLookPreviewRequest {
    private var generation = 0
    private var completion: ((Error?) -> Void)?

    public init() {}

    public func begin(completion handler: @escaping (Error?) -> Void) -> Int {
        generation += 1
        let request = generation
        let previous = completion
        completion = nil
        previous?(CancellationError())
        // The previous completion may start another request synchronously.
        if generation == request {
            completion = handler
        } else {
            handler(CancellationError())
        }
        return request
    }

    public func isCurrent(_ request: Int) -> Bool {
        generation == request && completion != nil
    }

    public func finish(_ request: Int, error: Error?) {
        guard isCurrent(request) else { return }
        let handler = completion
        completion = nil
        handler?(error)
    }
}
