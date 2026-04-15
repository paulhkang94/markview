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
        // Do NOT close fileDescriptor here — the cancel handler (set up in startWatching)
        // captures the fd by value and is responsible for closing it. Closing here AND in
        // the cancel handler races: if startWatching() is called between stop() and the
        // cancel handler firing, self.fileDescriptor already refers to the NEW fd, and the
        // old handler would close the wrong one — leaving the new DispatchSource on an
        // invalid fd and silently disabling all future file-change events.
        source = nil
        fileDescriptor = -1
    }

    private func startWatching() {
        stop()

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
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

        // Capture fd by value — never read self.fileDescriptor here.
        // By the time this handler fires, self.fileDescriptor may already point to a
        // newer fd (opened by the next startWatching() call). We must close the specific
        // fd this source was created for, not whatever self.fileDescriptor happens to be.
        source.setCancelHandler {
            close(fd)
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
