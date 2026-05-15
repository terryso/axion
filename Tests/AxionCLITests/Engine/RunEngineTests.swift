import Testing
import Foundation
@testable import AxionCLI
import AxionCore

// ATDD RED PHASE — Story 3-6: Run Engine 执行循环状态机
// 所有测试在 RunEngine 实现后将通过 (TDD red-green-refactor)
// 测试覆盖 AC1-AC12 全部 12 个验收标准

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

@Suite("RunEngine")
struct RunEngineTests {

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

    @Test("RunEngine type exists")
    func runEngineTypeExists() throws {
        let _ = RunEngine.self
    }

    @Test("RunEngineOptions type exists")
    func runEngineOptionsTypeExists() throws {
        let _ = RunEngineOptions.self
    }

    @Test("AC1: happy path — planning -> executing -> verifying -> done")
    func happyPathPlanExecuteVerifyDone() async throws {

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

        #expect(result.currentState == .done)
        #expect(planner.createPlanCallCount == 1)
        #expect(executor.executePlanCallCount == 1)
        #expect(verifier.verifyCallCount == 1)
    }

    @Test("AC2: done state displays summary")
    func doneStateDisplaysSummary() async throws {

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

        #expect(output.displaySummaryCalls.count >= 1)
    }

    @Test("AC3: blocked triggers replan")
    func blockedTriggersReplan() async throws {

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

        #expect(result.currentState == .done)
        #expect(planner.replanCallCount == 1)
        #expect(output.displayReplanCalls.count >= 1)
    }

    @Test("AC4: replan success returns to executing")
    func replanSuccessReturnsToExecuting() async throws {

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

        #expect(executor.executePlanCallCount == 2)
        #expect(verifier.verifyCallCount == 2)
        #expect(result.currentState == .done)

        let executingTransitions = output.displayStateChangeCalls.filter { $0.to == .executing }
        #expect(executingTransitions.count == 2)
    }

    @Test("AC5: max replan retries exceeded enters failed")
    func maxReplanRetriesExceededEntersFailed() async throws {

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

        #expect(result.currentState == .failed)
        #expect(planner.replanCallCount == 2)
    }

    @Test("AC6: cancel propagation enters cancelled")
    func cancelPropagationEntersCancelled() async throws {

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

        #expect(result.currentState == .cancelled)
    }

    @Test("AC7: max batches exceeded enters failed")
    func maxBatchesExceededEntersFailed() async throws {

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

        #expect(result.currentState == .failed)
    }

    @Test("AC7: max steps exceeded stops execution")
    func maxStepsExceededStopsExecution() async throws {

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

        #expect(result.currentState == .failed)
    }

    @Test("AC8: dryrun mode plans only without execute")
    func dryrunModePlansOnlyNoExecute() async throws {

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

        #expect(result.currentState == .done)
        #expect(executor.executePlanCallCount == 0)
        #expect(verifier.verifyCallCount == 0)
        #expect(planner.createPlanCallCount == 1)
        #expect(output.displayPlanCalls.count >= 1)
    }

    @Test("AC9: allowForeground executes foreground ops")
    func allowForegroundExecutesForegroundOps() async throws {

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

        #expect(result.currentState == .done)
        #expect(executor.executePlanCallCount == 1)
    }

    @Test("AC10: needsClarification enters terminal state")
    func needsClarificationEntersTerminalState() async throws {

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

        #expect(result.currentState == .needsClarification)
        #expect(planner.replanCallCount == 0)
    }

    @Test("AC11: irrecoverable error enters failed")
    func irrecoverableErrorEntersFailed() async throws {

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

        #expect(result.currentState == .failed)
        #expect(output.displayErrorCalls.count >= 1)
    }

    @Test("AC12: step failure skips verify and replans")
    func stepFailureSkipsVerifyAndReplans() async throws {

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

        #expect(result.currentState == .done)
        #expect(verifier.verifyCallCount == 1)
        #expect(planner.replanCallCount == 1)
        #expect(executor.executePlanCallCount == 2)
    }

    @Test("AC12 variant: step failure replan exhausted enters failed")
    func stepFailureReplanExhaustedEntersFailed() async throws {

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

        #expect(result.currentState == .failed)
        #expect(verifier.verifyCallCount == 0)
    }

    @Test("calls displayRunStart")
    func callsDisplayRunStart() async throws {

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

        #expect(output.displayRunStartCalls.count >= 1)
        #expect(output.displayRunStartCalls.first?.task == "Open Calculator")
    }

    @Test("calls displayStateChange")
    func callsDisplayStateChange() async throws {

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

        #expect(output.displayStateChangeCalls.count >= 2)

        let planningToExecuting = output.displayStateChangeCalls.contains { $0.from == .planning && $0.to == .executing }
        #expect(planningToExecuting)
    }

    @Test("calls displayVerificationResult")
    func callsDisplayVerificationResult() async throws {

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

        #expect(output.displayVerificationResultCalls.count >= 1)
    }

    @Test("RunEngineOptions default values")
    func runEngineOptionsDefaultValues() throws {

        let options = RunEngineOptions()
        #expect(options.dryrun == false)
        #expect(options.allowForeground == false)
        #expect(options.maxSteps == nil) // nil means use config default
        #expect(options.maxBatches == nil) // nil means use config default
    }

    @Test("runId format YYYYMMDD-{6random}")
    func runIdFormat() async throws {

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
        let unwrappedRunId = try #require(runId)
        let pattern = "^\\d{8}-[a-z0-9]{6}$"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(unwrappedRunId.startIndex..., in: unwrappedRunId)
        let match = regex.firstMatch(in: unwrappedRunId, range: range)
        #expect(match != nil)
    }
}
