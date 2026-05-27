import Foundation
import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("TraceEventHandler")
struct TraceEventHandlerTests {

    private func makeContext(sessionId: String? = "test-session") -> EventHandlerContext {
        EventHandlerContext(
            sessionId: sessionId,
            config: AxionConfig(apiKey: ""),
            eventBus: nil,
            externallyModified: false,
            externallyModifiedFlag: nil,
            takeoverEvent: nil,
            runCompleteContext: nil,
            sessionStore: SessionStore(sessionsDir: nil)
        )
    }

    @Test("identifier is 'trace'")
    func testIdentifier() async {
        let handler = TraceEventHandler(traceDir: "/tmp/axion-test-trace")
        let id = await handler.identifier
        #expect(id == "trace")
    }

    @Test("subscribed to all events (empty array)")
    func testSubscribedEventTypes() async {
        let handler = TraceEventHandler(traceDir: "/tmp/axion-test-trace")
        let types = await handler.subscribedEventTypes
        #expect(types.isEmpty)
    }

    @Test("handler with nil traceDir does nothing")
    func testNilTraceDir() async {
        let handler = TraceEventHandler(traceDir: nil)
        let context = makeContext()
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 5, durationMs: 1000, resultText: "done"
        )
        await handler.handle(event, context: context)
    }

    @Test("handler records AgentStartedEvent")
    func testRecordsAgentStarted() async {
        let tmpDir = "/tmp/axion-test-trace-\(UUID().uuidString)"
        let handler = TraceEventHandler(traceDir: tmpDir)
        let context = makeContext()
        let event = AgentStartedEvent(sessionId: "s1", task: "do something")
        await handler.handle(event, context: context)

        let traceFile = "\(tmpDir)/test-session/events.jsonl"
        let content = try? String(contentsOfFile: traceFile, encoding: .utf8)
        #expect(content?.contains("agent_started") == true)
        #expect(content?.contains("do something") == true)
    }

    @Test("handler records ToolStartedEvent")
    func testRecordsToolStarted() async {
        let tmpDir = "/tmp/axion-test-trace-\(UUID().uuidString)"
        let handler = TraceEventHandler(traceDir: tmpDir)
        let context = makeContext()
        let event = ToolStartedEvent(
            sessionId: "s1", toolName: "bash", toolUseId: "tu1", input: nil
        )
        await handler.handle(event, context: context)

        let traceFile = "\(tmpDir)/test-session/events.jsonl"
        let content = try? String(contentsOfFile: traceFile, encoding: .utf8)
        #expect(content?.contains("tool_started") == true)
        #expect(content?.contains("bash") == true)
    }

    @Test("handler records LLMCostEvent")
    func testRecordsLLMCost() async {
        let tmpDir = "/tmp/axion-test-trace-\(UUID().uuidString)"
        let handler = TraceEventHandler(traceDir: tmpDir)
        let context = makeContext()
        let event = LLMCostEvent(
            sessionId: "s1",
            model: "claude-sonnet-4-6",
            inputTokens: 500,
            outputTokens: 200,
            cacheCreationInputTokens: nil,
            cacheReadInputTokens: nil,
            estimatedCostUsd: 0.03
        )
        await handler.handle(event, context: context)

        let traceFile = "\(tmpDir)/test-session/events.jsonl"
        let content = try? String(contentsOfFile: traceFile, encoding: .utf8)
        #expect(content?.contains("llm_cost") == true)
        #expect(content?.contains("claude-sonnet-4-6") == true)
    }

    @Test("handler records multiple events sequentially")
    func testRecordsMultipleEvents() async {
        let tmpDir = "/tmp/axion-test-trace-\(UUID().uuidString)"
        let handler = TraceEventHandler(traceDir: tmpDir)
        let context = makeContext()

        let event1 = AgentStartedEvent(sessionId: "s1", task: "task 1")
        let event2 = ToolStartedEvent(sessionId: "s1", toolName: "bash", toolUseId: "tu1", input: nil)
        let event3 = ToolCompletedEvent(sessionId: "s1", toolUseId: "tu1", toolName: "bash", durationMs: 100, isError: false, output: nil)

        await handler.handle(event1, context: context)
        await handler.handle(event2, context: context)
        await handler.handle(event3, context: context)

        let traceFile = "\(tmpDir)/test-session/events.jsonl"
        let content = try? String(contentsOfFile: traceFile, encoding: .utf8)
        let lines = content?.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines?.count == 3)
    }
}
