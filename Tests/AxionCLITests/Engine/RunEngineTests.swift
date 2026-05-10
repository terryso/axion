import XCTest
@testable import AxionCLI
import AxionCore

// [P0] 基础设施验证
// [P1] 行为验证

// ATDD RED PHASE — Story 3-6: Run Engine 执行循环状态机
// 所有测试在 RunEngine 实现后将通过 (TDD red-green-refactor)
// 测试覆盖 AC1-AC12 全部 12 个验收标准

// MARK: - Mock Planner

final class MockPlanner: PlannerProtocol {
    var createPlanResult: Result<Plan, Error>?
    var replanResult: Result<Plan, Error>?
    var createPlanCallCount = 0
    var replanCallCount = 0
    var lastReplanReason: String?

    private var createPlanResults: [Result<Plan, Error>] = []
    private var replanResults: [Result<Plan, Error>] = []
    private var createPlanIndex = 0
    private var replanIndex = 0

    func enqueueCreatePlanResult(_ result: Result<Plan, Error>) {
        createPlanResults.append(result)
    }

    func enqueueReplanResult(_ result: Result<Plan, Error>) {
        replanResults.append(result)
    }

    func createPlan(for task: String, context: RunContext) async throws -> Plan {
        createPlanCallCount += 1
        if createPlanIndex < createPlanResults.count {
            let result = createPlanResults[createPlanIndex]
            createPlanIndex += 1
            return try result.get()
        }
        if let result = createPlanResult {
            return try result.get()
        }
        return Plan(
            id: UUID(),
            task: task,
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")],
                     purpose: "Launch app", expectedChange: "App opens")
            ],
            stopWhen: [StopCondition(type: .custom, value: "App visible")],
            maxRetries: 3
        )
    }

    func replan(from currentPlan: Plan, executedSteps: [ExecutedStep], failureReason: String, context: RunContext) async throws -> Plan {
        replanCallCount += 1
        lastReplanReason = failureReason
        if replanIndex < replanResults.count {
            let result = replanResults[replanIndex]
            replanIndex += 1
            return try result.get()
        }
        if let result = replanResult {
            return try result.get()
        }
        return Plan(
            id: UUID(),
            task: currentPlan.task,
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")],
                     purpose: "Retry launch", expectedChange: "App opens")
            ],
            stopWhen: [StopCondition(type: .custom, value: "App visible")],
            maxRetries: 3
        )
    }
}

// MARK: - Mock Executor

final class MockExecutor: ExecutorProtocol {
    var executeStepResult: Result<ExecutedStep, Error>?
    var executePlanResult: Result<(executedSteps: [ExecutedStep], context: RunContext), Error>?
    var executeStepCallCount = 0
    var executePlanCallCount = 0

    private var executePlanResults: [Result<(executedSteps: [ExecutedStep], context: RunContext), Error>] = []
    private var planIndex = 0

    func enqueueExecutePlanResult(_ result: Result<(executedSteps: [ExecutedStep], context: RunContext), Error>) {
        executePlanResults.append(result)
    }

    func executeStep(_ step: Step, context: RunContext) async throws -> ExecutedStep {
        executeStepCallCount += 1
        if let result = executeStepResult {
            return try result.get()
        }
        return ExecutedStep(
            stepIndex: step.index,
            tool: step.tool,
            parameters: step.parameters,
            result: "{\"success\": true}",
            success: true,
            timestamp: Date()
        )
    }

    func executePlan(_ plan: Plan, context: RunContext) async throws -> (executedSteps: [ExecutedStep], context: RunContext) {
        executePlanCallCount += 1
        if planIndex < executePlanResults.count {
            let result = executePlanResults[planIndex]
            planIndex += 1
            return try result.get()
        }
        if let result = executePlanResult {
            return try result.get()
        }
        var updatedContext = context
        let executedSteps = plan.steps.enumerated().map { index, step in
            ExecutedStep(
                stepIndex: index,
                tool: step.tool,
                parameters: step.parameters,
                result: "{\"success\": true}",
                success: true,
                timestamp: Date()
            )
        }
        updatedContext.executedSteps = executedSteps
        updatedContext.currentStepIndex = executedSteps.count - 1
        return (executedSteps, updatedContext)
    }
}

// MARK: - Mock Verifier

final class MockVerifier: VerifierProtocol {
    var verifyResult: VerificationResult?
    var verifyCallCount = 0

    private var verifyResults: [VerificationResult] = []
    private var verifyIndex = 0

