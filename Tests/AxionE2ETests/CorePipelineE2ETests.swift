import Foundation
import Testing

import AxionCore
import OpenAgentSDK
@testable import AxionCLI

// MARK: - Pure Logic Tests (no Helper required)

/// Tests for core pipeline components that don't require a real Helper process.
/// These run in any CI environment.
///
/// Covers: Stories 3.2 (prompt loading), 3.4 (stop conditions), 3.6 (safety, run engine).
@Suite("Core Pipeline Logic E2E")
struct CorePipelineLogicE2ETests {

    // MARK: - Story 3.2: Prompt Management

    @Test("prompt loading with variable injection")
    func promptLoadingWithVariableInjection() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let systemPrompt = try PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: ToolNames.allToolNames),
                "max_steps": "25",
            ],
            fromDirectory: promptDir
        )

        #expect(!systemPrompt.contains("{{tools}}"), "{{tools}} should be replaced")
        #expect(!systemPrompt.contains("{{max_steps}}"), "{{max_steps}} should be replaced")
        #expect(systemPrompt.contains("launch_app"), "Prompt should contain tool descriptions")
        #expect(systemPrompt.contains("25"), "Prompt should contain the max_steps value")
        #expect(systemPrompt.contains("Axion"), "Prompt should contain agent identity")
    }

    @Test("prompt loading throws on missing file")
    func promptLoadingThrowsOnMissingFile() async throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        #expect(throws: Error.self) {
            try PromptBuilder.load(name: "nonexistent", variables: [:], fromDirectory: promptDir)
        }
    }

    // MARK: - Story 3.4: Stop Condition Evaluation

    @Test("maxSteps stop condition")
    func maxStepsStopCondition() {
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
        #expect(result == .satisfied, "maxStepsReached should be satisfied when steps == maxSteps")

        let underLimit = evaluator.evaluate(
            stopConditions: [condition],
            screenshot: nil,
            axTree: nil,
            executedSteps: executedSteps,
            maxSteps: 10
        )
        #expect(underLimit == .notSatisfied, "maxStepsReached should NOT be satisfied when steps < maxSteps")
    }

    @Test("empty stop conditions are trivially satisfied")
    func emptyStopConditions() {
        let evaluator = StopConditionEvaluator()
        let result = evaluator.evaluate(
            stopConditions: [],
            screenshot: nil,
            axTree: nil,
            executedSteps: [],
            maxSteps: 20
        )
        #expect(result == .satisfied, "Empty stop conditions should be trivially satisfied")
    }

    // MARK: - Story 3.6: Safety Checker

    @Test("safety checker blocks foreground in shared-seat mode")
    func safetyCheckerBlocksForegroundInSharedSeatMode() {
        let checker = SafetyChecker()

        let foregroundTools = ["click", "type_text", "press_key", "hotkey", "double_click", "right_click", "scroll", "drag"]
        for tool in foregroundTools {
            let result = checker.check(tool: tool, sharedSeatMode: true)
            #expect(!result.allowed, "Tool '\(tool)' should be blocked in shared-seat mode")
            #expect(result.errorMessage.contains("foreground"), "Error should mention foreground for \(tool)")
        }
    }

    @Test("safety checker allows foreground in normal mode")
    func safetyCheckerAllowsForegroundInNormalMode() {
        let checker = SafetyChecker()

        let allTools = ToolNames.allToolNames
        for tool in allTools {
            let result = checker.check(tool: tool, sharedSeatMode: false)
            #expect(result.allowed, "Tool '\(tool)' should be allowed in normal mode")
        }
    }

    @Test("safety checker allows read-only in background mode")
    func safetyCheckerAllowsReadOnlyInBackgroundMode() {
        let checker = SafetyChecker()

        let safeTools = ["list_apps", "list_windows", "screenshot", "get_accessibility_tree",
                         "launch_app", "open_url", "get_window_state", "quit_app"]
        for tool in safeTools {
            let result = checker.check(tool: tool, sharedSeatMode: true)
            #expect(result.allowed, "Tool '\(tool)' should be allowed in shared-seat mode")
        }
    }

    // MARK: - Story 3.6: Run Engine State Machine

    @Test("run engine replan loop succeeds on second attempt")
    func runEngineReplanLoop() async throws {
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

        #expect(context.currentState == .done, "Engine should reach .done after replan")
        #expect(output.replanCalls == 1, "Should have replanned once")
    }

    @Test("run engine terminates when max replan retries exceeded")
    func runEngineMaxReplanExceeded() async throws {
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

        #expect(context.currentState == .failed, "Engine should fail when max replan retries exceeded")
    }

    @Test("run engine dryrun mode skips execution and verification")
    func runEngineDryrunMode() async throws {
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

        #expect(context.currentState == .done, "Dryrun should reach .done without execution")
        #expect(executor.executeCallCount == 0, "Executor should NOT be called in dryrun mode")
        #expect(verifier.verifyCallCount == 0, "Verifier should NOT be called in dryrun mode")
    }
}

