import XCTest
@testable import AxionCLI
@testable import AxionCore

/// Integration tests for Story 3-6: RunEngine state machine.
///
/// Tests the full plan -> execute -> verify -> replan loop with real Helper process
/// and real MCP calls. Only the Planner and LLM (for verification) are mocked.
///
/// Prerequisites:
/// - AxionHelper.app built at .build/AxionHelper.app
/// - macOS Accessibility permissions granted to Terminal/iTerm
/// - Screen Recording permission granted (for screenshots)
/// - Run with: AXION_HELPER_PATH="$(pwd)/.build/AxionHelper.app/Contents/MacOS/AxionHelper" swift test --filter "AxionCLIIntegrationTests.RunEngineIntegrationTests"
final class RunEngineIntegrationTests: XCTestCase {

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

    // MARK: - Properties

    private var manager: HelperProcessManager?
    private var mcpClient: RealMCPAdapter?
    private var tempDir: URL?

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()

        let mgr = HelperProcessManager()
        do {
            try await mgr.start()
        } catch {
            XCTFail("Failed to start Helper process: \(error). " +
                    "Ensure AxionHelper.app is built and AX permissions are granted.")
            return
        }

        let running = await mgr.isRunning()
        XCTAssertTrue(running, "Helper should be running after start()")

        self.manager = mgr
        self.mcpClient = RealMCPAdapter(manager: mgr)

        self.tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunEngineIntegTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir!, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let manager {
            await manager.stop()
        }
        self.manager = nil
        self.mcpClient = nil

        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        self.tempDir = nil

        try await super.tearDown()
    }

    // MARK: - AC1, AC2: Happy path — plan -> execute -> verify -> done

    func test_real_happyPath_launchAndVerifyCalculator() async throws {
        guard let mcpClient else { return }

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

        // AC1: State machine goes through planning -> executing -> verifying
        // AC2: Final state is .done
        XCTAssertEqual(result.currentState, .done,
            "Happy path should end in .done state")

        // Planner was called once
        XCTAssertEqual(planner.createPlanCallCount, 1)

        // Output contains run info
        let combined = capturedOutput.joined(separator: "\n")
        XCTAssertTrue(combined.contains("[axion]"),
            "All output should have [axion] prefix")

        // Output shows plan, execution, verification, and summary
        XCTAssertTrue(combined.contains("步骤"), "Should show step progress")
        XCTAssertTrue(combined.contains("验证"), "Should show verification result")
        XCTAssertTrue(combined.contains("完成"), "Should show completion summary")

        // Cleanup: quit Calculator
        cleanupCalculator()
    }

    // MARK: - AC8: Dryrun mode — plan only, no execution

    func test_real_dryrunMode_plansWithoutExecution() async throws {
        guard let mcpClient else { return }

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

        // Dryrun should reach .done without executing
        XCTAssertEqual(result.currentState, .done)

        // Planner was called (generates the plan)
        XCTAssertEqual(planner.createPlanCallCount, 1)

        // Output shows plan
        let combined = capturedOutput.joined(separator: "\n")
        XCTAssertTrue(combined.contains("[axion]"))
        XCTAssertTrue(combined.contains("规划完成"), "Dryrun should display the plan")

        // Dryrun should NOT show step execution results
        XCTAssertFalse(combined.contains("ok"),
            "Dryrun should not show step execution results")
    }

    // MARK: - AC12: Step failure triggers replan

    func test_real_stepFailureTriggersReplan() async throws {
        guard let mcpClient else { return }

        // Plan 1: use click (foreground op) in shared-seat mode — safety check will fail
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

        // Plan 2 (replan): launch Calculator (will succeed)
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

        // Should reach .done after replan
        XCTAssertEqual(result.currentState, .done,
            "Should reach .done after replan with valid app")

        // Replan was called once
        XCTAssertEqual(planner.replanCallCount, 1,
            "Replan should be called exactly once")

        // Output contains replan info
        let combined = capturedOutput.joined(separator: "\n")
        XCTAssertTrue(combined.contains("重规划"),
            "Should show replan message in output")

        cleanupCalculator()
    }

    // MARK: - AC3, AC4: Blocked verification triggers replan

    func test_real_blockedVerificationTriggersReplan() async throws {
        guard let mcpClient else { return }

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

        // Verifier that returns blocked first, then done
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

        // Should reach .done after replan
        XCTAssertEqual(result.currentState, .done,
            "Should reach .done after blocked -> replan -> done")

        // Replan was called
        XCTAssertEqual(planner.replanCallCount, 1)

        // Output contains replan and verification messages
        let combined = capturedOutput.joined(separator: "\n")
        XCTAssertTrue(combined.contains("重规划"),
            "Should show replan message")

        cleanupCalculator()
    }

    // MARK: - Output recording through RunEngine

    func test_real_outputRecording() async throws {
        guard let mcpClient else { return }

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

        // === Verify TerminalOutput ===
        let combined = capturedOutput.joined(separator: "\n")

        // Every non-empty line has [axion] prefix
        for line in capturedOutput where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            XCTAssertTrue(line.contains("[axion]"),
                "Output line missing [axion] prefix: '\(line)'")
        }

        // Run start info
        XCTAssertTrue(combined.contains("运行"), "Should show run start info")

        // Plan display
        XCTAssertTrue(combined.contains("规划完成"), "Should show plan info")

        // Step execution
        XCTAssertTrue(combined.contains("步骤"), "Should show step execution")

        // Verification result
        XCTAssertTrue(combined.contains("验证"), "Should show verification")

        // Summary
        XCTAssertTrue(combined.contains("完成"), "Should show completion summary")

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

/// A verifier wrapper that returns .blocked on the first call, then .done on subsequent calls.
/// Uses real TaskVerifier with different mock LLMs to test the replan path.
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
            var verifier = TaskVerifier(mcpClient: mcpClient, llmClient: blockedLLM, config: config)
            return try await verifier.verify(plan: plan, executedSteps: executedSteps, context: context)
        } else {
            var verifier = TaskVerifier(mcpClient: mcpClient, llmClient: doneLLM, config: config)
            return try await verifier.verify(plan: plan, executedSteps: executedSteps, context: context)
        }
    }
}