    func enqueueVerifyResult(_ result: VerificationResult) {
        verifyResults.append(result)
    }

    func verify(plan: Plan, executedSteps: [ExecutedStep], context: RunContext) async throws -> VerificationResult {
        verifyCallCount += 1
        if verifyIndex < verifyResults.count {
            let result = verifyResults[verifyIndex]
            verifyIndex += 1
            return result
        }
        return verifyResult ?? .done()
    }
}

// MARK: - Mock Output

final class MockOutput: OutputProtocol {
    var displayPlanCalls: [Plan] = []
    var displayStepResultCalls: [ExecutedStep] = []
    var displayStateChangeCalls: [(from: RunState, to: RunState)] = []
    var displayErrorCalls: [AxionError] = []
    var displaySummaryCalls: [RunContext] = []
    var displayRunStartCalls: [(runId: String, task: String, mode: String)] = []
    var displayReplanCalls: [(attempt: Int, maxRetries: Int, reason: String)] = []
    var displayVerificationResultCalls: [VerificationResult] = []

    func displayPlan(_ plan: Plan) {
        displayPlanCalls.append(plan)
    }

    func displayStepResult(_ executedStep: ExecutedStep) {
        displayStepResultCalls.append(executedStep)
    }

    func displayStateChange(from oldState: RunState, to newState: RunState) {
        displayStateChangeCalls.append((from: oldState, to: newState))
    }

    func displayError(_ error: AxionError) {
        displayErrorCalls.append(error)
    }

    func displaySummary(context: RunContext) {
        displaySummaryCalls.append(context)
    }

    func displayRunStart(runId: String, task: String, mode: String) {
        displayRunStartCalls.append((runId: runId, task: task, mode: mode))
    }

    func displayReplan(attempt: Int, maxRetries: Int, reason: String) {
        displayReplanCalls.append((attempt: attempt, maxRetries: maxRetries, reason: reason))
    }

    func displayVerificationResult(_ result: VerificationResult) {
        displayVerificationResultCalls.append(result)
    }
}

// MARK: - Test Helpers

extension RunEngineTests {
    func makeDefaultConfig() -> AxionConfig {
        AxionConfig(
            apiKey: "test-key",
            maxSteps: 20,
            maxBatches: 6,
            maxReplanRetries: 3
        )
    }

    func makeSuccessPlan(task: String = "Open Calculator", stepCount: Int = 1) -> Plan {
        let steps = (0..<stepCount).map { i in
            Step(
                index: i,
                tool: "launch_app",
                parameters: ["app_name": .string("Calculator")],
                purpose: "Step \(i)",
                expectedChange: "Done"
            )
        }
        return Plan(
            id: UUID(),
            task: task,
            steps: steps,
            stopWhen: [StopCondition(type: .custom, value: "Done")],
            maxRetries: 3
        )
    }

    func makeSuccessExecutedSteps(from plan: Plan) -> [ExecutedStep] {
        plan.steps.enumerated().map { index, step in
            ExecutedStep(
                stepIndex: index,
                tool: step.tool,
                parameters: step.parameters,
                result: "{\"success\": true}",
                success: true,
                timestamp: Date()
            )
        }
    }

    func makeFailedExecutedStep(index: Int = 0) -> ExecutedStep {
        ExecutedStep(
            stepIndex: index,
            tool: "launch_app",
            parameters: ["app_name": .string("BadApp")],
            result: "App not found",
            success: false,
            timestamp: Date()
        )
    }
}

// MARK: - RunEngine ATDD Tests

final class RunEngineTests: XCTestCase {

    // ========================================================================
    // MARK: - [P0] 类型存在性 — RunEngine 和 RunEngineOptions 存在
    // ========================================================================

    func test_runEngine_typeExists() throws {
        let _ = RunEngine.self
    }

    func test_runEngineOptions_typeExists() throws {
        let _ = RunEngineOptions.self
    }

    // ========================================================================
    // MARK: - [P0] AC1: 状态机启动 — planning -> executing -> verifying
    // ========================================================================