// MARK: - Helper-Dependent Tests (requires real Helper + AX permissions)

/// E2E tests that require a real Helper process with AX permissions.
/// Covers: Stories 3.3 (placeholder resolution), 3.4 (verification with real AX tree).
@Suite("Core Pipeline Helper E2E")
struct CorePipelineHelperE2ETests {

    private func setUpFixture() async throws -> E2EHelperFixture? {
        let fixture = try E2EHelperFixture()
        let started = try await fixture.setUpHelper()
        guard started else { return nil }
        return fixture
    }

    // MARK: - Story 3.3: Placeholder Resolution with Real Helper

    @Test("placeholder resolution with real helper")
    func placeholderResolutionWithRealHelper() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard let mcpClient = fixture.mcpClient else {
            await fixture.tearDown()
            return
        }

        let launchResult = try await mcpClient.callTool(
            name: "launch_app",
            arguments: ["app_name": .string("Calculator")]
        )

        var execContext = ExecutionContext()
        let resolver = PlaceholderResolver()
        resolver.absorbResult(tool: "launch_app", result: launchResult, context: &execContext)

        #expect(execContext.pid != nil, "pid should be extracted from launch_app result: \(launchResult)")

        let stepWithPlaceholder = Step(
            index: 1,
            tool: "list_windows",
            parameters: ["pid": .placeholder("$pid")],
            purpose: "List Calculator windows",
            expectedChange: "Window list returned"
        )

        let resolvedStep = resolver.resolve(step: stepWithPlaceholder, context: execContext)
        #expect(resolvedStep.parameters["pid"] == .int(execContext.pid!), "$pid should be resolved to actual pid")

        // Wait for Calculator window to become available
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        let windowsResult = try await mcpClient.callTool(
            name: "list_windows",
            arguments: ["pid": .int(execContext.pid!)]
        )
        #expect(
            windowsResult.contains("window_id") || windowsResult.contains("title"),
            "list_windows with resolved pid should return window info: \(windowsResult)"
        )

        _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("Calculator")])
        await fixture.tearDown()
    }

    @Test("window_id placeholder resolution")
    func windowIdPlaceholderResolution() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard let mcpClient = fixture.mcpClient else {
            await fixture.tearDown()
            return
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

        #expect(execContext.windowId != nil, "window_id should be extracted from list_windows result: \(windowsResult)")

        let stepWithPlaceholder = Step(
            index: 2,
            tool: "get_window_state",
            parameters: ["window_id": .placeholder("$window_id")],
            purpose: "Get Calculator window state",
            expectedChange: "Window state with AX tree"
        )
        let resolvedStep = resolver.resolve(step: stepWithPlaceholder, context: execContext)
        #expect(resolvedStep.parameters["window_id"] == .int(execContext.windowId!))

        let stateResult = try await mcpClient.callTool(
            name: "get_window_state",
            arguments: ["window_id": .int(execContext.windowId!)]
        )
        #expect(
            stateResult.contains("bounds") || stateResult.contains("ax_tree"),
            "get_window_state should return window info: \(stateResult)"
        )

        _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("Calculator")])
        await fixture.tearDown()
    }

    // MARK: - Story 3.4: Verification with Real AX Tree

    @Test("stop condition evaluation with real AX tree")
    func stopConditionEvaluationWithRealAXTree() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard let mcpClient = fixture.mcpClient else {
            await fixture.tearDown()
            return
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
        #expect(
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
        #expect(notFoundResult == .notSatisfied, "textAppears 'TextEdit' should NOT be satisfied")

        _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("Calculator")])
        await fixture.tearDown()
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
