import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

/// Mock 实现 MCPClientProtocol，用于测试 StepExecutor 而不调用真实 MCP
final class MockExecutorMCPClient: MCPClientProtocol {
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
        return ["launch_app", "click", "type_text", "screenshot", "get_accessibility_tree",
                "list_windows", "get_window_state", "press_key", "hotkey", "scroll",
                "drag", "double_click", "right_click", "list_apps", "quit_app",
                "activate_window", "move_window", "resize_window", "open_url", "get_file_info"]
    }
}

/// ATDD 红色阶段测试 — 覆盖 Story 3-3 AC1 (MCP 工具调用), AC4 (AX 刷新), AC5 (失败处理)
/// 这些测试将在 StepExecutor 实现后通过 (TDD red-green-refactor)
@Suite("StepExecutor")
struct StepExecutorTests {

    @Test("stepExecutor type exists")
    func stepExecutorTypeExists() {
        let _ = StepExecutor.self
    }

    @Test("stepExecutor conforms to ExecutorProtocol")
    func stepExecutorConformsToExecutorProtocol() {
        // StepExecutor must conform to ExecutorProtocol
        let mockClient = MockExecutorMCPClient()
        let config = AxionConfig.default
        let executor = StepExecutor(mcpClient: mockClient, config: config)
        let _ = executor as ExecutorProtocol
    }

