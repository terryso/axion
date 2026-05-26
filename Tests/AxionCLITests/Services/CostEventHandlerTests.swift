import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("CostEventHandler")
struct CostEventHandlerTests {

    private func makeContext(runCompleteContext: RunCompleteContext? = nil) -> EventHandlerContext {
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

    private func makeRunCompleteContext(
        numTurns: Int = 3,
        inputTokens: Int = 1000,
        outputTokens: Int = 500,
        totalCostUsd: Double = 0.0342
    ) -> RunCompleteContext {
        RunCompleteContext(
            toolPairs: [],
            task: "test task",
            runId: nil,
            status: .success,
            usage: TokenUsage(inputTokens: inputTokens, outputTokens: outputTokens),
            totalCostUsd: totalCostUsd,
            durationMs: 5000,
            numTurns: numTurns,
            costBreakdown: []
        )
    }

    @Test("identifier is 'cost'")
    func testIdentifier() async {
        let handler = CostEventHandler()
        let id = await handler.identifier
        #expect(id == "cost")
    }

    @Test("subscribed to completed, failed, and interrupted events")
    func testSubscribedEventTypes() async {
        let handler = CostEventHandler()
        let types = await handler.subscribedEventTypes
        #expect(types.contains { $0 == AgentCompletedEvent.self })
        #expect(types.contains { $0 == AgentFailedEvent.self })
        #expect(types.contains { $0 == AgentInterruptedEvent.self })
    }

    @Test("formatSummary produces correct output")
    func testFormatSummary() {
        let result = CostEventHandler.formatSummary(numTurns: 5, totalTokens: 2800, totalCostUsd: 0.1234)
        #expect(result == "[axion] LLM 调用: 5轮, Tokens: 2800, 预估成本: $0.1234\n")
    }

    @Test("formatSummary pads cost to 4 decimal places")
    func testFormatSummaryPadsCost() {
        let result = CostEventHandler.formatSummary(numTurns: 1, totalTokens: 100, totalCostUsd: 0.1)
        #expect(result.contains("$0.1000"))
    }

    @Test("handler does not crash when runCompleteContext is nil")
    func testSkipsWhenNoRunCompleteContext() async {
        let handler = CostEventHandler()
        let context = makeContext(runCompleteContext: nil)
        let event = AgentFailedEvent(sessionId: "s1", error: "boom", stepsCompleted: 2)
        // Should not crash or throw
        await handler.handle(event, context: context)
    }

    @Test("handler processes AgentCompletedEvent with valid context")
    func testHandleAgentCompletedEvent() async {
        let handler = CostEventHandler()
        let ctx = makeRunCompleteContext(numTurns: 5, inputTokens: 2000, outputTokens: 800, totalCostUsd: 0.1234)
        let context = makeContext(runCompleteContext: ctx)
        let event = AgentCompletedEvent(sessionId: "s1", totalSteps: 5, durationMs: 1000, resultText: "done")
        // Should not crash
        await handler.handle(event, context: context)
    }

    @Test("handler processes AgentInterruptedEvent with valid context")
    func testHandleAgentInterruptedEvent() async {
        let handler = CostEventHandler()
        let ctx = makeRunCompleteContext(numTurns: 2, inputTokens: 500, outputTokens: 200, totalCostUsd: 0.01)
        let context = makeContext(runCompleteContext: ctx)
        let event = AgentInterruptedEvent(sessionId: "s1", stepsCompleted: 2)
        await handler.handle(event, context: context)
    }
}
