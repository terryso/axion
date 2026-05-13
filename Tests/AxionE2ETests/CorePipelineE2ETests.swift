import Foundation
import XCTest

import AxionCore
import OpenAgentSDK
@testable import AxionCLI

// MARK: - Pure Logic Tests (no Helper required)

/// Tests for core pipeline components that don't require a real Helper process.
/// These run in any CI environment.
///
/// Covers: Stories 3.2 (prompt loading), 3.4 (stop conditions), 3.6 (safety, run engine).
final class CorePipelineLogicE2ETests: XCTestCase {

    // MARK: - Story 3.2: Prompt Management

    /// PromptBuilder loads planner-system.md and substitutes {{tools}} and {{max_steps}}.
    func test_promptLoadingWithVariableInjection() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let systemPrompt = try PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: ToolNames.allToolNames),
                "max_steps": "25",
            ],
            fromDirectory: promptDir
        )

        XCTAssertFalse(systemPrompt.contains("{{tools}}"), "{{tools}} should be replaced")
        XCTAssertFalse(systemPrompt.contains("{{max_steps}}"), "{{max_steps}} should be replaced")
        XCTAssertTrue(systemPrompt.contains("launch_app"), "Prompt should contain tool descriptions")
        XCTAssertTrue(systemPrompt.contains("25"), "Prompt should contain the max_steps value")
        XCTAssertTrue(systemPrompt.contains("Axion"), "Prompt should contain agent identity")
    }

    /// PromptBuilder throws when prompt file doesn't exist.
    func test_promptLoadingThrowsOnMissingFile() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        XCTAssertThrowsError(
            try PromptBuilder.load(name: "nonexistent", variables: [:], fromDirectory: promptDir)
        )
    }

    // MARK: - Story 3.4: Stop Condition Evaluation

    /// Tests maxStepsReached stop condition.
    func test_maxStepsStopCondition() {
        let evaluator = StopConditionEvaluator()

        let executedSteps = (0..<5).map { i in
            ExecutedStep(stepIndex: i, tool: "click", parameters: [:], result: "ok", success: true, timestamp: Date())
        }

        let condition = StopCondition(type: .maxStepsReached, value: nil)
        let result = evaluator.evaluate(
            stopConditions: [condition],
            screenshot: nil,
            axTree: nil,
            executedSteps: executedSteps,
            maxSteps: 5
        )
        XCTAssertEqual(result, .satisfied, "maxStepsReached should be satisfied when steps == maxSteps")

        let underLimit = evaluator.evaluate(
            stopConditions: [condition],
            screenshot: nil,
            axTree: nil,
            executedSteps: executedSteps,
            maxSteps: 10
        )
        XCTAssertEqual(underLimit, .notSatisfied, "maxStepsReached should NOT be satisfied when steps < maxSteps")
    }

    /// Tests empty stop conditions → trivially satisfied.
    func test_emptyStopConditions() {
        let evaluator = StopConditionEvaluator()
        let result = evaluator.evaluate(
            stopConditions: [],
            screenshot: nil,
            axTree: nil,
            executedSteps: [],
            maxSteps: 20
        )
        XCTAssertEqual(result, .satisfied, "Empty stop conditions should be trivially satisfied")
    }

    // MARK: - Story 3.6: Safety Checker

    /// SafetyChecker blocks foreground tools in shared-seat mode.
    func test_safetyCheckerBlocksForegroundInSharedSeatMode() {
        let checker = SafetyChecker()

        let foregroundTools = ["click", "type_text", "press_key", "hotkey", "double_click", "right_click", "scroll", "drag"]
        for tool in foregroundTools {
            let result = checker.check(tool: tool, sharedSeatMode: true)
            XCTAssertFalse(result.allowed, "Tool '\(tool)' should be blocked in shared-seat mode")
            XCTAssertTrue(result.errorMessage.contains("foreground"), "Error should mention foreground for \(tool)")
        }
    }

    /// SafetyChecker allows foreground tools when not in shared-seat mode.
    func test_safetyCheckerAllowsForegroundInNormalMode() {
        let checker = SafetyChecker()

        let allTools = ToolNames.allToolNames
        for tool in allTools {
            let result = checker.check(tool: tool, sharedSeatMode: false)
            XCTAssertTrue(result.allowed, "Tool '\(tool)' should be allowed in normal mode")
        }
    }

    /// SafetyChecker allows read-only and background-safe tools in shared-seat mode.
    func test_safetyCheckerAllowsReadOnlyInBackgroundMode() {
        let checker = SafetyChecker()

        let safeTools = ["list_apps", "list_windows", "screenshot", "get_accessibility_tree",
                         "launch_app", "open_url", "get_window_state", "quit_app"]
        for tool in safeTools {
            let result = checker.check(tool: tool, sharedSeatMode: true)
            XCTAssertTrue(result.allowed, "Tool '\(tool)' should be allowed in shared-seat mode")
        }
    }

    // MARK: - Story 3.6: Run Engine State Machine

    /// RunEngine state machine: replan loop succeeds on second attempt.
    func test_runEngineReplanLoop() async throws {
        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()

        planner.plans = [
            Plan(id: UUID(), task: "test", steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")], purpose: "launch", expectedChange: "app running")
            ], stopWhen: [], maxRetries: 3),
            Plan(id: UUID(), task: "test", steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")], purpose: "launch", expectedChange: "app running")
            ], stopWhen: [], maxRetries: 3)
        ]
        executor.results = [
            [ExecutedStep(stepIndex: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")], result: #"{"pid":12345}"#, success: true, timestamp: Date())]
        ]
        verifier.results = [
            .blocked(reason: "App not visible yet", screenshotBase64: nil, axTreeSnapshot: nil),
            .done(reason: "Task complete", screenshotBase64: nil, axTreeSnapshot: nil)
        ]

        var config = AxionConfig.default
        config.maxReplanRetries = 3
        config.maxBatches = 5

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        let context = await engine.run(task: "test", config: config, options: RunEngineOptions())

        XCTAssertEqual(context.currentState, .done, "Engine should reach .done after replan")
        XCTAssertEqual(output.replanCalls, 1, "Should have replanned once")
    }

    /// RunEngine terminates when max replan retries exceeded.
    func test_runEngineMaxReplanExceeded() async throws {
        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()

        planner.plans = [
            Plan(id: UUID(), task: "test", steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("X")], purpose: "launch", expectedChange: "app")
            ], stopWhen: [], maxRetries: 3)
        ]
        executor.results = [
            [ExecutedStep(stepIndex: 0, tool: "launch_app", parameters: [:], result: #"{"pid":1}"#, success: true, timestamp: Date())]
        ]
        verifier.results = [
            .blocked(reason: "stuck", screenshotBase64: nil, axTreeSnapshot: nil),
            .blocked(reason: "stuck", screenshotBase64: nil, axTreeSnapshot: nil),
            .blocked(reason: "stuck", screenshotBase64: nil, axTreeSnapshot: nil),
        ]

        var config = AxionConfig.default
        config.maxReplanRetries = 2
        config.maxBatches = 10

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        let context = await engine.run(task: "test", config: config, options: RunEngineOptions())

        XCTAssertEqual(context.currentState, .failed, "Engine should fail when max replan retries exceeded")
    }

    /// RunEngine dryrun mode skips execution and verification.
    func test_runEngineDryrunMode() async throws {
        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()

        planner.plans = [
            Plan(id: UUID(), task: "test", steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")], purpose: "launch", expectedChange: "app running")
            ], stopWhen: [], maxRetries: 3)
        ]

        let config = AxionConfig.default

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        let context = await engine.run(task: "test", config: config, options: RunEngineOptions(dryrun: true))

        XCTAssertEqual(context.currentState, .done, "Dryrun should reach .done without execution")
        XCTAssertEqual(executor.executeCallCount, 0, "Executor should NOT be called in dryrun mode")
        XCTAssertEqual(verifier.verifyCallCount, 0, "Verifier should NOT be called in dryrun mode")
    }
}

