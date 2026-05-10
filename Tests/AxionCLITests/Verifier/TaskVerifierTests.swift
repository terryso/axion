import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] Core verification flow with MCP/LLM mocks
// [P1] Degradation and edge cases

// MARK: - Mock MCP Client for TaskVerifier Tests

/// Mock MCPClientProtocol for testing TaskVerifier without real MCP calls.
/// Supports stubbed responses per tool name and error injection.
final class MockVerifierMCPClient: MCPClientProtocol {
    var stubbedResults: [String: String] = [:]
    var callHistory: [(name: String, arguments: [String: Value])] = []
    var shouldThrow = false
    var throwError: Error?

    func callTool(name: String, arguments: [String: Value]) async throws -> String {
        callHistory.append((name: name, arguments: arguments))

        if shouldThrow {
            throw throwError ?? AxionError.mcpError(tool: name, reason: "Mock error")
        }

        return stubbedResults[name] ?? "{\"success\": true}"
    }

    func listTools() async throws -> [String] {
        return ["screenshot", "get_accessibility_tree", "launch_app", "click", "type_text"]
    }
}

// MARK: - Mock LLM Client for TaskVerifier Tests

/// Mock LLMClientProtocol for testing TaskVerifier without real LLM calls.
struct MockVerifierLLMClient: LLMClientProtocol {
    let promptResult: String

    func prompt(systemPrompt: String, userMessage: String, imagePaths: [String]) async throws -> String {
        return promptResult
    }
}

// MARK: - Failing Mock LLM Client

/// Mock LLM client that always throws, simulating LLM failure.
struct FailingMockLLMClient: LLMClientProtocol {
    func prompt(systemPrompt: String, userMessage: String, imagePaths: [String]) async throws -> String {
        throw AxionError.planningFailed(reason: "LLM service unavailable")
    }
}

// MARK: - TaskVerifier ATDD Tests

