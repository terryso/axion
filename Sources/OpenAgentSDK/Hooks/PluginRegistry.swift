import Foundation

// MARK: - PluginRegistry Actor

/// Thread-safe registry for managing self-evolution plugins across Agent lifecycle events.
///
/// `PluginRegistry` is an `actor` that maintains an ordered list of registered
/// ``SelfEvolutionPlugin`` instances and dispatches lifecycle events to them.
/// Individual plugin failures are caught and logged — they do not propagate to callers.
public actor PluginRegistry {

    // MARK: - Properties

    /// Ordered list of registered plugins.
    private var plugins: [any SelfEvolutionPlugin] = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Registration

    /// Register a plugin.
    ///
    /// - Parameter plugin: The plugin to register.
    /// - Throws: ``SDKError/invalidConfiguration`` if a plugin with the same `name` is already registered.
    public func register(_ plugin: any SelfEvolutionPlugin) throws {
        if plugins.contains(where: { $0.name == plugin.name }) {
            throw SDKError.invalidConfiguration("Plugin '\(plugin.name)' is already registered")
        }
        plugins.append(plugin)
    }

    /// Remove a plugin by name.
    ///
    /// - Parameter name: The name of the plugin to remove.
    public func unregister(name: String) {
        plugins.removeAll { $0.name == name }
    }

    // MARK: - Lookup

    /// Look up a plugin by name.
    ///
    /// - Parameter name: The plugin name.
    /// - Returns: The plugin, or `nil` if not found.
    public func getPlugin(name: String) -> (any SelfEvolutionPlugin)? {
        plugins.first { $0.name == name }
    }

    /// Returns all registered plugins in registration order.
    public func allPlugins() -> [any SelfEvolutionPlugin] {
        plugins
    }

    /// Names of all registered plugins in registration order.
    public var pluginNames: [String] {
        plugins.map { $0.name }
    }

    // MARK: - Dispatch

    /// Dispatch a lifecycle phase to all plugins that support it.
    ///
    /// Each plugin's ``SelfEvolutionPlugin/onPhase(_:context:)`` is called sequentially.
    /// If a plugin throws, the error is logged and ``PluginResult/none`` is substituted
    /// for that plugin. Other plugins continue executing unaffected.
    ///
    /// - Parameters:
    ///   - phase: The lifecycle phase to dispatch.
    ///   - context: The runtime context snapshot.
    /// - Returns: An array of results from all participating plugins.
    public func dispatch(
        _ phase: PluginLifecyclePhase,
        context: PluginContext
    ) async -> [PluginResult] {
        var results: [PluginResult] = []
        for plugin in plugins {
            guard plugin.supportedPhases.contains(phase) else { continue }
            do {
                let result = try await plugin.onPhase(phase, context: context)
                results.append(result)
            } catch {
                Logger.shared.error("PluginRegistry", "plugin_phase_failed", data: [
                    "plugin": plugin.name,
                    "phase": phase.rawValue,
                    "error": error.localizedDescription,
                ])
                results.append(.none)
            }
        }
        return results
    }

    /// Initialize all registered plugins in registration order.
    ///
    /// Errors are collected but do not stop initialization of subsequent plugins.
    ///
    /// - Parameter sessionId: The session identifier passed to each plugin.
    /// - Throws: ``SDKError/invalidConfiguration`` if any plugin fails to initialize,
    ///   with the combined error messages.
    public func initializeAll(sessionId: String) async throws {
        var errors: [String] = []
        for plugin in plugins {
            do {
                try await plugin.initialize(sessionId: sessionId)
            } catch {
                errors.append("\(plugin.name): \(error.localizedDescription)")
                Logger.shared.error("PluginRegistry", "plugin_init_failed", data: [
                    "plugin": plugin.name,
                    "error": error.localizedDescription,
                ])
            }
        }
        if !errors.isEmpty {
            throw SDKError.invalidConfiguration(
                "Plugin initialization failures: " + errors.joined(separator: "; ")
            )
        }
    }

    /// Shut down all plugins in reverse registration order.
    ///
    /// Each plugin's ``SelfEvolutionPlugin/shutdown()`` is called.
    public func shutdownAll() async {
        for plugin in plugins.reversed() {
            await plugin.shutdown()
        }
    }
}
