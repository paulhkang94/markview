import Foundation

// MARK: - Plugin Protocol

public protocol LanguagePlugin {
    /// File extensions this plugin handles (without dots).
    var supportedExtensions: Set<String> { get }

    /// Display name for the language.
    var displayName: String { get }

    /// Whether this language needs JS execution in preview.
    var requiresJSExecution: Bool { get }

    /// Transform source code into previewable HTML body.
    func render(source: String) -> String
}

// MARK: - Plugin Registry

public final class PluginRegistry {
    public static let shared = PluginRegistry()

    private var plugins: [String: LanguagePlugin] = [:]

    public init() {}

    /// Register a plugin for its supported extensions.
    public func register(_ plugin: LanguagePlugin) {
        for ext in plugin.supportedExtensions {
            plugins[ext.lowercased()] = plugin
        }
    }

    /// Look up a plugin by file extension.
    public func plugin(forExtension ext: String) -> LanguagePlugin? {
        plugins[ext.lowercased()]
    }

    /// All registered extensions.
    public var registeredExtensions: Set<String> {
        Set(plugins.keys)
    }

    /// Clear all registered plugins.
    public func clear() {
        plugins.removeAll()
    }
}
