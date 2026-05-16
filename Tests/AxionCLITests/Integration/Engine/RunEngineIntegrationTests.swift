import Foundation
import Testing
@testable import AxionCLI
@testable import AxionCore

@Suite("RunEngine Integration")
struct RunEngineIntegrationTests {

    // MARK: - Helper -> MCPClientProtocol Adapter

    struct RealMCPAdapter: MCPClientProtocol {
        private let manager: HelperProcessManager

        init(manager: HelperProcessManager) {
            self.manager = manager
        }

        func callTool(name: String, arguments: [String: AxionCore.Value]) async throws -> String {
            return try await manager.callTool(name: name, arguments: arguments)
        }

        func listTools() async throws -> [String] {
            return try await manager.listTools()
        }
    }

    // MARK: - Mock Planner

    final class IntegrationMockPlanner: PlannerProtocol {
        var plans: [Plan]
        var planIndex = 0
        var createPlanCallCount = 0
        var replanCallCount = 0
        var lastReplanReason: String?

        init(plans: [Plan]) {
            self.plans = plans
        }

        func createPlan(for task: String, context: RunContext) async throws -> Plan {
            createPlanCallCount += 1
            let plan = plans[min(planIndex, plans.count - 1)]
            planIndex += 1
            return plan
        }

        func replan(from currentPlan: Plan, executedSteps: [ExecutedStep], failureReason: String, context: RunContext) async throws -> Plan {
            replanCallCount += 1
            lastReplanReason = failureReason
            let plan = plans[min(planIndex, plans.count - 1)]
            planIndex += 1
            return plan
        }
    }

    // MARK: - Mock LLM Client

    struct IntegrationMockLLM: LLMClientProtocol {
        let promptResult: String
        func prompt(systemPrompt: String, userMessage: String, imagePaths: [String]) async throws -> String {
            return promptResult
        }
    }

    // MARK: - Setup Helper

    private func setUpMCPClient() async throws -> (HelperProcessManager, RealMCPAdapter, URL) {
        let mgr = HelperProcessManager()
        do {
            try await mgr.start()
        } catch {
            throw NSError(domain: "AxionHelper not available", code: 1)
        }

        let running = await mgr.isRunning()
        #expect(running, "Helper should be running after start()")

        let mcpClient = RealMCPAdapter(manager: mgr)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunEngineIntegTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        return (mgr, mcpClient, tempDir)
    }

    // MARK: - AC1, AC2: Happy path — plan -> execute -> verify -> done

