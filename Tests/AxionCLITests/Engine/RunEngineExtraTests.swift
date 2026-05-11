import XCTest
@testable import AxionCLI
import AxionCore

// Additional RunEngine tests covering error paths and edge cases.

final class RunEngineExtraTests: XCTestCase {

    func makeDefaultConfig() -> AxionConfig {
        AxionConfig(apiKey: "test-key", maxSteps: 20, maxBatches: 6, maxReplanRetries: 3)
    }

    func makeSuccessPlan(task: String = "Open Calculator", stepCount: Int = 1) -> Plan {
        let steps = (0..<stepCount).map { i in
            Step(index: i, tool: "launch_app", parameters: ["app_name": .string("Calculator")],
                 purpose: "Step \(i)", expectedChange: "Done")
        }
        return Plan(id: UUID(), task: task, steps: steps, stopWhen: [StopCondition(type: .custom, value: "Done")], maxRetries: 3)
    }

    func makeSuccessExecutedSteps(from plan: Plan) -> [ExecutedStep] {
        plan.steps.enumerated().map { index, step in
            ExecutedStep(stepIndex: index, tool: step.tool, parameters: step.parameters, result: "{\"success\": true}", success: true, timestamp: Date())
        }
    }

    // MARK: - Executor throws generic error

    func test_runEngine_executorThrowsGenericError_entersFailed() async throws {
        let planner = MockPlannerExtra()
        let executor = MockExecutorExtra()
        let verifier = MockVerifierExtra()
        let output = MockOutputExtra()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.createPlanResult = .success(plan)
        executor.executePlanError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Executor crashed"])

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        let result = await engine.run(task: "Open Calculator", config: config, options: RunEngineOptions())

        XCTAssertEqual(result.currentState, .failed)
    }

    // MARK: - Verifier throws generic error

    func test_runEngine_verifierThrowsGenericError_entersFailed() async throws {
        let planner = MockPlannerExtra()
        let executor = MockExecutorExtra()
        let verifier = MockVerifierExtra()
        let output = MockOutputExtra()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.createPlanResult = .success(plan)
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        executor.executePlanResult = (executedSteps, RunContext(planId: plan.id, currentState: .executing, currentStepIndex: 0, executedSteps: [], replanCount: 0, config: config))
        verifier.verifyError = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Verifier crashed"])

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        let result = await engine.run(task: "Open Calculator", config: config, options: RunEngineOptions())

        XCTAssertEqual(result.currentState, .failed)
    }

    // MARK: - Planner throws generic error

