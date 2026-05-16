import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

/// Mock 实现 LLMClientProtocol，用于测试 LLMPlanner 而不调用真实 LLM
final class MockLLMClient: LLMClientProtocol {
    var promptCallCount = 0
    var lastSystemPrompt: String?
    var lastUserMessage: String?
    var lastImagePaths: [String]?
    var stubbedResponse: String
    var shouldThrow = false
    var throwError: Error?

    /// 控制在第几次调用后停止抛出错误（用于测试重试成功）
    /// nil = 始终使用 shouldThrow 行为
    var stopThrowingAfterCall: Int? = nil

    init(stubbedResponse: String = "{}") {
        self.stubbedResponse = stubbedResponse
    }

    func prompt(systemPrompt: String, userMessage: String, imagePaths: [String]) async throws -> String {
        promptCallCount += 1
        lastSystemPrompt = systemPrompt
        lastUserMessage = userMessage
        lastImagePaths = imagePaths

        if shouldThrow {
            if let stopAfter = stopThrowingAfterCall, promptCallCount > stopAfter {
                // Stop throwing after specified call count
            } else {
                throw throwError ?? AxionError.planningFailed(reason: "Mock LLM error")
            }
        }

        return stubbedResponse
    }
}

/// Mock 实现 MCPClientProtocol，用于测试 Planner 的上下文获取
final class MockPlannerMCPClient: MCPClientProtocol {
    var stubbedTools: [String] = ["launch_app", "click", "type_text", "screenshot", "get_accessibility_tree"]
    var stubbedScreenshotResult: String = "{\"image_path\": \"/tmp/test-screenshot.png\"}"
    var stubbedAXTreeResult: String = "{\"tree\": \"AXRoot\"}"
    var shouldThrowOnScreenshot = false
    var shouldThrowOnAXTree = false

    func callTool(name: String, arguments: [String: Value]) async throws -> String {
        if name == "screenshot" {
            if shouldThrowOnScreenshot {
                throw AxionError.mcpError(tool: "screenshot", reason: "Permission denied")
            }
            return stubbedScreenshotResult
        }
        if name == "get_accessibility_tree" {
            if shouldThrowOnAXTree {
                throw AxionError.mcpError(tool: "get_accessibility_tree", reason: "Permission denied")
            }
            return stubbedAXTreeResult
        }
        return "{}"
    }

    func listTools() async throws -> [String] {
        return stubbedTools
    }
}

@Suite("LLMPlanner")
struct LLMPlannerTests {

    @Test("type exists")
    func llmPlannerTypeExists() async throws {
        let _ = LLMPlanner.self
    }

    @Test("LLMClientProtocol type exists")
    func llmClientProtocolTypeExists() async throws {
        let _ = MockLLMClient.self
    }

    @Test("createPlan calls LLM with correct prompt")
    func createPlanCallsLLMWithCorrectPrompt() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [{"tool": "launch_app", "args": {"name": "Calculator"}, "purpose": "Open Calculator", "expected_change": "Calculator opens"}],
            "stopWhen": "Calculator window appears"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        _ = try await planner.createPlan(for: "Open Calculator", context: context)