// MARK: - Helper-Dependent Tests (requires real Helper + AX permissions)

/// E2E tests that require a real Helper process with AX permissions.
/// Covers: Stories 3.3 (placeholder resolution), 3.4 (verification with real AX tree).
final class CorePipelineHelperE2ETests: XCTestCase {

    private var fixture: E2EHelperFixture!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try E2EHelperFixture()
        try await fixture.setUpHelper()
    }

    override func tearDown() async throws {
        await fixture.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    // MARK: - Story 3.3: Placeholder Resolution with Real Helper

    /// Launches Calculator via MCP, captures pid from result, verifies PlaceholderResolver
    /// absorbs it into ExecutionContext and resolves $pid in a subsequent step.
    func test_placeholderResolutionWithRealHelper() async throws {
        guard let mcpClient = fixture.mcpClient else {
            throw XCTSkip("AxionHelper not available")
        }

        let launchResult = try await mcpClient.callTool(
            name: "launch_app",
            arguments: ["app_name": .string("Calculator")]
        )

        var execContext = ExecutionContext()
        let resolver = PlaceholderResolver()
        resolver.absorbResult(tool: "launch_app", result: launchResult, context: &execContext)

        XCTAssertNotNil(execContext.pid, "pid should be extracted from launch_app result: \(launchResult)")

        let stepWithPlaceholder = Step(
            index: 1,
            tool: "list_windows",
            parameters: ["pid": .placeholder("$pid")],
            purpose: "List Calculator windows",
            expectedChange: "Window list returned"
        )

        let resolvedStep = resolver.resolve(step: stepWithPlaceholder, context: execContext)
        XCTAssertEqual(resolvedStep.parameters["pid"], .int(execContext.pid!), "$pid should be resolved to actual pid")

        // Wait for Calculator window to become available
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        let windowsResult = try await mcpClient.callTool(
            name: "list_windows",
            arguments: ["pid": .int(execContext.pid!)]
        )
        XCTAssertTrue(
            windowsResult.contains("window_id") || windowsResult.contains("title"),
            "list_windows with resolved pid should return window info: \(windowsResult)"
        )

        _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("Calculator")])
    }

    /// Verifies $window_id placeholder resolution: launch → list_windows → get_window_state.
    func test_windowIdPlaceholderResolution() async throws {
        guard let mcpClient = fixture.mcpClient else {
            throw XCTSkip("AxionHelper not available")
        }

        let launchResult = try await mcpClient.callTool(
            name: "launch_app",
            arguments: ["app_name": .string("Calculator")]
        )

        var execContext = ExecutionContext()
        let resolver = PlaceholderResolver()
        resolver.absorbResult(tool: "launch_app", result: launchResult, context: &execContext)

        let windowsResult = try await mcpClient.callTool(
            name: "list_windows",
            arguments: ["pid": .int(execContext.pid!)]
        )
        resolver.absorbResult(tool: "list_windows", result: windowsResult, context: &execContext)

        XCTAssertNotNil(execContext.windowId, "window_id should be extracted from list_windows result: \(windowsResult)")

        let stepWithPlaceholder = Step(
            index: 2,
            tool: "get_window_state",
            parameters: ["window_id": .placeholder("$window_id")],
            purpose: "Get Calculator window state",
            expectedChange: "Window state with AX tree"
        )
        let resolvedStep = resolver.resolve(step: stepWithPlaceholder, context: execContext)
        XCTAssertEqual(resolvedStep.parameters["window_id"], .int(execContext.windowId!))

        let stateResult = try await mcpClient.callTool(
            name: "get_window_state",
            arguments: ["window_id": .int(execContext.windowId!)]
        )
        XCTAssertTrue(
            stateResult.contains("bounds") || stateResult.contains("ax_tree"),
            "get_window_state should return window info: \(stateResult)"
        )

        _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("Calculator")])
    }

    // MARK: - Story 3.4: Verification with Real AX Tree

    /// Tests StopConditionEvaluator with real AX tree data from Calculator.
    func test_stopConditionEvaluationWithRealAXTree() async throws {
        guard let mcpClient = fixture.mcpClient else {
            throw XCTSkip("AxionHelper not available")
        }

        let launchResult = try await mcpClient.callTool(
            name: "launch_app",
            arguments: ["app_name": .string("Calculator")]
        )

        var execContext = ExecutionContext()
        let resolver = PlaceholderResolver()
        resolver.absorbResult(tool: "launch_app", result: launchResult, context: &execContext)

        let windowsResult = try await mcpClient.callTool(
            name: "list_windows",
            arguments: ["pid": .int(execContext.pid!)]
        )
        resolver.absorbResult(tool: "list_windows", result: windowsResult, context: &execContext)

        let axTreeResult = try await mcpClient.callTool(
            name: "get_accessibility_tree",
            arguments: ["window_id": .int(execContext.windowId!)]
        )

        // Wait for Calculator window to be fully rendered
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        let evaluator = StopConditionEvaluator()

        // textAppears — check for Calculator (locale-aware: "Calculator" or "计算器")
        let satisfiedResultEN = evaluator.evaluate(
            stopConditions: [StopCondition(type: .textAppears, value: "Calculator")],
            screenshot: nil,
            axTree: axTreeResult,
            executedSteps: [],
            maxSteps: 20
        )
        let satisfiedResultZH = evaluator.evaluate(
            stopConditions: [StopCondition(type: .textAppears, value: "计算器")],
            screenshot: nil,
            axTree: axTreeResult,
            executedSteps: [],
            maxSteps: 20
        )
        XCTAssertTrue(
            satisfiedResultEN == .satisfied || satisfiedResultZH == .satisfied,
            "textAppears 'Calculator' or '计算器' should be satisfied in AX tree: \(axTreeResult.prefix(200))"
        )

        // textAppears "TextEdit" → not satisfied
        let notFoundResult = evaluator.evaluate(
            stopConditions: [StopCondition(type: .textAppears, value: "TextEdit")],
            screenshot: nil,
            axTree: axTreeResult,
            executedSteps: [],
            maxSteps: 20
        )
        XCTAssertEqual(notFoundResult, .notSatisfied, "textAppears 'TextEdit' should NOT be satisfied")

        _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("Calculator")])
    }
}

