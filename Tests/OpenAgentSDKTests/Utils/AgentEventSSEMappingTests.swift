import XCTest
@testable import OpenAgentSDK

final class AgentEventSSEMappingTests: XCTestCase {

    // MARK: - AC1: ToolStartedEvent → stepStarted

    func testToolStartedMapsToStepStarted() {
        let event = ToolStartedEvent(sessionId: "s1", toolName: "bash", toolUseId: "xxx", input: nil)
        let result = AgentEventSSEMapping.map(event, stepIndex: 3)
        guard case .stepStarted(let data) = result else {
            XCTFail("Expected .stepStarted, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(data.stepIndex, 3)
        XCTAssertEqual(data.tool, "bash")
    }

    func testToolStartedDefaultStepIndex() {
        let event = ToolStartedEvent(sessionId: nil, toolName: "read", toolUseId: "tu_1", input: nil)
        let result = AgentEventSSEMapping.map(event)
        guard case .stepStarted(let data) = result else {
            XCTFail("Expected .stepStarted")
            return
        }
        XCTAssertEqual(data.stepIndex, 0)
        XCTAssertEqual(data.tool, "read")
    }

    // MARK: - AC2: AgentStartedEvent → runStarted

    func testAgentStartedMapsToRunStarted() {
        let event = AgentStartedEvent(sessionId: "s1", task: "do work")
        let result = AgentEventSSEMapping.map(event)
        guard case .runStarted(let data) = result else {
            XCTFail("Expected .runStarted, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(data.runId, "s1")
        XCTAssertEqual(data.task, "do work")
    }

    func testAgentStartedNilSessionId() {
        let event = AgentStartedEvent(sessionId: nil, task: "hello")
        let result = AgentEventSSEMapping.map(event)
        guard case .runStarted(let data) = result else {
            XCTFail("Expected .runStarted")
            return
        }
        XCTAssertEqual(data.runId, "")
        XCTAssertEqual(data.task, "hello")
    }

    // MARK: - AC3: LLMCostEvent → costUpdate

    func testLLMCostMapsToCostUpdate() {
        let event = LLMCostEvent(
            sessionId: "s1",
            model: "claude-sonnet-4-6",
            inputTokens: 100,
            outputTokens: 50,
            cacheCreationInputTokens: 10,
            cacheReadInputTokens: 20,
            estimatedCostUsd: 0.003
        )
        let result = AgentEventSSEMapping.map(event)
        guard case .costUpdate(let data) = result else {
            XCTFail("Expected .costUpdate, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(data.model, "claude-sonnet-4-6")
        XCTAssertEqual(data.inputTokens, 100)
        XCTAssertEqual(data.outputTokens, 50)
        XCTAssertEqual(data.cacheCreationInputTokens, 10)
        XCTAssertEqual(data.cacheReadInputTokens, 20)
        XCTAssertEqual(data.estimatedCostUsd, 0.003)
    }

    func testLLMCostWithNilCacheFields() {
        let event = LLMCostEvent(
            sessionId: "s1",
            model: "claude-haiku-4-5",
            inputTokens: 200,
            outputTokens: 30,
            cacheCreationInputTokens: nil,
            cacheReadInputTokens: nil,
            estimatedCostUsd: 0.001
        )
        let result = AgentEventSSEMapping.map(event)
        guard case .costUpdate(let data) = result else {
            XCTFail("Expected .costUpdate")
            return
        }
        XCTAssertNil(data.cacheCreationInputTokens)
        XCTAssertNil(data.cacheReadInputTokens)
        XCTAssertEqual(data.inputTokens, 200)
    }

    // MARK: - AC4: AgentCompletedEvent → runCompleted

    func testAgentCompletedMapsToRunCompleted() {
        let event = AgentCompletedEvent(sessionId: "s1", totalSteps: 5, durationMs: 3200, resultText: nil)
        let result = AgentEventSSEMapping.map(event)
        guard case .runCompleted(let data) = result else {
            XCTFail("Expected .runCompleted, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(data.runId, "s1")
        XCTAssertEqual(data.finalStatus, "completed")
        XCTAssertEqual(data.totalSteps, 5)
        XCTAssertEqual(data.durationMs, 3200)
    }

    func testAgentCompletedNilSessionId() {
        let event = AgentCompletedEvent(sessionId: nil, totalSteps: 2, durationMs: 100, resultText: "ok")
        let result = AgentEventSSEMapping.map(event)
        guard case .runCompleted(let data) = result else {
            XCTFail("Expected .runCompleted")
            return
        }
        XCTAssertEqual(data.runId, "")
    }

    // MARK: - AC5: ToolCompletedEvent → stepCompleted

    func testToolCompletedMapsToStepCompleted() {
        let event = ToolCompletedEvent(sessionId: "s1", toolUseId: "tu_1", toolName: "bash", durationMs: 150, isError: false)
        let result = AgentEventSSEMapping.map(event, stepIndex: 2)
        guard case .stepCompleted(let data) = result else {
            XCTFail("Expected .stepCompleted, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(data.stepIndex, 2)
        XCTAssertEqual(data.tool, "bash")
        XCTAssertEqual(data.success, true)
        XCTAssertEqual(data.durationMs, 150)
    }

    func testToolCompletedError() {
        let event = ToolCompletedEvent(sessionId: "s1", toolUseId: "tu_1", toolName: "bash", durationMs: 50, isError: true)
        let result = AgentEventSSEMapping.map(event)
        guard case .stepCompleted(let data) = result else {
            XCTFail("Expected .stepCompleted")
            return
        }
        XCTAssertEqual(data.success, false)
    }

    // MARK: - AC6: Unmapped event types → nil

    func testSessionCreatedReturnsNil() {
        let event = SessionCreatedEvent(sessionId: "s1", task: "do work", model: "claude")
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    func testToolStreamingReturnsNil() {
        let event = ToolStreamingEvent(sessionId: "s1", toolUseId: "tu_1", chunk: "data")
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    func testSessionClosedReturnsNil() {
        let event = SessionClosedEvent(sessionId: "s1", finalStatus: .completed)
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    func testAgentFailedReturnsNil() {
        let event = AgentFailedEvent(sessionId: "s1", error: "boom", stepsCompleted: 3)
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    func testSessionAutoSavedReturnsNil() {
        let event = SessionAutoSavedEvent(sessionId: "s1", messageCount: 5)
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    func testToolFailedReturnsNil() {
        let event = ToolFailedEvent(sessionId: "s1", toolUseId: "tu_1", toolName: "bash", error: "oops")
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    func testAgentInterruptedReturnsNil() {
        let event = AgentInterruptedEvent(sessionId: "s1", stepsCompleted: 2)
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    func testLLMRequestStartedReturnsNil() {
        let event = LLMRequestStartedEvent(sessionId: "s1", model: "claude-sonnet-4-6")
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    func testLLMResponseReceivedReturnsNil() {
        let event = LLMResponseReceivedEvent(sessionId: "s1", model: "claude-sonnet-4-6", durationMs: 500)
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    func testAgentResumedReturnsNil() {
        let event = AgentResumedEvent(sessionId: "s1", resumeContext: "continue")
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    func testSessionRestoredReturnsNil() {
        let event = SessionRestoredEvent(sessionId: "s1", messageCount: 3, originalCreatedAt: Date())
        XCTAssertNil(AgentEventSSEMapping.map(event))
    }

    // MARK: - stepIndex pass-through

    func testStepIndexPassedToToolStarted() {
        let event = ToolStartedEvent(sessionId: "s1", toolName: "bash", toolUseId: "tu_1", input: nil)
        let result = AgentEventSSEMapping.map(event, stepIndex: 7)
        guard case .stepStarted(let data) = result else {
            XCTFail("Expected .stepStarted")
            return
        }
        XCTAssertEqual(data.stepIndex, 7)
    }

    func testStepIndexPassedToToolCompleted() {
        let event = ToolCompletedEvent(sessionId: "s1", toolUseId: "tu_1", toolName: "bash", durationMs: 100, isError: false)
        let result = AgentEventSSEMapping.map(event, stepIndex: 7)
        guard case .stepCompleted(let data) = result else {
            XCTFail("Expected .stepCompleted")
            return
        }
        XCTAssertEqual(data.stepIndex, 7)
    }

    // MARK: - stepIndex ignored for non-tool events

    func testStepIndexIgnoredForAgentStarted() {
        let event = AgentStartedEvent(sessionId: "s1", task: "do work")
        let result = AgentEventSSEMapping.map(event, stepIndex: 99)
        guard case .runStarted = result else {
            XCTFail("Expected .runStarted")
            return
        }
    }

    func testStepIndexIgnoredForLLMCost() {
        let event = LLMCostEvent(
            sessionId: "s1", model: "m", inputTokens: 1, outputTokens: 1,
            cacheCreationInputTokens: nil, cacheReadInputTokens: nil, estimatedCostUsd: 0.01
        )
        let result = AgentEventSSEMapping.map(event, stepIndex: 99)
        guard case .costUpdate = result else {
            XCTFail("Expected .costUpdate")
            return
        }
    }

    func testStepIndexIgnoredForAgentCompleted() {
        let event = AgentCompletedEvent(sessionId: "s1", totalSteps: 3, durationMs: 100, resultText: nil)
        let result = AgentEventSSEMapping.map(event, stepIndex: 99)
        guard case .runCompleted = result else {
            XCTFail("Expected .runCompleted")
            return
        }
    }
}