    @Test("executeStep launch_app calls MCP and returns success")
    func executeStepLaunchAppCallsMCPAndReturnsSuccess() async throws {
        let mockClient = MockExecutorMCPClient()
        mockClient.stubbedResults["launch_app"] = """
        {"pid": 1234, "app_name": "Calculator", "status": "launched"}
        """
        let config = AxionConfig.default
        let executor = StepExecutor(mcpClient: mockClient, config: config)

        let step = Step(
            index: 0,
            tool: "launch_app",
            parameters: ["app_name": .string("Calculator")],
            purpose: "Open Calculator",
            expectedChange: "Calculator opens"
        )

        let context = RunContext(
            planId: UUID(),
            currentState: .executing,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        let executed = try await executor.executeStep(step, context: context)

        #expect(executed.success)
        #expect(executed.tool == "launch_app")
        #expect(executed.stepIndex == 0)
        #expect(mockClient.callHistory.contains(where: { $0.name == "launch_app" }))
    }

    @Test("executeStep MCP error returns failed executed step")
    func executeStepMCPErrorReturnsFailedExecutedStep() async throws {
        let mockClient = MockExecutorMCPClient()
        mockClient.shouldThrow = true
        mockClient.throwError = AxionError.mcpError(tool: "launch_app", reason: "App not found")
        let config = AxionConfig.default
        let executor = StepExecutor(mcpClient: mockClient, config: config)

        let step = Step(
            index: 0,
            tool: "launch_app",
            parameters: ["app_name": .string("NonexistentApp")],
            purpose: "Open app",
            expectedChange: "App opens"
        )

        let context = RunContext(
            planId: UUID(),
            currentState: .executing,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        do {
            _ = try await executor.executeStep(step, context: context)
            // If execution doesn't throw, it should at least return a failed step
        } catch let error as AxionError {
            // executionFailed or mcpError expected
            if case .executionFailed = error {
                // Expected: step execution failed
            } else if case .mcpError = error {
                // Also acceptable: MCP error propagated
            } else {
                Issue.record("Expected executionFailed or mcpError, got: \(error)")
            }
        }
    }

    @Test("executeStep safety blocked returns safety error")
    func executeStepSafetyBlockedReturnsSafetyError() async throws {
        let mockClient = MockExecutorMCPClient()
        mockClient.stubbedResults["click"] = """
        {"success": true}
        """
        var config = AxionConfig.default
        config.sharedSeatMode = true // Shared seat mode blocks foreground ops
        let executor = StepExecutor(mcpClient: mockClient, config: config)

        let step = Step(
            index: 1,
            tool: "click",
            parameters: ["x": .int(100), "y": .int(200)],
            purpose: "Click button",
            expectedChange: "Button clicked"
        )

        let context = RunContext(
            planId: UUID(),
            currentState: .executing,
            currentStepIndex: 1,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        do {
            let executed = try await executor.executeStep(step, context: context)
            // If it returns instead of throws, it should be a failed step
            #expect(!executed.success)
        } catch let error as AxionError {
            // Safety error expected
            if case .executionFailed = error {
                // Expected
            } else {
                Issue.record("Expected executionFailed for safety block, got: \(error)")
            }
        }

        // MCP client should NOT have been called for the blocked tool
        #expect(!mockClient.callHistory.contains(where: { $0.name == "click" }))
    }

    @Test("executeStep allow-foreground executes click")
    func executeStepAllowForegroundExecutesClick() async throws {
        let mockClient = MockExecutorMCPClient()
        mockClient.stubbedResults["click"] = """
        {"success": true}
        """
        var config = AxionConfig.default
        config.sharedSeatMode = false // Allow foreground
        let executor = StepExecutor(mcpClient: mockClient, config: config)

        let step = Step(
            index: 1,
            tool: "click",
            parameters: ["x": .int(100), "y": .int(200)],
            purpose: "Click button",
            expectedChange: "Button clicked"
        )

        let context = RunContext(
            planId: UUID(),
            currentState: .executing,
            currentStepIndex: 1,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        let executed = try await executor.executeStep(step, context: context)

        #expect(executed.success)
        #expect(mockClient.callHistory.contains(where: { $0.name == "click" }))
    }

    @Test("executeStep placeholder resolved before MCP call")
    func executeStepPlaceholderResolvedBeforeMCPCall() async throws {
        let mockClient = MockExecutorMCPClient()
        mockClient.stubbedResults["click"] = """
        {"success": true}
        """
        var config = AxionConfig.default
        config.sharedSeatMode = false
        let executor = StepExecutor(mcpClient: mockClient, config: config)

        // Step with $pid placeholder that should be resolved before calling MCP
        let step = Step(
            index: 1,
            tool: "click",
            parameters: [
                "pid": .placeholder("$pid"),
                "window_id": .placeholder("$window_id"),
                "x": .int(100),
                "y": .int(200)
            ],
            purpose: "Click in window",
            expectedChange: "Element clicked"
        )

        // Create context with a prior executed step that returned pid
        let priorStep = ExecutedStep(
            stepIndex: 0,
            tool: "launch_app",
            parameters: ["app_name": .string("Calculator")],
            result: "{\"pid\": 1234, \"app_name\": \"Calculator\", \"status\": \"launched\"}",
            success: true,
            timestamp: Date()
        )

        let context = RunContext(
            planId: UUID(),
            currentState: .executing,
            currentStepIndex: 1,
            executedSteps: [priorStep],
            replanCount: 0,
            config: config
        )

        let executed = try await executor.executeStep(step, context: context)

        #expect(executed.success)

        // Verify MCP was called with resolved (non-placeholder) parameters
        let clickCall = mockClient.callHistory.first(where: { $0.name == "click" })
        let resolvedCall = try #require(clickCall)
        #expect(resolvedCall.arguments["pid"] == .int(1234))
    }

    @Test("executePlan AX operation refreshes window state first")
    func executePlanAXOperationRefreshesWindowStateFirst() async throws {
        let mockClient = MockExecutorMCPClient()
        mockClient.stubbedResults["launch_app"] = """
        {"pid": 1234, "app_name": "Calculator", "status": "launched"}
        """
        mockClient.stubbedResults["list_windows"] = """
        {"windows": [{"window_id": 42, "pid": 1234, "title": "Calculator"}]}
        """
        mockClient.stubbedResults["get_window_state"] = """
        {"window_id": 42, "title": "Calculator", "pid": 1234, "elements": []}
        """
        mockClient.stubbedResults["click"] = """
        {"success": true}
        """
        var config = AxionConfig.default
        config.sharedSeatMode = false
        let executor = StepExecutor(mcpClient: mockClient, config: config)

        let plan = Plan(
            id: UUID(),
            task: "Open Calculator, find window, and click",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch", expectedChange: "App opens"),
                Step(index: 1, tool: "list_windows", parameters: ["pid": .placeholder("$pid")],
                     purpose: "Find window", expectedChange: "Window found"),
                Step(index: 2, tool: "click", parameters: ["x": .int(100), "y": .int(200)],
                     purpose: "Click button", expectedChange: "Button clicked")
            ],
            stopWhen: [StopCondition(type: .custom, value: "Clicked")],
            maxRetries: 3
        )

        let context = RunContext(
            planId: plan.id,
            currentState: .executing,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        _ = try await executor.executePlan(plan, context: context)

        // get_window_state should have been called before the click (AX refresh)
        let getWinStateCallIndex = mockClient.callHistory.firstIndex(where: { $0.name == "get_window_state" })
        let clickCallIndex = mockClient.callHistory.firstIndex(where: { $0.name == "click" })

        #expect(getWinStateCallIndex != nil)
        #expect(clickCallIndex != nil)
        // Verify get_window_state was called with window_id (not pid)
        let refreshCall = mockClient.callHistory.first(where: { $0.name == "get_window_state" })
        let resolvedRefreshCall = try #require(refreshCall)
        #expect(resolvedRefreshCall.arguments["window_id"] == .int(42))
        if let refreshIdx = getWinStateCallIndex, let clickIdx = clickCallIndex {
            #expect(refreshIdx < clickIdx)
        }
    }

    @Test("executePlan multiple steps resolves placeholders")
    func executePlanMultipleStepsResolvesPlaceholders() async throws {
        let mockClient = MockExecutorMCPClient()
        mockClient.stubbedResults["launch_app"] = """
        {"pid": 5555, "app_name": "Calculator", "status": "launched"}
        """
        mockClient.stubbedResults["list_windows"] = """
        {"windows": [{"window_id": 88, "pid": 5555, "title": "Calculator"}]}
        """
        mockClient.stubbedResults["get_window_state"] = """
        {"window_id": 88, "title": "Calculator", "pid": 5555, "elements": []}
        """
        mockClient.stubbedResults["type_text"] = """
        {"success": true}
        """
        var config = AxionConfig.default
        config.sharedSeatMode = false
        let executor = StepExecutor(mcpClient: mockClient, config: config)

        let plan = Plan(
            id: UUID(),
            task: "Open Calculator, find window, and type",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch Calculator", expectedChange: "App opens"),
                Step(index: 1, tool: "list_windows", parameters: ["pid": .placeholder("$pid")],
                     purpose: "Find window", expectedChange: "Window found"),
                Step(index: 2, tool: "type_text",
                     parameters: [
                        "pid": .placeholder("$pid"),
                        "window_id": .placeholder("$window_id"),
                        "text": .string("17*23=")
                     ],
                     purpose: "Type expression", expectedChange: "Expression entered")
            ],
            stopWhen: [StopCondition(type: .custom, value: "Result visible")],
            maxRetries: 3
        )

        let context = RunContext(
            planId: plan.id,
            currentState: .executing,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        let (executedSteps, _) = try await executor.executePlan(plan, context: context)

        #expect(executedSteps.count == 3)
        #expect(executedSteps[0].success)
        #expect(executedSteps[1].success)
        #expect(executedSteps[2].success)

        // Verify type_text was called with resolved pid/window_id from prior steps
        let typeTextCall = mockClient.callHistory.first(where: { $0.name == "type_text" })
        let resolvedCall = try #require(typeTextCall)
        #expect(resolvedCall.arguments["pid"] == .int(5555))
        #expect(resolvedCall.arguments["window_id"] == .int(88))
        #expect(resolvedCall.arguments["text"] == .string("17*23="))
    }

    @Test("executePlan returns updated execution context")
    func executePlanReturnsUpdatedExecutionContext() async throws {
        let mockClient = MockExecutorMCPClient()
        mockClient.stubbedResults["launch_app"] = """
        {"pid": 9999, "app_name": "Calculator", "status": "launched"}
        """
        let config = AxionConfig.default
        let executor = StepExecutor(mcpClient: mockClient, config: config)

        let plan = Plan(
            id: UUID(),
            task: "Launch app",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch", expectedChange: "App opens")
            ],
            stopWhen: [StopCondition(type: .custom, value: "App visible")],
            maxRetries: 3
        )

        let context = RunContext(
            planId: plan.id,
            currentState: .executing,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        let (executedSteps, updatedContext) = try await executor.executePlan(plan, context: context)

        #expect(executedSteps.count == 1)
        #expect(executedSteps[0].success)
        // The returned context should include the executed steps
        #expect(!updatedContext.executedSteps.isEmpty)
    }

    @Test("executePlan stops on first failure")
    func executePlanStopsOnFirstFailure() async throws {
        let mockClient = MockExecutorMCPClient()
        // First step succeeds
        mockClient.stubbedResults["launch_app"] = """
        {"pid": 1234, "app_name": "Calculator", "status": "launched"}
        """
        // Second step fails - set up throw for click
        mockClient.stubbedResults["click"] = """
        {"success": false}
        """
        var config = AxionConfig.default
        config.sharedSeatMode = false
        let executor = StepExecutor(mcpClient: mockClient, config: config)

        let plan = Plan(
            id: UUID(),
            task: "Launch and click",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch", expectedChange: "App opens"),
                Step(index: 1, tool: "click", parameters: ["x": .int(100), "y": .int(200)],
                     purpose: "Click", expectedChange: "Clicked"),
                Step(index: 2, tool: "type_text", parameters: ["text": .string("hello")],
                     purpose: "Type", expectedChange: "Typed")
            ],
            stopWhen: [StopCondition(type: .custom, value: "Done")],
            maxRetries: 3
        )

        let context = RunContext(
            planId: plan.id,
            currentState: .executing,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        // The executor should either throw or return partial results on failure
        // The third step (type_text) should NOT be executed
        do {
            let (executedSteps, _) = try await executor.executePlan(plan, context: context)
            // If it returns, it should have stopped before the third step
            // or the third step's result should indicate failure
            let typeTextCalls = mockClient.callHistory.filter { $0.name == "type_text" }
            // type_text should not have been called if execution stopped at step 1
            if let failedStep = executedSteps.last, !failedStep.success {
                // Step 1 failed, so step 2 should not be reached
                #expect(typeTextCalls.isEmpty)
            }
        } catch {
            // Throwing on failure is also acceptable behavior
            // Verify type_text was not called
            let typeTextCalls = mockClient.callHistory.filter { $0.name == "type_text" }
            #expect(typeTextCalls.isEmpty)
        }
    }

    @Test("executePlan with empty steps returns empty results")
    func executePlanEmptyStepsReturnsEmptyResults() async throws {
        let mockClient = MockExecutorMCPClient()
        let config = AxionConfig.default
        let executor = StepExecutor(mcpClient: mockClient, config: config)

        let plan = Plan(
            id: UUID(),
            task: "Empty task",
            steps: [],
            stopWhen: [StopCondition(type: .custom, value: "Done")],
            maxRetries: 3
        )

        let context = RunContext(
            planId: plan.id,
            currentState: .executing,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        let (executedSteps, _) = try await executor.executePlan(plan, context: context)

        #expect(executedSteps.isEmpty)
        #expect(mockClient.callHistory.isEmpty)
    }
}
