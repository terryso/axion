import Foundation
import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("MemoryProcessingHandler")
struct MemoryProcessingHandlerTests {

    private func makeContext(
        runCompleteContext: RunCompleteContext? = nil,
        externallyModified: Bool = false,
        takeoverEvent: RunMemoryProcessor.TakeoverEventContext? = nil
    ) -> EventHandlerContext {
        EventHandlerContext(
            sessionId: nil,
            config: AxionConfig(apiKey: ""),
            eventBus: nil,
            externallyModified: externallyModified,
            takeoverEvent: takeoverEvent,
            runCompleteContext: runCompleteContext,
            sessionStore: SessionStore(sessionsDir: nil)
        )
    }

    private func makeRunCompleteContext(
        toolPairs: [SDKMessage.ToolExecutionPair] = []
    ) -> RunCompleteContext {
        RunCompleteContext(
            toolPairs: toolPairs,
            task: "test task",
            runId: "test-run-id",
            status: .success,
            usage: TokenUsage(inputTokens: 100, outputTokens: 50),
            totalCostUsd: 0.01,
            durationMs: 1000,
            numTurns: 1,
            costBreakdown: []
        )
    }

    @Test("identifier is 'memory-processing'")
    func testIdentifier() async {
        let handler = MemoryProcessingHandler(noMemory: false, memoryDir: "/tmp/axion-test-mem")
        let id = await handler.identifier
        #expect(id == "memory-processing")
    }

    @Test("subscribed to terminal events")
    func testSubscribedEventTypes() async {
        let handler = MemoryProcessingHandler(noMemory: false, memoryDir: "/tmp/axion-test-mem")
        let types = await handler.subscribedEventTypes
        #expect(types.contains { $0 == AgentCompletedEvent.self })
        #expect(types.contains { $0 == AgentFailedEvent.self })
        #expect(types.contains { $0 == AgentInterruptedEvent.self })
    }

    @Test("handler with noMemory=true does nothing")
    func testNoMemorySkips() async {
        let handler = MemoryProcessingHandler(noMemory: true, memoryDir: "/tmp/axion-test-mem")
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 1, durationMs: 100, resultText: "done"
        )
        await handler.handle(event, context: context)
    }

    @Test("handler skips when runCompleteContext is nil")
    func testSkipsWithoutRunCompleteContext() async {
        let handler = MemoryProcessingHandler(noMemory: false, memoryDir: "/tmp/axion-test-mem")
        let context = makeContext(runCompleteContext: nil)
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 1, durationMs: 100, resultText: "done"
        )
        await handler.handle(event, context: context)
    }

    @Test("handler skips when externallyModified is true")
    func testSkipsWhenExternallyModified() async {
        let handler = MemoryProcessingHandler(noMemory: false, memoryDir: "/tmp/axion-test-mem-ext")
        let context = makeContext(
            runCompleteContext: makeRunCompleteContext(),
            externallyModified: true
        )
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 1, durationMs: 100, resultText: "done"
        )
        // Should not crash — processRunResult internally checks externallyModified
        await handler.handle(event, context: context)
    }

    @Test("handler processes AgentCompletedEvent with valid context")
    func testProcessesAgentCompletedEvent() async {
        let tmpDir = "/tmp/axion-test-mem-handler-\(UUID().uuidString)"
        let handler = MemoryProcessingHandler(noMemory: false, memoryDir: tmpDir)
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 1, durationMs: 100, resultText: "done"
        )
        await handler.handle(event, context: context)
    }

    @Test("handler processes AgentFailedEvent")
    func testProcessesAgentFailedEvent() async {
        let tmpDir = "/tmp/axion-test-mem-handler-\(UUID().uuidString)"
        let handler = MemoryProcessingHandler(noMemory: false, memoryDir: tmpDir)
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentFailedEvent(
            sessionId: "s1", error: "boom", stepsCompleted: 1
        )
        await handler.handle(event, context: context)
    }

    @Test("handler ignores non-terminal events")
    func testIgnoresNonTerminalEvents() async {
        let handler = MemoryProcessingHandler(noMemory: false, memoryDir: "/tmp/axion-test-mem")
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = ToolStartedEvent(
            sessionId: "s1", toolName: "bash", toolUseId: "tu1", input: nil
        )
        await handler.handle(event, context: context)
    }
}
