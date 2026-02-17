@preconcurrency import ApplicationServices
import Foundation

/// Manages the MarkView.app lifecycle: finding the bundle, launching, terminating.
/// Uses Process and POSIX APIs only — no @MainActor-isolated AppKit APIs.
final class AppController: @unchecked Sendable {
    let bundlePath: String
    /// Mutable PID — only accessed from the main thread in practice.
    private var _storedPid: pid_t = 0

    var pid: pid_t? {
        _storedPid == 0 ? nil : _storedPid
    }

    var axApp: AXUIElement? {
        pid.map { AXUIElementCreateApplication($0) }
    }

    /// Finds the .app bundle in common locations.
    init() throws {
        // pid already initialized to 0

        let candidates = [
            FileManager.default.currentDirectoryPath + "/MarkView.app",
            ProcessInfo.processInfo.environment["PROJECT_DIR"].map { $0 + "/MarkView.app" },
            "/Applications/MarkView.app",
        ].compactMap { $0 }

        guard let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw AppControllerError.bundleNotFound(candidates)
        }
        self.bundlePath = found
    }

    /// Launch the app with optional arguments.
    func launch(args: [String] = []) throws {
        terminate() // Kill any previous instance

        let executablePath = bundlePath + "/Contents/MacOS/MarkView"
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw AppControllerError.executableNotFound(executablePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        _storedPid = process.processIdentifier

        // Wait for the app to register with the window server
        Thread.sleep(forTimeInterval: 1.0)

        // Bring to front using `open` — no @MainActor dependency
        let activate = Process()
        activate.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        activate.arguments = ["-a", bundlePath]
        activate.standardOutput = FileHandle.nullDevice
        activate.standardError = FileHandle.nullDevice
        try? activate.run()
        activate.waitUntilExit()
    }

    /// Launch app with a file path argument.
    func launchWithFile(_ path: String) throws {
        try launch(args: [path])
    }

    /// Terminate the running app instance.
    func terminate() {
        let currentPid = _storedPid
        if currentPid != 0 {
            kill(currentPid, SIGTERM)
            Thread.sleep(forTimeInterval: 0.3)
            if kill(currentPid, 0) == 0 {
                kill(currentPid, SIGKILL)
                Thread.sleep(forTimeInterval: 0.2)
            }
        }

        // Also kill any stray MarkView processes
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", "MarkView.app/Contents/MacOS/MarkView"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        _storedPid = 0
        Thread.sleep(forTimeInterval: 0.3)
    }

    func isRunning() -> Bool {
        let currentPid = _storedPid
        guard currentPid != 0 else { return false }
        return kill(currentPid, 0) == 0
    }

    /// Wait for the main window to appear after launch.
    func waitForWindow(timeout: TimeInterval = 3.0) throws -> AXUIElement {
        var window: AXUIElement?
        try AXHelper.waitFor(timeout: timeout, description: "main window") {
            guard let app = axApp else { return false }
            let wins = AXHelper.windows(of: app)
            if let first = wins.first {
                window = first
                return true
            }
            return false
        }
        guard let w = window else {
            throw AppControllerError.windowNotFound
        }
        return w
    }

    /// Get the current main window.
    func mainWindow() throws -> AXUIElement {
        guard let app = axApp else {
            throw AppControllerError.appNotRunning
        }
        let wins = AXHelper.windows(of: app)
        guard let first = wins.first else {
            throw AppControllerError.windowNotFound
        }
        return first
    }
}

enum AppControllerError: Error, CustomStringConvertible {
    case bundleNotFound([String])
    case executableNotFound(String)
    case windowNotFound
    case appNotRunning

    var description: String {
        switch self {
        case .bundleNotFound(let paths):
            return "MarkView.app not found. Searched: \(paths.joined(separator: ", "))"
        case .executableNotFound(let path):
            return "Executable not found at: \(path)"
        case .windowNotFound:
            return "No window appeared"
        case .appNotRunning:
            return "App is not running"
        }
    }
}
