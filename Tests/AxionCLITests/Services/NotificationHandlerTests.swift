import Foundation
import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("NotificationHandler")
struct NotificationHandlerTests {

    private func makeContext(
        runCompleteContext: RunCompleteContext? = nil
    ) -> EventHandlerContext {
        EventHandlerContext(
            sessionId: nil,
            config: AxionConfig(apiKey: ""),
            eventBus: nil,
            externallyModified: false,
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
            totalCostUsd: 0.05,
            durationMs: 5000,
            numTurns: 3,
            costBreakdown: []
        )
    }

    @Test("identifier is 'notification'")
    func testIdentifier() async {
        let handler = NotificationHandler(json: false)
        let id = await handler.identifier
        #expect(id == "notification")
    }

    @Test("subscribed to terminal events")
    func testSubscribedEventTypes() async {
        let handler = NotificationHandler(json: false)
        let types = await handler.subscribedEventTypes
        #expect(types.contains { $0 == AgentCompletedEvent.self })
        #expect(types.contains { $0 == AgentFailedEvent.self })
        #expect(types.contains { $0 == AgentInterruptedEvent.self })
    }

    @Test("handler with json=true skips")
    func testJsonModeSkips() async {
        let handler = NotificationHandler(json: true)
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 3, durationMs: 5000, resultText: "done"
        )
        await handler.handle(event, context: context)
    }

    @Test("handler skips when runCompleteContext is nil")
    func testSkipsWithoutRunCompleteContext() async {
        let handler = NotificationHandler(json: false)
        let context = makeContext(runCompleteContext: nil)
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 3, durationMs: 5000, resultText: "done"
        )
        await handler.handle(event, context: context)
    }

    @Test("handler sends notification on AgentCompletedEvent")
    func testSendsNotificationOnCompleted() async {
        let handler = NotificationHandler(json: false)
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 3, durationMs: 5000, resultText: "done"
        )
        await handler.handle(event, context: context)
    }

    @Test("handler sends notification on AgentFailedEvent")
    func testSendsNotificationOnFailed() async {
        let handler = NotificationHandler(json: false)
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentFailedEvent(
            sessionId: "s1", error: "something went wrong", stepsCompleted: 2
        )
        await handler.handle(event, context: context)
    }

    @Test("handler ignores non-terminal events")
    func testIgnoresNonTerminalEvents() async {
        let handler = NotificationHandler(json: false)
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = ToolStartedEvent(
            sessionId: "s1", toolName: "bash", toolUseId: "tu1", input: nil
        )
        await handler.handle(event, context: context)
    }
}
