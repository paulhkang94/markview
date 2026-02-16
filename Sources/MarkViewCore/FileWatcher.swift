import Foundation

/// Watches a file for changes using DispatchSource.
/// Handles atomic saves (write-to-temp + rename) used by VS Code, Vim, etc.
public final class FileWatcher: @unchecked Sendable {
    private let path: String
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.markview.filewatcher", qos: .userInteractive)

    /// Debounce interval to coalesce rapid events
    private let debounceInterval: TimeInterval = 0.1
    private var debounceWorkItem: DispatchWorkItem?

    public init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    public func start() {
        startWatching()
    }

    public func stop() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func startWatching() {
        stop()

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = source.data
            if flags.contains(.rename) || flags.contains(.delete) {
                // File was renamed/deleted — likely an atomic save.
                // Re-establish the watch on the new file at the same path.
                self.queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.startWatching()
                    self?.notifyDebounced()
                }
            } else {
                self.notifyDebounced()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        self.source = source
        source.resume()
    }

    private func notifyDebounced() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    deinit {
        stop()
    }
}
