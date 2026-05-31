import Foundation
import OpenAgentSDK

/// Emitted by RunOrchestrator when the SDK message stream produces a `.system(.paused)` message.
///
/// TGEventHandler subscribes to this event to show an inline keyboard to the user in Telegram.
struct AgentPausedEvent: AgentEvent, Equatable {
    let base: BaseAgentEvent

    /// Reason the agent paused (e.g. "tool_approval", "clarification_needed").
    let reason: String

    /// Session ID of the paused run.
    let sessionId: String

    /// Whether the agent can be resumed.
    let canResume: Bool

    /// Unique ID for this pause, used to correlate resume handle with session store entry.
    let pendingId: String

    var id: String { base.id }
    var timestamp: Date { base.timestamp }

    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case reason
        case sessionId = "session_id"
        case canResume = "can_resume"
        case pendingId = "pending_id"
    }

    init(
        base: BaseAgentEvent = BaseAgentEvent(),
        reason: String,
        sessionId: String,
        canResume: Bool = true,
        pendingId: String
    ) {
        self.base = base
        self.reason = reason
        self.sessionId = sessionId
        self.canResume = canResume
        self.pendingId = pendingId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = BaseAgentEvent(
            id: try c.decode(String.self, forKey: .id),
            timestamp: try c.decode(Date.self, forKey: .timestamp)
        )
        reason = try c.decode(String.self, forKey: .reason)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        canResume = try c.decode(Bool.self, forKey: .canResume)
        pendingId = try c.decode(String.self, forKey: .pendingId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base.id, forKey: .id)
        try c.encode(base.timestamp, forKey: .timestamp)
        try c.encode(reason, forKey: .reason)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(canResume, forKey: .canResume)
        try c.encode(pendingId, forKey: .pendingId)
    }
}