    func test_runEngine_happyPath_planExecuteVerifyDone() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan))

        let executedSteps = makeSuccessExecutedSteps(from: plan)
        let context = RunContext(
            planId: plan.id,
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps, context: context)))

        verifier.enqueueVerifyResult(.done())

        let engine = RunEngine(
            planner: planner,
            executor: executor,
            verifier: verifier,
            output: output
        )

        let options = RunEngineOptions()
        let result = await engine.run(task: "Open Calculator", config: config, options: options)

        // Verify final state is .done
        XCTAssertEqual(result.currentState, .done)

        // Verify planner was called once
        XCTAssertEqual(planner.createPlanCallCount, 1)

        // Verify executor was called once
        XCTAssertEqual(executor.executePlanCallCount, 1)

        // Verify verifier was called once
        XCTAssertEqual(verifier.verifyCallCount, 1)
    }

    // ========================================================================
    // MARK: - [P0] AC2: 任务完成终态 (.done) — 显示完成汇总
    // ========================================================================

    func test_runEngine_doneState_displaysSummary() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan))
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        let context = RunContext(
            planId: plan.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps, context: context)))
        verifier.enqueueVerifyResult(.done())

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        _ = await engine.run(task: "Open Calculator", config: config, options: options)

        // Verify displaySummary was called
        XCTAssertTrue(output.displaySummaryCalls.count >= 1,
                       "displaySummary should be called when run completes")
    }

    // ========================================================================
    // MARK: - [P0] AC3: 重规划循环 — blocked -> replanning -> planning
    // ========================================================================

    func test_runEngine_blockedTriggersReplan() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        // First plan: verification returns blocked
        let plan1 = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan1))
        let executedSteps1 = makeSuccessExecutedSteps(from: plan1)
        let context1 = RunContext(
            planId: plan1.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps1, context: context1)))
        verifier.enqueueVerifyResult(.blocked(reason: "Calculator window not found"))

        // Second plan (replan): verification returns done
        let plan2 = makeSuccessPlan(task: "Open Calculator (retry)")
        planner.enqueueReplanResult(.success(plan2))
        let executedSteps2 = makeSuccessExecutedSteps(from: plan2)
        let context2 = RunContext(
            planId: plan2.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 1, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps2, context: context2)))
        verifier.enqueueVerifyResult(.done())

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        let result = await engine.run(task: "Open Calculator", config: config, options: options)

        // Verify final state is .done (after successful replan)
        XCTAssertEqual(result.currentState, .done)

        // Verify replan was called once
        XCTAssertEqual(planner.replanCallCount, 1)

        // Verify displayReplan was called
        XCTAssertTrue(output.displayReplanCalls.count >= 1,
                       "displayReplan should be called when replanning")
    }

    // ========================================================================
    // MARK: - [P0] AC4: 重规划后继续执行 — 回到 executing 状态
    // ========================================================================

    func test_runEngine_replanSuccess_returnsToExecuting() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        // First plan: blocked
        let plan1 = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan1))
        let executedSteps1 = makeSuccessExecutedSteps(from: plan1)
        let context1 = RunContext(
            planId: plan1.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps1, context: context1)))
        verifier.enqueueVerifyResult(.blocked(reason: "Not found"))

        // Replan: succeeds
        let plan2 = makeSuccessPlan(task: "Open Calculator (replan)")
        planner.enqueueReplanResult(.success(plan2))
        let executedSteps2 = makeSuccessExecutedSteps(from: plan2)
        let context2 = RunContext(
            planId: plan2.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 1, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps2, context: context2)))
        verifier.enqueueVerifyResult(.done())

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        let result = await engine.run(task: "Open Calculator", config: config, options: options)

        // Executor was called twice (original plan + replan plan)
        XCTAssertEqual(executor.executePlanCallCount, 2)

        // Verifier was called twice
        XCTAssertEqual(verifier.verifyCallCount, 2)

        // Final state is .done
        XCTAssertEqual(result.currentState, .done)

        // State transitions include executing twice
        let executingTransitions = output.displayStateChangeCalls.filter { $0.to == .executing }
        XCTAssertEqual(executingTransitions.count, 2,
                       "Should transition to executing twice (original + replan)")
    }

    // ========================================================================
    // MARK: - [P0] AC5: 最大重规划次数 — 进入 .failed 终态
    // ========================================================================

    func test_runEngine_maxReplanRetriesExceeded_entersFailed() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        var config = makeDefaultConfig()
        config.maxReplanRetries = 2 // Low limit for test

        // First plan: blocked
        let plan1 = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan1))
        let executedSteps1 = makeSuccessExecutedSteps(from: plan1)
        let context1 = RunContext(
            planId: plan1.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps1, context: context1)))
        verifier.enqueueVerifyResult(.blocked(reason: "Still blocked"))

        // Replan 1: still blocked
        let plan2 = makeSuccessPlan(task: "Retry 1")
        planner.enqueueReplanResult(.success(plan2))
        let executedSteps2 = makeSuccessExecutedSteps(from: plan2)
        let context2 = RunContext(
            planId: plan2.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 1, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps2, context: context2)))
        verifier.enqueueVerifyResult(.blocked(reason: "Still blocked"))

        // Replan 2: still blocked (should exceed maxReplanRetries = 2)
        let plan3 = makeSuccessPlan(task: "Retry 2")
        planner.enqueueReplanResult(.success(plan3))
        let executedSteps3 = makeSuccessExecutedSteps(from: plan3)
        let context3 = RunContext(
            planId: plan3.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 2, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps3, context: context3)))
        verifier.enqueueVerifyResult(.blocked(reason: "Still blocked"))

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        let result = await engine.run(task: "Impossible task", config: config, options: options)

        // Should enter .failed after max retries exceeded
        XCTAssertEqual(result.currentState, .failed)

        // Replan was called maxReplanRetries times
        XCTAssertEqual(planner.replanCallCount, 2)
    }

    // ========================================================================
    // MARK: - [P1] AC6: Ctrl-C 中断 — 进入 .cancelled
    // ========================================================================

    func test_runEngine_cancelPropagation_entersCancelled() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        // Planner throws cancelled error
        planner.enqueueCreatePlanResult(.failure(AxionError.cancelled))

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        let result = await engine.run(task: "Open Calculator", config: config, options: options)

        // Should enter .cancelled state
        XCTAssertEqual(result.currentState, .cancelled)
    }

    // ========================================================================
    // MARK: - [P0] AC7: 批次限制 — maxBatches 超出后终止
    // ========================================================================

    func test_runEngine_maxBatchesExceeded_entersFailed() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        var config = makeDefaultConfig()
        config.maxBatches = 2 // Low limit for test

        // Batch 1: blocked
        let plan1 = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan1))
        let executedSteps1 = makeSuccessExecutedSteps(from: plan1)
        let context1 = RunContext(
            planId: plan1.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps1, context: context1)))
        verifier.enqueueVerifyResult(.blocked(reason: "Not done"))

        // Batch 2 (replan): blocked — exceeds maxBatches
        let plan2 = makeSuccessPlan(task: "Retry")
        planner.enqueueReplanResult(.success(plan2))
        let executedSteps2 = makeSuccessExecutedSteps(from: plan2)
        let context2 = RunContext(
            planId: plan2.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 1, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps2, context: context2)))
        verifier.enqueueVerifyResult(.blocked(reason: "Not done"))

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        let result = await engine.run(task: "Open Calculator", config: config, options: options)

        // Should enter .failed when maxBatches exceeded
        XCTAssertEqual(result.currentState, .failed)
    }

    // ========================================================================
    // MARK: - [P0] AC7: 步数限制 — maxSteps 超出后终止
    // ========================================================================

    func test_runEngine_maxStepsExceeded_stopsExecution() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        var config = makeDefaultConfig()
        config.maxSteps = 2 // Very low limit

        // Plan with 3 steps (exceeds maxSteps)
        let plan = makeSuccessPlan(stepCount: 3)
        planner.enqueueCreatePlanResult(.success(plan))

        // Executor returns all 3 steps executed
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        let context = RunContext(
            planId: plan.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps, context: context)))

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        let result = await engine.run(task: "Complex task", config: config, options: options)

        // Should enter .failed when steps exceed maxSteps
        XCTAssertEqual(result.currentState, .failed)
    }

    // ========================================================================
    // MARK: - [P0] AC8: 干跑模式 — Planner 生成计划后不执行
    // ========================================================================

    func test_runEngine_dryrunMode_plansOnlyNoExecute() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan))

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        var options = RunEngineOptions()
        options.dryrun = true
        let result = await engine.run(task: "Open Calculator", config: config, options: options)

        // Should enter .done without executing
        XCTAssertEqual(result.currentState, .done)

        // Executor should NOT have been called
        XCTAssertEqual(executor.executePlanCallCount, 0,
                       "Executor should not be called in dryrun mode")

        // Verifier should NOT have been called
        XCTAssertEqual(verifier.verifyCallCount, 0,
                       "Verifier should not be called in dryrun mode")

        // Planner SHOULD have been called
        XCTAssertEqual(planner.createPlanCallCount, 1,
                       "Planner should be called in dryrun mode")

        // Plan should be displayed
        XCTAssertTrue(output.displayPlanCalls.count >= 1,
                       "Plan should be displayed in dryrun mode")
    }

    // ========================================================================
    // MARK: - [P1] AC9: 前台模式 — allowForeground 放行
    // ========================================================================

    func test_runEngine_allowForeground_executesForegroundOps() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        var config = makeDefaultConfig()
        config.sharedSeatMode = false // Allow foreground ops

        let plan = Plan(
            id: UUID(),
            task: "Click button",
            steps: [
                Step(index: 0, tool: "click", parameters: ["x": .int(100), "y": .int(200)],
                     purpose: "Click button", expectedChange: "Clicked")
            ],
            stopWhen: [StopCondition(type: .custom, value: "Clicked")],
            maxRetries: 3
        )
        planner.enqueueCreatePlanResult(.success(plan))

        let executedSteps = makeSuccessExecutedSteps(from: plan)
        let context = RunContext(
            planId: plan.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps, context: context)))
        verifier.enqueueVerifyResult(.done())

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        var options = RunEngineOptions()
        options.allowForeground = true
        let result = await engine.run(task: "Click button", config: config, options: options)

        XCTAssertEqual(result.currentState, .done)
        XCTAssertEqual(executor.executePlanCallCount, 1)
    }

    // ========================================================================
    // MARK: - [P1] AC10: needsClarification 处理 — 进入终态
    // ========================================================================

    func test_runEngine_needsClarification_entersTerminalState() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan))
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        let context = RunContext(
            planId: plan.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps, context: context)))
        verifier.enqueueVerifyResult(.needsClarification(reason: "Which calculator?"))

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        let result = await engine.run(task: "Open calculator", config: config, options: options)

        // Should enter .needsClarification state (terminal)
        XCTAssertEqual(result.currentState, .needsClarification)

        // Should NOT attempt replan
        XCTAssertEqual(planner.replanCallCount, 0,
                       "Should not replan for needsClarification")
    }

    // ========================================================================
    // MARK: - [P0] AC11: 不可恢复错误 — 进入 .failed 终态
    // ========================================================================

    func test_runEngine_irrecoverableError_entersFailed() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        // Planner throws irrecoverable error (e.g., API key invalid)
        planner.enqueueCreatePlanResult(.failure(AxionError.configError(reason: "API Key not found")))

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        let result = await engine.run(task: "Open Calculator", config: config, options: options)

        // Should enter .failed state
        XCTAssertEqual(result.currentState, .failed)

        // displayError should have been called
        XCTAssertTrue(output.displayErrorCalls.count >= 1,
                       "displayError should be called for irrecoverable errors")
    }

    // ========================================================================
    // MARK: - [P0] AC12: 步骤执行失败触发重规划 — 跳过验证
    // ========================================================================

    func test_runEngine_stepFailure_skipsVerifyAndReplans() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        // First plan: step execution fails
        let plan1 = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan1))

        let failedStep = makeFailedExecutedStep(index: 0)
        let context1 = RunContext(
            planId: plan1.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: [failedStep], context: context1)))

        // Replan: succeeds
        let plan2 = makeSuccessPlan(task: "Retry after failure")
        planner.enqueueReplanResult(.success(plan2))
        let executedSteps2 = makeSuccessExecutedSteps(from: plan2)
        let context2 = RunContext(
            planId: plan2.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 1, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps2, context: context2)))
        verifier.enqueueVerifyResult(.done())

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        let result = await engine.run(task: "Open Calculator", config: config, options: options)

        // Final state should be .done
        XCTAssertEqual(result.currentState, .done)

        // Verifier should only be called once (for the successful replan, NOT for the failed first plan)
        XCTAssertEqual(verifier.verifyCallCount, 1,
                       "Verifier should be skipped when step execution fails")

        // Replan should have been called once
        XCTAssertEqual(planner.replanCallCount, 1)

        // Executor should have been called twice (failed plan + replan plan)
        XCTAssertEqual(executor.executePlanCallCount, 2)
    }

    // ========================================================================
    // MARK: - [P0] AC12 变体: 步骤失败重规划也耗尽 -> .failed
    // ========================================================================

    func test_runEngine_stepFailureReplanExhausted_entersFailed() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        var config = makeDefaultConfig()
        config.maxReplanRetries = 1

        // First plan: step execution fails
        let plan1 = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan1))
        let failedStep = makeFailedExecutedStep(index: 0)
        let context1 = RunContext(
            planId: plan1.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: [failedStep], context: context1)))

        // Replan 1: also fails
        let plan2 = makeSuccessPlan(task: "Retry 1")
        planner.enqueueReplanResult(.success(plan2))
        let failedStep2 = makeFailedExecutedStep(index: 0)
        let context2 = RunContext(
            planId: plan2.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 1, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: [failedStep2], context: context2)))

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        let result = await engine.run(task: "Open Calculator", config: config, options: options)

        // Should enter .failed
        XCTAssertEqual(result.currentState, .failed)

        // Verifier should NOT have been called at all (all steps failed)
        XCTAssertEqual(verifier.verifyCallCount, 0)
    }

    // ========================================================================
    // MARK: - [P1] Output 调用验证 — displayRunStart 被调用
    // ========================================================================

    func test_runEngine_callsDisplayRunStart() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan))
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        let context = RunContext(
            planId: plan.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps, context: context)))
        verifier.enqueueVerifyResult(.done())

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        _ = await engine.run(task: "Open Calculator", config: config, options: options)

        // displayRunStart should have been called
        XCTAssertTrue(output.displayRunStartCalls.count >= 1,
                       "displayRunStart should be called at the beginning")
        XCTAssertEqual(output.displayRunStartCalls.first?.task, "Open Calculator")
    }

    // ========================================================================
    // MARK: - [P1] Output 调用验证 — displayStateChange 被调用
    // ========================================================================

    func test_runEngine_callsDisplayStateChange() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan))
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        let context = RunContext(
            planId: plan.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps, context: context)))
        verifier.enqueueVerifyResult(.done())

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        _ = await engine.run(task: "Open Calculator", config: config, options: options)

        // displayStateChange should have been called for state transitions
        XCTAssertTrue(output.displayStateChangeCalls.count >= 2,
                       "displayStateChange should be called for each state transition")

        // Should contain planning -> executing transition
        let planningToExecuting = output.displayStateChangeCalls.contains { $0.from == .planning && $0.to == .executing }
        XCTAssertTrue(planningToExecuting, "Should transition from planning to executing")
    }

    // ========================================================================
    // MARK: - [P1] Output 调用验证 — displayVerificationResult 被调用
    // ========================================================================

    func test_runEngine_callsDisplayVerificationResult() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan))
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        let context = RunContext(
            planId: plan.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps, context: context)))
        verifier.enqueueVerifyResult(.done(reason: "Calculator is open"))

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        _ = await engine.run(task: "Open Calculator", config: config, options: options)

        // displayVerificationResult should have been called
        XCTAssertTrue(output.displayVerificationResultCalls.count >= 1,
                       "displayVerificationResult should be called after verification")
    }

    // ========================================================================
    // MARK: - [P0] RunEngineOptions 默认值
    // ========================================================================

    func test_runEngineOptions_defaultValues() throws {

        let options = RunEngineOptions()
        XCTAssertEqual(options.dryrun, false)
        XCTAssertEqual(options.allowForeground, false)
        XCTAssertEqual(options.maxSteps, nil) // nil means use config default
        XCTAssertEqual(options.maxBatches, nil) // nil means use config default
    }

    // ========================================================================
    // MARK: - [P0] RunId 格式和唯一性
    // ========================================================================

    func test_runEngine_runIdFormat() async throws {

        let planner = MockPlanner()
        let executor = MockExecutor()
        let verifier = MockVerifier()
        let output = MockOutput()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.enqueueCreatePlanResult(.success(plan))
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        let context = RunContext(
            planId: plan.id, currentState: .executing, currentStepIndex: 0,
            executedSteps: [], replanCount: 0, config: config
        )
        executor.enqueueExecutePlanResult(.success((executedSteps: executedSteps, context: context)))
        verifier.enqueueVerifyResult(.done())

        let engine = RunEngine(
            planner: planner, executor: executor, verifier: verifier,
            output: output
        )
        let options = RunEngineOptions()
        _ = await engine.run(task: "Open Calculator", config: config, options: options)

        // Run ID should follow YYYYMMDD-{6random} format
        let runId = output.displayRunStartCalls.first?.runId
        XCTAssertNotNil(runId, "Run ID should be generated")
        let pattern = "^\\d{8}-[a-z0-9]{6}$"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(runId!.startIndex..., in: runId!)
        let match = regex.firstMatch(in: runId!, range: range)
        XCTAssertNotNil(match, "Run ID should match YYYYMMDD-{6random} format: \(runId!)")
    }
}
