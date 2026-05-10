import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] 基础设施验证
// [P1] 行为验证

// MARK: - Mock MCP Client for StepExecutor Tests

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

// MARK: - StepExecutor ATDD Tests

/// ATDD 红色阶段测试 — 覆盖 Story 3-3 AC1 (MCP 工具调用), AC4 (AX 刷新), AC5 (失败处理)
/// 这些测试将在 StepExecutor 实现后通过 (TDD red-green-refactor)
final class StepExecutorTests: XCTestCase {

    // MARK: - P0 类型存在性

    func test_stepExecutor_typeExists() {
        let _ = StepExecutor.self
    }

    func test_stepExecutor_conformsToExecutorProtocol() {
        // StepExecutor must conform to ExecutorProtocol
        let mockClient = MockExecutorMCPClient()
        let config = AxionConfig.default
        let executor = StepExecutor(mcpClient: mockClient, config: config)
        let _ = executor as ExecutorProtocol
    }

    // MARK: - P0 单步执行成功 (AC1)

    func test_executeStep_launchApp_callsMCPAndReturnsSuccess() async throws {
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

        XCTAssertTrue(executed.success)
        XCTAssertEqual(executed.tool, "launch_app")
        XCTAssertEqual(executed.stepIndex, 0)
        XCTAssertTrue(mockClient.callHistory.contains(where: { $0.name == "launch_app" }))
    }

    // MARK: - P0 步骤执行失败处理 (AC5)

    func test_executeStep_mcpError_returnsFailedExecutedStep() async throws {
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
                XCTFail("Expected executionFailed or mcpError, got: \(error)")
            }
        }
    }

    // MARK: - P0 安全检查阻止 (AC6)

    func test_executeStep_safetyBlocked_returnsSafetyError() async throws {
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
            XCTAssertFalse(executed.success, "Foreground operation should be blocked in shared seat mode")
        } catch let error as AxionError {
            // Safety error expected
            if case .executionFailed = error {
                // Expected
            } else {
                XCTFail("Expected executionFailed for safety block, got: \(error)")
            }
        }

        // MCP client should NOT have been called for the blocked tool
        XCTAssertFalse(mockClient.callHistory.contains(where: { $0.name == "click" }),
                       "Blocked tool should not reach MCP")
    }

    // MARK: - P0 allow-foreground 放行 (AC7)

    func test_executeStep_allowForeground_executesClick() async throws {
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

        XCTAssertTrue(executed.success)
        XCTAssertTrue(mockClient.callHistory.contains(where: { $0.name == "click" }))
    }

    // MARK: - P0 占位符解析后执行 (AC2 + AC3 集成)

    func test_executeStep_placeholderResolved_beforeMCPCall() async throws {
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

        XCTAssertTrue(executed.success)

        // Verify MCP was called with resolved (non-placeholder) parameters
        let clickCall = mockClient.callHistory.first(where: { $0.name == "click" })
        XCTAssertNotNil(clickCall)
        XCTAssertEqual(clickCall?.arguments["pid"], .int(1234))
    }

    // MARK: - P1 AX 刷新前执行 (AC4)

    func test_executePlan_axOperation_refreshesWindowStateFirst() async throws {
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

        XCTAssertNotNil(getWinStateCallIndex, "get_window_state should be called before AX operations")
        XCTAssertNotNil(clickCallIndex, "click should be called")
        // Verify get_window_state was called with window_id (not pid)
        let refreshCall = mockClient.callHistory.first(where: { $0.name == "get_window_state" })
        XCTAssertNotNil(refreshCall)
        XCTAssertEqual(refreshCall?.arguments["window_id"], .int(42),
                       "get_window_state should be called with window_id from prior list_windows result")
        if let refreshIdx = getWinStateCallIndex, let clickIdx = clickCallIndex {
            XCTAssertLessThan(refreshIdx, clickIdx, "AX refresh should happen before click")
        }
    }

    // MARK: - P1 多步骤占位符链式解析

    func test_executePlan_multipleSteps_resolvesPlaceholders() async throws {
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

        XCTAssertEqual(executedSteps.count, 3)
        XCTAssertTrue(executedSteps[0].success)
        XCTAssertTrue(executedSteps[1].success)
        XCTAssertTrue(executedSteps[2].success)

        // Verify type_text was called with resolved pid/window_id from prior steps
        let typeTextCall = mockClient.callHistory.first(where: { $0.name == "type_text" })
        XCTAssertNotNil(typeTextCall)
        XCTAssertEqual(typeTextCall?.arguments["pid"], .int(5555))
        XCTAssertEqual(typeTextCall?.arguments["window_id"], .int(88))
        XCTAssertEqual(typeTextCall?.arguments["text"], .string("17*23="))
    }

    // MARK: - P1 executePlan 返回执行上下文

    func test_executePlan_returnsUpdatedExecutionContext() async throws {
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

        XCTAssertEqual(executedSteps.count, 1)
        XCTAssertTrue(executedSteps[0].success)
        // The returned context should include the executed steps
        XCTAssertFalse(updatedContext.executedSteps.isEmpty)
    }

    // MARK: - P1 executePlan 失败即停

    func test_executePlan_stopsOnFirstFailure() async throws {
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
                XCTAssertTrue(typeTextCalls.isEmpty, "Steps after failure should not execute")
            }
        } catch {
            // Throwing on failure is also acceptable behavior
            // Verify type_text was not called
            let typeTextCalls = mockClient.callHistory.filter { $0.name == "type_text" }
            XCTAssertTrue(typeTextCalls.isEmpty, "Steps after failure should not execute")
        }
    }

    // MARK: - P1 空步骤列表

    func test_executePlan_emptySteps_returnsEmptyResults() async throws {
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

        XCTAssertTrue(executedSteps.isEmpty)
        XCTAssertTrue(mockClient.callHistory.isEmpty)
    }
}