// MARK: - Mock Components for RunEngine Tests

private final class MockPlanner: PlannerProtocol {
    var plans: [Plan] = []
    private var planIndex = 0

    func createPlan(for task: String, context: RunContext) async throws -> Plan {
        guard planIndex < plans.count else {
            return Plan(id: UUID(), task: task, steps: [], stopWhen: [], maxRetries: 3)
        }
        defer { planIndex += 1 }
        return plans[planIndex]
    }

    func replan(from originalPlan: Plan, executedSteps: [ExecutedStep], failureReason: String, context: RunContext) async throws -> Plan {
        guard planIndex < plans.count else {
            return Plan(id: UUID(), task: originalPlan.task, steps: [], stopWhen: [], maxRetries: 3)
        }
        defer { planIndex += 1 }
        return plans[planIndex]
    }
}

private final class MockExecutor: ExecutorProtocol {
    var results: [[ExecutedStep]] = []
    private var resultIndex = 0
    private(set) var executeCallCount = 0

    func executeStep(_ step: Step, context: RunContext) async throws -> ExecutedStep {
        return ExecutedStep(stepIndex: step.index, tool: step.tool, parameters: step.parameters, result: "ok", success: true, timestamp: Date())
    }

    func executePlan(_ plan: Plan, context: RunContext) async throws -> (executedSteps: [ExecutedStep], context: RunContext) {
        executeCallCount += 1
        guard resultIndex < results.count else {
            return (executedSteps: [], context: context)
        }
        defer { resultIndex += 1 }
        return (executedSteps: results[resultIndex], context: context)
    }
}

private final class MockVerifier: VerifierProtocol {
    var results: [VerificationResult] = []
    private var resultIndex = 0
    private(set) var verifyCallCount = 0

    func verify(plan: Plan, executedSteps: [ExecutedStep], context: RunContext) async throws -> VerificationResult {
        verifyCallCount += 1
        guard resultIndex < results.count else {
            return .done(reason: "default", screenshotBase64: nil, axTreeSnapshot: nil)
        }
        defer { resultIndex += 1 }
        return results[resultIndex]
    }
}

private final class MockOutput: OutputProtocol {
    private(set) var replanCalls = 0
    private(set) var stateChanges: [(RunState, RunState)] = []

    func displayRunStart(runId: String, task: String, mode: String) {}
    func displayStateChange(from: RunState, to: RunState) {
        stateChanges.append((from, to))
    }
    func displayPlan(_ plan: Plan) {}
    func displayStepResult(_ executedStep: ExecutedStep) {}
    func displayVerificationResult(_ result: VerificationResult) {}
    func displayReplan(attempt: Int, maxRetries: Int, reason: String) {
        replanCalls += 1
    }
    func displayError(_ error: AxionError) {}
    func displaySummary(context: RunContext) {}
}
