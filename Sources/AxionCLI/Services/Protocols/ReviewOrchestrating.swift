import Foundation
import OpenAgentSDK

/// Protocol abstracting ReviewOrchestrator for testability.
protocol ReviewOrchestrating: Sendable {
    func shouldReview(
        sessionId: String,
        messageCount: Int,
        config: ReviewAgentConfig
    ) -> (memory: Bool, skill: Bool)

    func executeReview(
        parentAgent: Agent,
        messages: [SDKMessage],
        config: ReviewAgentConfig
    ) async -> ReviewAgentResult?
}

extension ReviewOrchestrator: ReviewOrchestrating {}