    @Test("real happy path launch and verify Calculator")
    func realHappyPathLaunchAndVerifyCalculator() async throws {
        let (manager, mcpClient, tempDir) = try await setUpMCPClient()
        defer {
            Task { await manager.stop() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let plan = Plan(
            id: UUID(), task: "Launch Calculator",
            steps: [
                Step(index: 0, tool: ToolNames.launchApp,
                     parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch Calculator", expectedChange: "App opens")
            ],
            stopWhen: [StopCondition(type: .textAppears, value: "Calculator")],
            maxRetries: 3
        )

        let planner = IntegrationMockPlanner(plans: [plan])
        let executor = StepExecutor(mcpClient: mcpClient, config: .default)
        let llm = IntegrationMockLLM(promptResult: """
        {"status": "done", "reason": "Calculator is running and visible"}
        """)
        let verifier = TaskVerifier(mcpClient: mcpClient, llmClient: llm, config: .default)

        var capturedOutput: [String] = []
        let output = TerminalOutput { capturedOutput.append($0) }

        let engine = RunEngine(
            planner: planner,
            executor: executor,
            verifier: verifier,
            output: output
        )

        let result = await engine.run(
            task: "Launch Calculator",
            config: .default,
            options: RunEngineOptions()
        )

        #expect(result.currentState == .done,
                "Happy path should end in .done state")

        #expect(planner.createPlanCallCount == 1)

        let combined = capturedOutput.joined(separator: "\n")
        #expect(combined.contains("[axion]"),
                "All output should have [axion] prefix")
        #expect(combined.contains("步骤"), "Should show step progress")
        #expect(combined.contains("验证"), "Should show verification result")
        #expect(combined.contains("完成"), "Should show completion summary")

        cleanupCalculator()
    }

    // MARK: - AC8: Dryrun mode — plan only, no execution

    @Test("real dryrun mode plans without execution")
    func realDryrunModePlansWithoutExecution() async throws {
        let (manager, mcpClient, tempDir) = try await setUpMCPClient()
        defer {
            Task { await manager.stop() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let plan = Plan(
            id: UUID(), task: "Launch Calculator",
            steps: [
                Step(index: 0, tool: ToolNames.launchApp,
                     parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch Calculator", expectedChange: "App opens")
            ],
            stopWhen: [],
            maxRetries: 3
        )

        let planner = IntegrationMockPlanner(plans: [plan])
        let executor = StepExecutor(mcpClient: mcpClient, config: .default)
        let verifier = TaskVerifier(
            mcpClient: mcpClient,
            llmClient: IntegrationMockLLM(promptResult: "{\"status\": \"done\"}"),
            config: .default
        )

        var capturedOutput: [String] = []
        let output = TerminalOutput { capturedOutput.append($0) }

        let engine = RunEngine(
            planner: planner,
            executor: executor,
            verifier: verifier,
            output: output
        )

        var options = RunEngineOptions()
        options.dryrun = true

        let result = await engine.run(
            task: "Launch Calculator",
            config: .default,
            options: options
        )

        #expect(result.currentState == .done)
        #expect(planner.createPlanCallCount == 1)

        let combined = capturedOutput.joined(separator: "\n")
        #expect(combined.contains("[axion]"))
        #expect(combined.contains("规划完成"), "Dryrun should display the plan")
        #expect(!combined.contains("ok"),
                "Dryrun should not show step execution results")
    }

    // MARK: - AC12: Step failure triggers replan

    @Test("real step failure triggers replan")
    func realStepFailureTriggersReplan() async throws {
        let (manager, mcpClient, tempDir) = try await setUpMCPClient()
        defer {
            Task { await manager.stop() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let plan1 = Plan(
            id: UUID(), task: "Click a button",
            steps: [
                Step(index: 0, tool: "click",
                     parameters: ["x": .int(100), "y": .int(200)],
                     purpose: "Click button", expectedChange: "Button clicked")
            ],
            stopWhen: [],
            maxRetries: 3
        )

        let plan2 = Plan(
            id: UUID(), task: "Open Calculator instead",
            steps: [
                Step(index: 0, tool: ToolNames.launchApp,
                     parameters: ["app_name": .string("Calculator")],
                     purpose: "Open Calculator", expectedChange: "Calculator opens")
            ],
            stopWhen: [StopCondition(type: .textAppears, value: "Calculator")],
            maxRetries: 3
        )

        let planner = IntegrationMockPlanner(plans: [plan1, plan2])
        let executor = StepExecutor(mcpClient: mcpClient, config: .default)
        let llm = IntegrationMockLLM(promptResult: """
        {"status": "done", "reason": "Calculator is running"}
        """)
        let verifier = TaskVerifier(mcpClient: mcpClient, llmClient: llm, config: .default)

        var capturedOutput: [String] = []
        let output = TerminalOutput { capturedOutput.append($0) }

        let engine = RunEngine(
            planner: planner,
            executor: executor,
            verifier: verifier,
            output: output
        )

        var config = AxionConfig.default
        config.maxReplanRetries = 3

        let result = await engine.run(
            task: "Click a button",
            config: config,
            options: RunEngineOptions()
        )

        #expect(result.currentState == .done,
                "Should reach .done after replan with valid app")
        #expect(planner.replanCallCount == 1,
                "Replan should be called exactly once")

        let combined = capturedOutput.joined(separator: "\n")
        #expect(combined.contains("重规划"),
                "Should show replan message in output")

        cleanupCalculator()
    }

    // MARK: - AC3, AC4: Blocked verification triggers replan

    @Test("real blocked verification triggers replan")
    func realBlockedVerificationTriggersReplan() async throws {
        let (manager, mcpClient, tempDir) = try await setUpMCPClient()
        defer {
            Task { await manager.stop() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let plan1 = Plan(
            id: UUID(), task: "Launch Calculator",
            steps: [
                Step(index: 0, tool: ToolNames.launchApp,
                     parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch Calculator", expectedChange: "App opens")
            ],
            stopWhen: [StopCondition(type: .textAppears, value: "NonExistentText")],
            maxRetries: 3
        )

        let plan2 = Plan(
            id: UUID(), task: "Launch Calculator (retry with relaxed condition)",
            steps: [
                Step(index: 0, tool: ToolNames.launchApp,
                     parameters: ["app_name": .string("Calculator")],
                     purpose: "Relaunch Calculator", expectedChange: "Calculator visible")
            ],
            stopWhen: [StopCondition(type: .textAppears, value: "Calculator")],
            maxRetries: 3
        )

        let planner = IntegrationMockPlanner(plans: [plan1, plan2])
        let executor = StepExecutor(mcpClient: mcpClient, config: .default)

        let verifier = BlockedThenDoneVerifier(
            mcpClient: mcpClient,
            blockedLLM: IntegrationMockLLM(promptResult: """
            {"status": "blocked", "reason": "Stop condition not met"}
            """),
            doneLLM: IntegrationMockLLM(promptResult: """
            {"status": "done", "reason": "Calculator is visible"}
            """),
            config: .default
        )

        var capturedOutput: [String] = []
        let output = TerminalOutput { capturedOutput.append($0) }

        let engine = RunEngine(
            planner: planner,
            executor: executor,
            verifier: verifier,
            output: output
        )

        var config = AxionConfig.default
        config.maxReplanRetries = 3

        let result = await engine.run(
            task: "Launch Calculator with strict stop condition",
            config: config,
            options: RunEngineOptions()
        )

        #expect(result.currentState == .done,
                "Should reach .done after blocked -> replan -> done")
        #expect(planner.replanCallCount == 1)

        let combined = capturedOutput.joined(separator: "\n")
        #expect(combined.contains("重规划"),
                "Should show replan message")

        cleanupCalculator()
    }

    // MARK: - Output recording through RunEngine

    @Test("real output recording")
    func realOutputRecording() async throws {
        let (manager, mcpClient, tempDir) = try await setUpMCPClient()
        defer {
            Task { await manager.stop() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let plan = Plan(
            id: UUID(), task: "Launch Calculator",
            steps: [
                Step(index: 0, tool: ToolNames.launchApp,
                     parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch Calculator", expectedChange: "App opens")
            ],
            stopWhen: [StopCondition(type: .textAppears, value: "Calculator")],
            maxRetries: 3
        )

        let planner = IntegrationMockPlanner(plans: [plan])
        let executor = StepExecutor(mcpClient: mcpClient, config: .default)
        let llm = IntegrationMockLLM(promptResult: """
        {"status": "done", "reason": "Calculator running"}
        """)
        let verifier = TaskVerifier(mcpClient: mcpClient, llmClient: llm, config: .default)

        var capturedOutput: [String] = []
        let output = TerminalOutput { capturedOutput.append($0) }

        let engine = RunEngine(
            planner: planner,
            executor: executor,
            verifier: verifier,
            output: output
        )

        _ = await engine.run(
            task: "Launch Calculator",
            config: .default,
            options: RunEngineOptions()
        )

        let combined = capturedOutput.joined(separator: "\n")

        for line in capturedOutput where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            #expect(line.contains("[axion]"),
                    "Output line missing [axion] prefix: '\(line)'")
        }

        #expect(combined.contains("运行"), "Should show run start info")
        #expect(combined.contains("规划完成"), "Should show plan info")
        #expect(combined.contains("步骤"), "Should show step execution")
        #expect(combined.contains("验证"), "Should show verification")
        #expect(combined.contains("完成"), "Should show completion summary")

        cleanupCalculator()
    }

    // MARK: - Helpers

    private func cleanupCalculator() {
        _ = try? Process.run(
            URL(fileURLWithPath: "/usr/bin/killall"),
            arguments: ["Calculator"]
        )
    }
}

// MARK: - BlockedThenDoneVerifier

private final class BlockedThenDoneVerifier: VerifierProtocol {
    private let mcpClient: MCPClientProtocol
    private let blockedLLM: LLMClientProtocol
    private let doneLLM: LLMClientProtocol
    private let config: AxionConfig
    private var callCount = 0

    init(mcpClient: MCPClientProtocol, blockedLLM: LLMClientProtocol, doneLLM: LLMClientProtocol, config: AxionConfig) {
        self.mcpClient = mcpClient
        self.blockedLLM = blockedLLM
        self.doneLLM = doneLLM
        self.config = config
    }

    func verify(plan: Plan, executedSteps: [ExecutedStep], context: RunContext) async throws -> VerificationResult {
        callCount += 1
        if callCount == 1 {
            let verifier = TaskVerifier(mcpClient: mcpClient, llmClient: blockedLLM, config: config)
            return try await verifier.verify(plan: plan, executedSteps: executedSteps, context: context)
        } else {
            let verifier = TaskVerifier(mcpClient: mcpClient, llmClient: doneLLM, config: config)
            return try await verifier.verify(plan: plan, executedSteps: executedSteps, context: context)
        }
    }
}
