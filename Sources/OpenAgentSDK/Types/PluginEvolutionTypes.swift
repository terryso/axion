import Foundation

// MARK: - EvolutionPluginConfig

/// Configuration for a self-evolution plugin.
///
/// Each entry in ``AgentOptions/evolutionPlugins`` describes a plugin to load
/// at agent creation time, along with its enabled state and optional key-value config.
public struct EvolutionPluginConfig: Sendable, Codable, Equatable {

    /// Unique plugin identifier. Must be non-empty after trimming.
    public let name: String

    /// Whether the plugin is enabled. Defaults to `true`.
    public let enabled: Bool

    /// Plugin-specific key-value configuration. `nil` means no extra config.
    public let config: [String: String]?

    public init(
        name: String,
        enabled: Bool = true,
        config: [String: String]? = nil
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmed.isEmpty, "EvolutionPluginConfig.name must be non-empty after trimming")
        self.name = trimmed
        self.enabled = enabled
        self.config = config
    }
}

// MARK: - PluginLifecyclePhase

/// Lifecycle phases that a self-evolution plugin can participate in.
///
/// Maps to the Hermes `MemoryProvider` lifecycle phases. Plugins declare
/// which phases they support via ``SelfEvolutionPlugin/supportedPhases``.
public enum PluginLifecyclePhase: String, Codable, Sendable, Equatable, CaseIterable {
    /// Called once at session start via ``SelfEvolutionPlugin/initialize(sessionId:)``.
    case initialize
    /// Pre-fetch context before the main query.
    case prefetch
    /// Synchronize a single turn (user message + assistant response).
    case syncTurn
    /// Session is ending — flush persisted data.
    case sessionEnd
    /// Before conversation compaction — extract key data.
    case preCompress
}

// MARK: - PluginContext

/// An immutable snapshot of runtime context provided to plugins at each lifecycle hook.
///
/// Contains the data a plugin needs without exposing mutable agent state.
/// The `messages` array is a copy of the current conversation history.
public struct PluginContext: Sendable, Equatable {

    /// The current session identifier.
    public let sessionId: String

    /// Conversation messages up to this point.
    public let messages: [SDKMessage]

    /// The current user query, if available.
    public let currentQuery: String?

    /// Snapshot of agent model configuration.
    public let model: String

    /// Snapshot of agent LLM provider.
    public let provider: LLMProvider

    public init(
        sessionId: String,
        messages: [SDKMessage],
        currentQuery: String? = nil,
        model: String,
        provider: LLMProvider
    ) {
        self.sessionId = sessionId
        self.messages = messages
        self.currentQuery = currentQuery
        self.model = model
        self.provider = provider
    }
}

// MARK: - SendableToolSchemaList

/// A type-erased Sendable wrapper for a list of tool schema dictionaries.
///
/// Uses the same pattern as ``SendableJSONSchema`` for Equatable comparison
/// via NSDictionary.
public struct SendableToolSchemaList: @unchecked Sendable, Equatable {
    /// The underlying list of JSON Schema dictionaries.
    public let schemas: [[String: Any]]

    /// Creates a wrapper around a list of tool schema dictionaries.
    public init(schemas: [[String: Any]]) {
        self.schemas = schemas
    }

    public static func == (lhs: SendableToolSchemaList, rhs: SendableToolSchemaList) -> Bool {
        guard lhs.schemas.count == rhs.schemas.count else { return false }
        for (ls, rs) in zip(lhs.schemas, rhs.schemas) {
            guard NSDictionary(dictionary: ls).isEqual(to: rs) else { return false }
        }
        return true
    }
}

// MARK: - PluginResult

/// Result returned by a plugin's lifecycle hook.
///
/// Each case describes a different action the plugin wants the SDK to take.
/// The registry collects all results from a dispatch and returns them to the caller.
public enum PluginResult: Sendable, Equatable {

    /// No action taken by the plugin.
    case none

    /// Text to inject into the system prompt.
    case systemPromptBlock(String)

    /// JSON Schema dicts for tools to expose to the LLM.
    ///
    /// Wrapped in ``SendableToolSchemaList`` for Sendable conformance.
    case toolSchemas(SendableToolSchemaList)

    /// Experience signals to persist.
    case facts([ExperienceSignal])
}

// MARK: - SelfEvolutionPlugin

/// Protocol for self-evolution plugins that participate in the agent lifecycle.
///
/// Plugins are registered with ``PluginRegistry`` and called at specific lifecycle
/// phases. Each plugin declares which phases it supports via ``supportedPhases``.
public protocol SelfEvolutionPlugin: Sendable {

    /// Unique identifier for this plugin.
    var name: String { get }

    /// Which lifecycle phases this plugin participates in.
    var supportedPhases: Set<PluginLifecyclePhase> { get }

    /// Called once at session start.
    ///
    /// - Parameter sessionId: The session identifier.
    func initialize(sessionId: String) async throws

    /// Main lifecycle hook called at each supported phase.
    ///
    /// - Parameters:
    ///   - phase: The current lifecycle phase.
    ///   - context: An immutable snapshot of runtime context.
    /// - Returns: A ``PluginResult`` describing the plugin's action.
    func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult

    /// Cleanup called when the session ends or the registry is shutting down.
    ///
    /// Default implementation is a no-op.
    func shutdown() async
}

extension SelfEvolutionPlugin {
    /// Default no-op shutdown.
    public func shutdown() async {}
}
