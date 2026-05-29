import Foundation
import OpenAgentSDK

/// Emitted by ReviewScheduler after a review agent completes (success or failure).
///
/// TGEventHandler subscribes to this event to push a summary notification to Telegram.
/// In non-Gateway modes (CLI / HTTP API) no subscriber exists, so the event is silently discarded.
struct ReviewResultEvent: AgentEvent, Equatable {
    let base: BaseAgentEvent

    /// Human-readable summary of the review outcome.
    let summary: String

    /// Descriptions of memory changes made during the review.
    let memoryChanges: [String]

    /// Descriptions of skill changes made during the review.
    let skillChanges: [String]

    /// Whether the review completed successfully.
    let success: Bool

    /// Wall-clock duration of the review in milliseconds.
    let durationMs: Int

    /// Session ID of the parent run that triggered the review.
    let sessionId: String

    var id: String { base.id }
    var timestamp: Date { base.timestamp }

    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case summary
        case memoryChanges = "memory_changes"
        case skillChanges = "skill_changes"
        case success
        case durationMs = "duration_ms"
        case sessionId = "session_id"
    }

    init(
        base: BaseAgentEvent = BaseAgentEvent(),
        summary: String,
        memoryChanges: [String],
        skillChanges: [String],
        success: Bool,
        durationMs: Int,
        sessionId: String
    ) {
        self.base = base
        self.summary = summary
        self.memoryChanges = memoryChanges
        self.skillChanges = skillChanges
        self.success = success
        self.durationMs = durationMs
        self.sessionId = sessionId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = BaseAgentEvent(
            id: try c.decode(String.self, forKey: .id),
            timestamp: try c.decode(Date.self, forKey: .timestamp)
        )
        summary = try c.decode(String.self, forKey: .summary)
        memoryChanges = try c.decode([String].self, forKey: .memoryChanges)
        skillChanges = try c.decode([String].self, forKey: .skillChanges)
        success = try c.decode(Bool.self, forKey: .success)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        sessionId = try c.decode(String.self, forKey: .sessionId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base.id, forKey: .id)
        try c.encode(base.timestamp, forKey: .timestamp)
        try c.encode(summary, forKey: .summary)
        try c.encode(memoryChanges, forKey: .memoryChanges)
        try c.encode(skillChanges, forKey: .skillChanges)
        try c.encode(success, forKey: .success)
        try c.encode(durationMs, forKey: .durationMs)
        try c.encode(sessionId, forKey: .sessionId)
    }
}
