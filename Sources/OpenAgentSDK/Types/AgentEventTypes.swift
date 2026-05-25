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

// MARK: - Session Events

/// Status of a session at the time of closure.
public enum SessionFinalStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case completed
    case failed
    case interrupted
}

/// Emitted when a new session is created.
public struct SessionCreatedEvent: AgentEvent, Equatable {
    public let base: BaseAgentEvent
    public let sessionId: String?
    public let task: String
    public let model: String

    public var id: String { base.id }
    public var timestamp: Date { base.timestamp }

    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case sessionId = "session_id"
        case task, model
    }

    public init(base: BaseAgentEvent = BaseAgentEvent(), sessionId: String?, task: String, model: String) {
        self.base = base
        self.sessionId = sessionId
        self.task = task
        self.model = model
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = BaseAgentEvent(
            id: try c.decode(String.self, forKey: .id),
            timestamp: try c.decode(Date.self, forKey: .timestamp)
        )
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        task = try c.decode(String.self, forKey: .task)
        model = try c.decode(String.self, forKey: .model)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base.id, forKey: .id)
        try c.encode(base.timestamp, forKey: .timestamp)
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encode(task, forKey: .task)
        try c.encode(model, forKey: .model)
    }
}

/// Emitted when a session is restored from a SessionStore.
public struct SessionRestoredEvent: AgentEvent, Equatable {
    public let base: BaseAgentEvent
    public let sessionId: String?
    public let messageCount: Int
    public let originalCreatedAt: Date

    public var id: String { base.id }
    public var timestamp: Date { base.timestamp }

    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case sessionId = "session_id"
        case messageCount = "message_count"
        case originalCreatedAt = "original_created_at"
    }

    public init(base: BaseAgentEvent = BaseAgentEvent(), sessionId: String?, messageCount: Int, originalCreatedAt: Date) {
        self.base = base
        self.sessionId = sessionId
        self.messageCount = messageCount
        self.originalCreatedAt = originalCreatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = BaseAgentEvent(
            id: try c.decode(String.self, forKey: .id),
            timestamp: try c.decode(Date.self, forKey: .timestamp)
        )
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        messageCount = try c.decode(Int.self, forKey: .messageCount)
        originalCreatedAt = try c.decode(Date.self, forKey: .originalCreatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base.id, forKey: .id)
        try c.encode(base.timestamp, forKey: .timestamp)
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encode(messageCount, forKey: .messageCount)
        try c.encode(originalCreatedAt, forKey: .originalCreatedAt)
    }
}

/// Emitted when a session is closed (agent execution ends).
public struct SessionClosedEvent: AgentEvent, Equatable {
    public let base: BaseAgentEvent
    public let sessionId: String?
    public let finalStatus: SessionFinalStatus

    public var id: String { base.id }
    public var timestamp: Date { base.timestamp }

    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case sessionId = "session_id"
        case finalStatus = "final_status"
    }

    public init(base: BaseAgentEvent = BaseAgentEvent(), sessionId: String?, finalStatus: SessionFinalStatus) {
        self.base = base
        self.sessionId = sessionId
        self.finalStatus = finalStatus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = BaseAgentEvent(
            id: try c.decode(String.self, forKey: .id),
            timestamp: try c.decode(Date.self, forKey: .timestamp)
        )
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        finalStatus = try c.decode(SessionFinalStatus.self, forKey: .finalStatus)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base.id, forKey: .id)
        try c.encode(base.timestamp, forKey: .timestamp)
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encode(finalStatus, forKey: .finalStatus)
    }
}

/// Emitted when a session is auto-saved during the agent loop.
public struct SessionAutoSavedEvent: AgentEvent, Equatable {
    public let base: BaseAgentEvent
    public let sessionId: String?
    public let messageCount: Int

    public var id: String { base.id }
    public var timestamp: Date { base.timestamp }

    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case sessionId = "session_id"
        case messageCount = "message_count"
    }

    public init(base: BaseAgentEvent = BaseAgentEvent(), sessionId: String?, messageCount: Int) {
        self.base = base
        self.sessionId = sessionId
        self.messageCount = messageCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = BaseAgentEvent(
            id: try c.decode(String.self, forKey: .id),
            timestamp: try c.decode(Date.self, forKey: .timestamp)
        )
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        messageCount = try c.decode(Int.self, forKey: .messageCount)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base.id, forKey: .id)
        try c.encode(base.timestamp, forKey: .timestamp)
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encode(messageCount, forKey: .messageCount)
    }
}