    func test_runEngine_plannerThrowsGenericError_entersFailed() async throws {
        let planner = MockPlannerExtra()
        let executor = MockExecutorExtra()
        let verifier = MockVerifierExtra()
        let output = MockOutputExtra()
        let config = makeDefaultConfig()

        planner.createPlanResult = .failure(NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Planner crashed"]))

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        let result = await engine.run(task: "Open Calculator", config: config, options: RunEngineOptions())

        XCTAssertEqual(result.currentState, .failed)
    }

    // MARK: - Verifier returns unexpected state

    func test_runEngine_verifierReturnsUnexpectedState_entersFailed() async throws {
        let planner = MockPlannerExtra()
        let executor = MockExecutorExtra()
        let verifier = MockVerifierExtra()
        let output = MockOutputExtra()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.createPlanResult = .success(plan)
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        executor.executePlanResult = (executedSteps, RunContext(planId: plan.id, currentState: .executing, currentStepIndex: 0, executedSteps: [], replanCount: 0, config: config))
        verifier.verifyResult = VerificationResult(state: .planning, reason: "Unexpected")

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        let result = await engine.run(task: "Open Calculator", config: config, options: RunEngineOptions())

        XCTAssertEqual(result.currentState, .failed)
    }

    // MARK: - Executor throws AxionError.cancelled

    func test_runEngine_executorThrowsCancelled_entersCancelled() async throws {
        let planner = MockPlannerExtra()
        let executor = MockExecutorExtra()
        let verifier = MockVerifierExtra()
        let output = MockOutputExtra()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.createPlanResult = .success(plan)
        executor.executePlanError = AxionError.cancelled

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        let result = await engine.run(task: "Open Calculator", config: config, options: RunEngineOptions())

        XCTAssertEqual(result.currentState, .cancelled)
    }

    // MARK: - Verifier throws AxionError.cancelled

    func test_runEngine_verifierThrowsCancelled_entersCancelled() async throws {
        let planner = MockPlannerExtra()
        let executor = MockExecutorExtra()
        let verifier = MockVerifierExtra()
        let output = MockOutputExtra()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.createPlanResult = .success(plan)
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        executor.executePlanResult = (executedSteps, RunContext(planId: plan.id, currentState: .executing, currentStepIndex: 0, executedSteps: [], replanCount: 0, config: config))
        verifier.verifyError = AxionError.cancelled

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        let result = await engine.run(task: "Open Calculator", config: config, options: RunEngineOptions())

        XCTAssertEqual(result.currentState, .cancelled)
    }

    // MARK: - Batch budget exceeded

    func test_runEngine_batchBudgetExceeded_entersFailed() async throws {
        let planner = MockPlannerExtra()
        let executor = MockExecutorExtra()
        let verifier = MockVerifierExtra()
        let output = MockOutputExtra()
        var config = makeDefaultConfig()
        config.maxBatches = 1

        let plan = makeSuccessPlan()
        planner.createPlanResult = .success(plan)
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        executor.executePlanResult = (executedSteps, RunContext(planId: plan.id, currentState: .executing, currentStepIndex: 0, executedSteps: [], replanCount: 0, config: config))
        verifier.verifyResult = VerificationResult(state: .blocked, reason: "Not done")
        // replan returns success but blocked again
        planner.replanResult = .success(plan)

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        let result = await engine.run(task: "Open Calculator", config: config, options: RunEngineOptions())

        XCTAssertEqual(result.currentState, .failed)
    }

    // MARK: - Foreground mode

    func test_runEngine_foregroundMode_setsModeCorrectly() async throws {
        let planner = MockPlannerExtra()
        let executor = MockExecutorExtra()
        let verifier = MockVerifierExtra()
        let output = MockOutputExtra()
        let config = makeDefaultConfig()

        let plan = makeSuccessPlan()
        planner.createPlanResult = .success(plan)
        let executedSteps = makeSuccessExecutedSteps(from: plan)
        executor.executePlanResult = (executedSteps, RunContext(planId: plan.id, currentState: .executing, currentStepIndex: 0, executedSteps: [], replanCount: 0, config: config))
        verifier.verifyResult = VerificationResult(state: .done, reason: nil)

        let engine = RunEngine(planner: planner, executor: executor, verifier: verifier, output: output)
        var options = RunEngineOptions()
        options.allowForeground = true
        let result = await engine.run(task: "Open Calculator", config: config, options: options)

        XCTAssertEqual(result.currentState, .done)
        XCTAssertTrue(output.runStartCalls.contains(where: { $0.mode == "foreground" }))
    }

    // MARK: - RunEngineOptions custom values

    func test_runEngineOptions_customValues() {
        var options = RunEngineOptions()
        options.dryrun = true
        options.allowForeground = true
        options.maxSteps = 10
        options.maxBatches = 3
        options.verbose = true

        XCTAssertTrue(options.dryrun)
        XCTAssertTrue(options.allowForeground)
        XCTAssertEqual(options.maxSteps, 10)
        XCTAssertEqual(options.maxBatches, 3)
        XCTAssertTrue(options.verbose)
    }
}

// MARK: - Simple Mocks for Extra Tests

private final class MockPlannerExtra: PlannerProtocol {
    var createPlanResult: Result<Plan, Error>?
    var replanResult: Result<Plan, Error>?

    func createPlan(for task: String, context: RunContext) async throws -> Plan {
        if let result = createPlanResult { return try result.get() }
        return Plan(id: UUID(), task: task, steps: [], stopWhen: [], maxRetries: 3)
    }

    func replan(from currentPlan: Plan, executedSteps: [ExecutedStep], failureReason: String, context: RunContext) async throws -> Plan {
        if let result = replanResult { return try result.get() }
        return Plan(id: UUID(), task: currentPlan.task, steps: [], stopWhen: [], maxRetries: 3)
    }
}

private final class MockExecutorExtra: ExecutorProtocol {
    var executePlanResult: ([ExecutedStep], RunContext)?
    var executePlanError: Error?

    func executeStep(_ step: Step, context: RunContext) async throws -> ExecutedStep {
        ExecutedStep(stepIndex: step.index, tool: step.tool, parameters: step.parameters, result: "ok", success: true, timestamp: Date())
    }

    func executePlan(_ plan: Plan, context: RunContext) async throws -> (executedSteps: [ExecutedStep], context: RunContext) {
        if let error = executePlanError { throw error }
        if let result = executePlanResult { return result }
        return ([], context)
    }
}

private final class MockVerifierExtra: VerifierProtocol {
    var verifyResult: VerificationResult?
    var verifyError: Error?

    func verify(plan: Plan, executedSteps: [ExecutedStep], context: RunContext) async throws -> VerificationResult {
        if let error = verifyError { throw error }
        return verifyResult ?? .done()
    }
}

private final class MockOutputExtra: OutputProtocol {
    var runStartCalls: [(runId: String, task: String, mode: String)] = []

    func displayRunStart(runId: String, task: String, mode: String) {
        runStartCalls.append((runId: runId, task: task, mode: mode))
    }
    func displayReplan(attempt: Int, maxRetries: Int, reason: String) {}
    func displayVerificationResult(_ result: VerificationResult) {}
    func displayPlan(_ plan: Plan) {}
    func displayStepResult(_ executedStep: ExecutedStep) {}
    func displayStateChange(from oldState: RunState, to newState: RunState) {}
    func displayError(_ error: AxionError) {}
    func displaySummary(context: RunContext) {}
}