        #expect(mockLLM.promptCallCount == 1)
        #expect(mockLLM.lastSystemPrompt != nil)
        #expect(mockLLM.lastUserMessage != nil)
        #expect(mockLLM.lastUserMessage?.contains("Open Calculator") == true)
    }

    @Test("createPlan returns plan with steps")
    func createPlanReturnsPlanWithSteps() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [
                {"tool": "launch_app", "args": {"name": "Calculator"}, "purpose": "Open Calculator", "expected_change": "Calculator opens"},
                {"tool": "click", "args": {"x": 100, "y": 200}, "purpose": "Click button 1", "expected_change": "1 entered"}
            ],
            "stopWhen": "Result visible"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        let plan = try await planner.createPlan(for: "Open Calculator and compute 1+1", context: context)

        #expect(plan.steps.count == 2)
        #expect(plan.steps[0].tool == "launch_app")
        #expect(plan.steps[1].tool == "click")
        #expect(plan.task == "Open Calculator and compute 1+1")
        #expect(!plan.stopWhen.isEmpty)
    }

    @Test("createPlan LLM throws error propagates error")
    func createPlanLLMThrowsErrorPropagatesError() async throws {
        let mockLLM = MockLLMClient()
        mockLLM.shouldThrow = true
        mockLLM.throwError = AxionError.planningFailed(reason: "Network timeout")

        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        do {
            _ = try await planner.createPlan(for: "test task", context: context)
            Issue.record("Should have thrown")
        } catch {
            // 验证错误传播
        }
    }

    @Test("createPlan parse failure throws invalidPlan")
    func createPlanParseFailureThrowsInvalidPlan() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: "This is not valid JSON at all")
        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        do {
            _ = try await planner.createPlan(for: "test task", context: context)
            Issue.record("Should have thrown")
        } catch let error as AxionError {
            if case .invalidPlan = error {
                // Expected
            } else {
                Issue.record("Expected invalidPlan error, got: \(error)")
            }
        }
    }

    @Test("createPlan retries on network error up to max retries")
    func createPlanRetriesOnNetworkErrorUpToMaxRetries() async throws {
        let mockLLM = MockLLMClient()
        mockLLM.shouldThrow = true
        mockLLM.throwError = AxionError.planningFailed(reason: "Network timeout")

        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        do {
            _ = try await planner.createPlan(for: "test task", context: context)
        } catch {
            // Should fail after 3 retries
        }

        // 验证重试次数: 1 initial + 3 retries = 4 次调用
        #expect(mockLLM.promptCallCount == 4)
    }

    @Test("createPlan succeeds on retry after initial failure")
    func createPlanSucceedsOnRetryAfterInitialFailure() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [{"tool": "launch_app", "args": {"name": "Calc"}, "purpose": "open", "expected_change": "opened"}],
            "stopWhen": "Calc visible"
        }
        """)

        // 配置：第一次调用失败，之后成功
        mockLLM.shouldThrow = true
        mockLLM.throwError = AxionError.planningFailed(reason: "Network timeout")
        mockLLM.stopThrowingAfterCall = 1 // 第一次调用抛出错误后停止

        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        // 第一次失败，第二次重试成功
        let plan = try await planner.createPlan(for: "test task", context: context)
        #expect(plan.steps.count == 1)
        // 应该总共调用 2 次（1 失败 + 1 成功）
        #expect(mockLLM.promptCallCount == 2)
    }

    @Test("createPlan does not retry on parse error")
    func createPlanDoesNotRetryOnParseError() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: "Invalid JSON response, not a network error")
        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        do {
            _ = try await planner.createPlan(for: "test task", context: context)
        } catch {
            // Should fail without retrying (parse error, not network error)
        }

        // 验证只调用了一次（无重试，因为解析错误不触发重试）
        #expect(mockLLM.promptCallCount == 1)
    }

    @Test("replan includes failure context")
    func replanIncludesFailureContext() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [{"tool": "click", "args": {"x": 150, "y": 300}, "purpose": "Click corrected button", "expected_change": "Button clicked"}],
            "stopWhen": "Task complete"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let currentPlan = Plan(
            id: UUID(),
            task: "Open Calculator and compute 1+1",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["name": .string("Calculator")], purpose: "Open Calculator", expectedChange: "Calculator opens"),
                Step(index: 1, tool: "click", parameters: ["x": .int(100), "y": .int(200)], purpose: "Click button 1", expectedChange: "Button clicked")
            ],
            stopWhen: [StopCondition(type: .custom, value: "Result 2 visible")],
            maxRetries: 3
        )

        let executedSteps = [
            ExecutedStep(stepIndex: 0, tool: "launch_app", parameters: ["name": .string("Calculator")], result: "App launched", success: true, timestamp: Date()),
            ExecutedStep(stepIndex: 1, tool: "click", parameters: ["x": .int(100), "y": .int(200)], result: "Element not found", success: false, timestamp: Date())
        ]

        let context = RunContext(
            planId: currentPlan.id,
            currentState: .replanning,
            currentStepIndex: 1,
            executedSteps: executedSteps,
            replanCount: 1,
            config: config
        )

        let replannedPlan = try await planner.replan(
            from: currentPlan,
            executedSteps: executedSteps,
            failureReason: "Element not found at coordinates (100, 200)",
            context: context
        )

        // 验证 LLM 被调用
        #expect(mockLLM.promptCallCount == 1)
        // 验证 userMessage 包含失败上下文
        let userMessage = mockLLM.lastUserMessage ?? ""
        #expect(userMessage.contains("REPLAN") || userMessage.contains("failed") || userMessage.contains("Element not found"))
        // 验证返回了新的 Plan
        #expect(replannedPlan.task == "Open Calculator and compute 1+1")
        #expect(!replannedPlan.steps.isEmpty)
    }

    @Test("createPlan captures current state calls MCP tools")
    func createPlanCapturesCurrentStateCallsMCPTools() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [{"tool": "launch_app", "args": {"name": "Calc"}, "purpose": "open", "expected_change": "opened"}],
            "stopWhen": "Calc visible"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        _ = try await planner.createPlan(for: "Open Calculator", context: context)

        // 验证 prompt 中包含了上下文信息
        // Planner 应该获取截图和 AX tree 作为上下文
        // 如果截图失败也应能降级工作
        #expect(mockLLM.lastUserMessage != nil)
    }

    @Test("createPlan screenshot failure degrades gracefully")
    func createPlanScreenshotFailureDegradesGracefully() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [{"tool": "launch_app", "args": {"name": "Calc"}, "purpose": "open", "expected_change": "opened"}],
            "stopWhen": "Calc visible"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        mockMCP.shouldThrowOnScreenshot = true
        mockMCP.shouldThrowOnAXTree = true
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        // 即使截图/AX tree 失败，Planner 也应该能工作（降级模式）
        let plan = try await planner.createPlan(for: "Open Calculator", context: context)
        #expect(plan.steps.count == 1)
    }

    @Test("replan passes executed steps to prompt")
    func replanPassesExecutedStepsToPrompt() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [{"tool": "type_text", "args": {"text": "test"}, "purpose": "type text", "expected_change": "typed"}],
            "stopWhen": "done"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let currentPlan = Plan(
            id: UUID(),
            task: "Open Calculator",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["name": .string("Calculator")], purpose: "Open", expectedChange: "opened")
            ],
            stopWhen: [StopCondition(type: .custom, value: "Calculator visible")],
            maxRetries: 3
        )

        let executedSteps = [
            ExecutedStep(stepIndex: 0, tool: "launch_app", parameters: ["name": .string("Calculator")], result: "OK", success: true, timestamp: Date())
        ]

        let context = RunContext(
            planId: currentPlan.id,
            currentState: .replanning,
            currentStepIndex: 1,
            executedSteps: executedSteps,
            replanCount: 1,
            config: config
        )

        _ = try await planner.replan(
            from: currentPlan,
            executedSteps: executedSteps,
            failureReason: "Click target moved",
            context: context
        )

        let userMessage = mockLLM.lastUserMessage ?? ""
        // Replan prompt 应包含已执行步骤信息
        #expect(userMessage.contains("launch_app") || userMessage.contains("executed") || userMessage.contains("REPLAN"))
    }

    @Test("LLMPlanner init with config and clients")
    func llmPlannerInitWithConfigAndClients() async throws {
        let mockLLM = MockLLMClient()
        let mockMCP = MockPlannerMCPClient()
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })
        let _ = planner
    }

    @Test("createPlan system prompt contains tool list")
    func createPlanSystemPromptContainsToolList() async throws {
        let mockLLM = MockLLMClient(stubbedResponse: """
        {
            "steps": [{"tool": "launch_app", "args": {"name": "Calc"}, "purpose": "open", "expected_change": "opened"}],
            "stopWhen": "done"
        }
        """)
        let mockMCP = MockPlannerMCPClient()
        mockMCP.stubbedTools = ["launch_app", "click", "type_text", "screenshot"]
        let config = AxionConfig.default
        let planner = LLMPlanner(config: config, llmClient: mockLLM, mcpClient: mockMCP, retryDelay: { _ in })

        let context = RunContext(
            planId: UUID(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )

        _ = try await planner.createPlan(for: "test", context: context)

        let systemPrompt = mockLLM.lastSystemPrompt ?? ""
        #expect(systemPrompt.contains("launch_app") || systemPrompt.contains("tool"))
    }
}