/// ATDD red-phase tests for TaskVerifier (Story 3-4 AC1, AC2, AC3, AC4, AC5).
/// Tests the full verification flow: MCP context capture, stop condition evaluation,
/// LLM-assisted evaluation, and graceful degradation on failures.
///
/// TDD RED PHASE: These tests will not compile until TaskVerifier is implemented
/// in Sources/AxionCLI/Verifier/TaskVerifier.swift and VerifierProtocol is updated
/// in Sources/AxionCore/Protocols/VerifierProtocol.swift.
final class TaskVerifierTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a minimal Plan with the given stop conditions.
    private func makePlan(stopWhen: [StopCondition] = []) -> Plan {
        Plan(
            id: UUID(),
            task: "Calculate 17*23",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch Calculator", expectedChange: "App opens"),
                Step(index: 1, tool: "type_text", parameters: ["text": .string("17*23=")],
                     purpose: "Type expression", expectedChange: "Expression entered")
            ],
            stopWhen: stopWhen,
            maxRetries: 3
        )
    }

    /// Creates executed steps simulating a successful Calculator session.
    private func makeExecutedSteps() -> [ExecutedStep] {
        return [
            ExecutedStep(
                stepIndex: 0,
                tool: "launch_app",
                parameters: ["app_name": .string("Calculator")],
                result: "{\"pid\": 1234, \"app_name\": \"Calculator\", \"status\": \"launched\"}",
                success: true,
                timestamp: Date()
            ),
            ExecutedStep(
                stepIndex: 1,
                tool: "list_windows",
                parameters: ["pid": .placeholder("$pid")],
                result: "{\"windows\": [{\"window_id\": 42, \"pid\": 1234, \"title\": \"Calculator\"}]}",
                success: true,
                timestamp: Date()
            ),
            ExecutedStep(
                stepIndex: 2,
                tool: "type_text",
                parameters: ["text": .string("17*23="), "pid": .int(1234), "window_id": .int(42)],
                result: "{\"success\": true}",
                success: true,
                timestamp: Date()
            )
        ]
    }

    /// Creates a RunContext for testing.
    private func makeContext() -> RunContext {
        RunContext(
            planId: UUID(),
            currentState: .verifying,
            currentStepIndex: 3,
            executedSteps: makeExecutedSteps(),
            replanCount: 0,
            config: .default
        )
    }

    /// Sample AX tree JSON with Calculator showing 391.
    private var calculatorAxTree: String {
        """
        {"role": "AXApplication", "children": [
            {"role": "AXWindow", "title": "Calculator", "pid": 1234, "children": [
                {"role": "AXStaticText", "title": "Display", "value": "391"},
                {"role": "AXButton", "title": "C"}
            ]}
        ]}
        """
    }

    // MARK: - P0 Type Existence (AC1)

    func test_taskVerifier_typeExists() {
        let _ = TaskVerifier.self
    }

    func test_taskVerifier_conformsToVerifierProtocol() {
        let mockMCP = MockVerifierMCPClient()
        let mockLLM = MockVerifierLLMClient(promptResult: "")
        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let _ = verifier as VerifierProtocol
    }

    // MARK: - P0 Full Verification Flow — Done (AC1, AC2, AC3)

    func test_verify_screenshotAndAxTreeCaptured_returnsDone() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"iVBORwkg==\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "done", "reason": "Calculator displays 391, which is 17*23"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .textAppears, value: "391")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        XCTAssertEqual(result.state, .done)
        // MCP should have been called for screenshot and AX tree
        XCTAssertTrue(mockMCP.callHistory.contains(where: { $0.name == ToolNames.screenshot }))
        XCTAssertTrue(mockMCP.callHistory.contains(where: { $0.name == ToolNames.getAccessibilityTree }))
    }

    // MARK: - P0 Stop Condition Not Met — Blocked (AC4)

    func test_verify_stopConditionNotMet_returnsBlocked() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = """
        {"role": "AXApplication", "children": [
            {"role": "AXWindow", "title": "Calculator", "children": [
                {"role": "AXStaticText", "value": "0"}
            ]}
        ]}
        """

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "blocked", "reason": "Calculator still shows 0, expression may not have been typed"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .textAppears, value: "391")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        XCTAssertEqual(result.state, .blocked)
        XCTAssertNotNil(result.reason)
    }

    // MARK: - P0 LLM Returns Needs Clarification (AC5)

    func test_verify_llmReturnsNeedsClarification_returnsNeedsClarification() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "needs_clarification", "reason": "Multiple windows found, which one to verify?"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .custom, value: "Result is correct")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        XCTAssertEqual(result.state, .needsClarification)
        XCTAssertEqual(result.reason, "Multiple windows found, which one to verify?")
    }

    // MARK: - P0 LLM Returns Done (AC3)

    func test_verify_llmReturnsDone_returnsDone() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "done", "reason": "Task verified"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .custom, value: "Calculator shows result")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        XCTAssertEqual(result.state, .done)
    }

    // MARK: - P0 LLM Returns Blocked (AC4)

    func test_verify_llmReturnsBlocked_returnsBlocked() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = """
        {"role": "AXApplication", "children": []}
        """

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "blocked", "reason": "Application window disappeared"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .custom, value: "Task done")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        XCTAssertEqual(result.state, .blocked)
        XCTAssertEqual(result.reason, "Application window disappeared")
    }

    // MARK: - P0 LLM Failure — Safe Degradation (AC2)

    func test_verify_llmFailure_returnsBlocked() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = FailingMockLLMClient()

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .custom, value: "Task done")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        XCTAssertEqual(result.state, .blocked)
        // Reason should mention LLM failure or degradation
        XCTAssertNotNil(result.reason)
    }

    // MARK: - P1 LLM Invalid JSON — Safe Degradation (AC2)

    func test_verify_llmInvalidJSON_returnsBlocked() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = MockVerifierLLMClient(promptResult: "This is not JSON at all")

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .custom, value: "Task done")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        XCTAssertEqual(result.state, .blocked)
    }

    // MARK: - P1 MCP Screenshot Failure — Degrades Gracefully (AC1)

    func test_verify_mcpScreenshotFailure_degradesGracefully() async throws {
        let mockMCP = MockVerifierMCPClient()
        // Screenshot fails but AX tree succeeds
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"error\": \"Permission denied\"}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "done", "reason": "Verified via AX tree"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .custom, value: "Task done")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        // Should still return a result (not crash), using AX tree only
        XCTAssertNotEqual(result.state, .planning) // just verify it's a terminal state
    }

    // MARK: - P1 MCP AX Tree Failure — Degrades Gracefully (AC1)

    func test_verify_mcpAxTreeFailure_degradesGracefully() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        // AX tree fails
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = "{\"error\": \"AX API unavailable\"}"

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "blocked", "reason": "Cannot verify without AX tree"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .custom, value: "Task done")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        // Should still return a result, falling back to LLM
        XCTAssertNotEqual(result.state, .planning)
    }

    // MARK: - P1 MCP Both Fail — Degrades Gracefully (AC1)

    func test_verify_mcpBothFail_degradesGracefully() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.shouldThrow = true
        mockMCP.throwError = AxionError.mcpError(tool: "screenshot", reason: "Helper not responding")

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "blocked", "reason": "No context available"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .custom, value: "Task done")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        // Both MCP calls failed, but verifier should still return a result (not crash)
        // Likely blocked since no visual context is available
        XCTAssertEqual(result.state, .blocked)
    }

    // MARK: - P1 Correct MCP Arguments (AC1)

    func test_verify_callsScreenshotWithCorrectWindowId() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "done", "reason": "OK"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .textAppears, value: "391")])
        let context = makeContext()

        _ = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        let screenshotCall = mockMCP.callHistory.first(where: { $0.name == ToolNames.screenshot })
        XCTAssertNotNil(screenshotCall)
        // Should include window_id=42 from the executed steps
        XCTAssertEqual(screenshotCall?.arguments["window_id"], .int(42))
    }

    func test_verify_callsGetAccessibilityTreeWithCorrectPid() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "done", "reason": "OK"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .textAppears, value: "391")])
        let context = makeContext()

        _ = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        let axTreeCall = mockMCP.callHistory.first(where: { $0.name == ToolNames.getAccessibilityTree })
        XCTAssertNotNil(axTreeCall)
        // Should include pid=1234 from the executed steps
        XCTAssertEqual(axTreeCall?.arguments["pid"], .int(1234))
    }

    // MARK: - P1 No Stop Conditions (AC3)

    func test_verify_noStopConditions_returnsDone() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "done", "reason": "No conditions to verify"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [])  // No stop conditions
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        XCTAssertEqual(result.state, .done)
    }

    // MARK: - P1 Local Match Skips LLM (AC2)

    func test_verify_textAppears_matchedLocally_skipsLLM() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        // This LLM result should never be used because textAppears "391" matches locally
        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "blocked", "reason": "Should not be called"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .textAppears, value: "391")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        // Should return .done based on local match, not LLM
        XCTAssertEqual(result.state, .done)
    }

    // MARK: - P0 Custom Condition Triggers LLM (AC2)

    func test_verify_customCondition_callsLLM() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "done", "reason": "Calculator shows the expected result"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .custom, value: "Calculator shows 17*23 result")])
        let context = makeContext()

        let result = try await verifier.verify(plan: plan, executedSteps: makeExecutedSteps(), context: context)

        XCTAssertEqual(result.state, .done)
    }

    // MARK: - P1 Context Without PID (AC1)

    func test_verify_contextWithoutPid_callsMCPWithoutPid() async throws {
        let mockMCP = MockVerifierMCPClient()
        mockMCP.stubbedResults[ToolNames.screenshot] = "{\"image_base64\": \"abc\", \"success\": true}"
        mockMCP.stubbedResults[ToolNames.getAccessibilityTree] = calculatorAxTree

        let mockLLM = MockVerifierLLMClient(promptResult: """
        {"status": "done", "reason": "OK"}
        """)

        let config = AxionConfig.default
        let verifier = TaskVerifier(mcpClient: mockMCP, llmClient: mockLLM, config: config)
        let plan = makePlan(stopWhen: [StopCondition(type: .custom, value: "Done")])

        // Steps without pid-producing tools
        let steps = [
            ExecutedStep(
                stepIndex: 0,
                tool: "click",
                parameters: ["x": .int(100), "y": .int(200)],
                result: "{\"success\": true}",
                success: true,
                timestamp: Date()
            )
        ]

        let context = RunContext(
            planId: plan.id,
            currentState: .verifying,
            currentStepIndex: 1,
            executedSteps: steps,
            replanCount: 0,
            config: .default
        )

        _ = try await verifier.verify(plan: plan, executedSteps: steps, context: context)

        let axTreeCall = mockMCP.callHistory.first(where: { $0.name == ToolNames.getAccessibilityTree })
        XCTAssertNotNil(axTreeCall)
        // Without pid, arguments should not contain pid key (or be empty)
        XCTAssertNil(axTreeCall?.arguments["pid"])
    }
}
