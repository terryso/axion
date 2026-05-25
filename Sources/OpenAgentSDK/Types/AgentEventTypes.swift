import Foundation

// MARK: - AgentEvent

/// Protocol for all runtime events emitted by the agent system.
///
/// Every event carries a unique identifier and the moment it was created.
/// Concrete event types use struct composition with ``BaseAgentEvent`` rather
/// than class inheritance, preserving value semantics and `Sendable` safety.
public protocol AgentEvent: Sendable, Codable {
    /// Unique identifier for this event instance.
    var id: String { get }
    /// Wall-clock time when this event was created.
    var timestamp: Date { get }
}

// MARK: - BaseAgentEvent

/// Default implementation of ``AgentEvent`` providing auto-generated `id` and `timestamp`.
///
/// Concrete event types compose this as a stored property rather than subclassing:
/// ```swift
/// struct MyEvent: AgentEvent {
///     let base: BaseAgentEvent
///     var id: String { base.id }
///     var timestamp: Date { base.timestamp }
///     // ... domain-specific fields
/// }
/// ```
public struct BaseAgentEvent: AgentEvent, Codable, Equatable {
    public let id: String
    public let timestamp: Date

    public init(id: String = UUID().uuidString, timestamp: Date = Date()) {
        self.id = id
        self.timestamp = timestamp
    }
}

// MARK: - AgentEventCategory

/// High-level classification of runtime event types.
///
/// Used by the EventBus for type-filtered subscriptions and structured logging.
public enum AgentEventCategory: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case session
    case agent
    case tool
    case llm
    case memory
    case subAgent
}
