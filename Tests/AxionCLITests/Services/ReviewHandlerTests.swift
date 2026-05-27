import Foundation
import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("ReviewHandler")
struct ReviewHandlerTests {

    private func makeContext(
        runCompleteContext: RunCompleteContext? = nil
    ) -> EventHandlerContext {
        EventHandlerContext(
            sessionId: "test-session",
            config: AxionConfig(apiKey: ""),
            eventBus: nil,
            externallyModified: false,
            externallyModifiedFlag: nil,
            takeoverEvent: nil,
            runCompleteContext: runCompleteContext,
            sessionStore: SessionStore(sessionsDir: nil)
        )
    }

    private func makeRunCompleteContext() -> RunCompleteContext {
        RunCompleteContext(
            toolPairs: [],
            task: "test task",
            runId: "run-1",
            status: .success,
            usage: TokenUsage(inputTokens: 100, outputTokens: 50),
            totalCostUsd: 0.01,
            durationMs: 1000,
            numTurns: 8,
            costBreakdown: []
        )
    }

    @Test("identifier is 'review'")
    func testIdentifier() async {
        let handler = ReviewHandler(noReview: false, noMemory: false, reviewOrchestrator: nil)
        let id = await handler.identifier
        #expect(id == "review")
    }

    @Test("subscribed to AgentCompletedEvent")
    func testSubscribedEventTypes() async {
        let handler = ReviewHandler(noReview: false, noMemory: false, reviewOrchestrator: nil)
        let types = await handler.subscribedEventTypes
        #expect(types.contains { $0 == AgentCompletedEvent.self })
    }

    @Test("handler with noReview=true does nothing")
    func testNoReviewSkips() async {
        let handler = ReviewHandler(noReview: true, noMemory: false, reviewOrchestrator: nil)
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 5, durationMs: 1000, resultText: "done"
        )
        await handler.handle(event, context: context)
    }

    @Test("handler with noMemory=true does nothing")
    func testNoMemorySkips() async {
        let handler = ReviewHandler(noReview: false, noMemory: true, reviewOrchestrator: nil)
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 5, durationMs: 1000, resultText: "done"
        )
        await handler.handle(event, context: context)
    }

    @Test("handler with nil orchestrator skips")
    func testNilOrchestratorSkips() async {
        let handler = ReviewHandler(noReview: false, noMemory: false, reviewOrchestrator: nil)
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 5, durationMs: 1000, resultText: "done"
        )
        await handler.handle(event, context: context)
    }

    @Test("handler ignores non-completed events")
    func testIgnoresNonCompletedEvents() async {
        let handler = ReviewHandler(noReview: false, noMemory: false, reviewOrchestrator: nil)
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentFailedEvent(sessionId: "s1", error: "boom", stepsCompleted: 2)
        await handler.handle(event, context: context)
    }
}
