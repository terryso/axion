import Foundation
import OpenAgentSDK

import AxionCore

actor ReviewHandler: EventHandler {
    let identifier = "review"
    let subscribedEventTypes: [any AgentEvent.Type] = [AgentCompletedEvent.self]

    private let noReview: Bool
    private let noMemory: Bool
    private let reviewOrchestrator: ReviewOrchestrator?

    init(noReview: Bool, noMemory: Bool, reviewOrchestrator: ReviewOrchestrator?) {
        self.noReview = noReview
        self.noMemory = noMemory
        self.reviewOrchestrator = reviewOrchestrator
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard !noReview else { return }
        guard !noMemory else { return }
        guard event is AgentCompletedEvent else { return }
        guard let orchestrator = reviewOrchestrator else { return }

        let reviewConfig = ReviewAgentConfig()
        let messageCount = context.runCompleteContext?.numTurns ?? 0
        let (doMemory, doSkill) = orchestrator.shouldReview(
            sessionId: context.sessionId ?? "",
            messageCount: messageCount,
            config: reviewConfig
        )

        if doMemory || doSkill {
            fputs("[axion] review handler: review scheduled (memory=\(doMemory), skill=\(doSkill))\n", stderr)
        }
    }
}
