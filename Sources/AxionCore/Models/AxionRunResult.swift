import Foundation

public struct AxionRunResult: Codable, Equatable, Sendable {
    public let sessionId: String
    public let task: String
    public let state: AxionRunState
    public let totalSteps: Int
    public let durationMs: Int
    public let runSucceeded: Bool
    public let errorMessage: String?
    public let runCompleteContext: RunCompleteContextWrapper?
    public let responseText: String?
    public let createdAt: Date

    public init(
        sessionId: String,
        task: String,
        state: AxionRunState,
        totalSteps: Int,
        durationMs: Int,
        runSucceeded: Bool,
        errorMessage: String? = nil,
        runCompleteContext: RunCompleteContextWrapper? = nil,
        responseText: String? = nil,
        createdAt: Date
    ) {
        self.sessionId = sessionId
        self.task = task
        self.state = state
        self.totalSteps = totalSteps
        self.durationMs = durationMs
        self.runSucceeded = runSucceeded
        self.errorMessage = errorMessage
        self.runCompleteContext = runCompleteContext
        self.responseText = responseText
        self.createdAt = createdAt
    }

    /// Convenience factory for a failed run result with zero steps and duration.
    public static func failedRun(
        sessionId: String,
        task: String,
        error: String,
        createdAt: Date
    ) -> AxionRunResult {
        AxionRunResult(
            sessionId: sessionId,
            task: task,
            state: .failed,
            totalSteps: 0,
            durationMs: 0,
            runSucceeded: false,
            errorMessage: error,
            createdAt: createdAt
        )
    }
}
