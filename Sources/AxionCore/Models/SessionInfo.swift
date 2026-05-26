import Foundation

public struct SessionInfo: Codable, Equatable, Sendable {
    public let sessionId: String
    public let cwd: String
    public let model: String
    public let createdAt: Date?
    public let updatedAt: Date?
    public let messageCount: Int
    public let summary: String?
    public let status: String
    public let totalSteps: Int
    public let durationMs: Int?

    public init(
        sessionId: String,
        cwd: String,
        model: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        messageCount: Int = 0,
        summary: String? = nil,
        status: String = "unknown",
        totalSteps: Int = 0,
        durationMs: Int? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.summary = summary
        self.status = status
        self.totalSteps = totalSteps
        self.durationMs = durationMs
    }
}
