import XCTest
@testable import AxionCore

// [P0] Protocol method existence and signature validation
// [P1] Default implementation behavior

// MARK: - OutputProtocol ATDD Tests

/// ATDD red-phase tests for OutputProtocol (Story 3-5 AC1-7).
/// Validates that OutputProtocol has all required method signatures:
/// - 5 existing methods (displayPlan, displayStepResult, displayStateChange, displayError, displaySummary)
/// - 3 new methods (displayRunStart, displayReplan, displayVerificationResult)
///
/// TDD RED PHASE: These tests will not compile until OutputProtocol is updated
/// with the 3 new method signatures in Sources/AxionCore/Protocols/OutputProtocol.swift.
final class OutputProtocolTests: XCTestCase {

    // MARK: - P0 Type Existence

    func test_outputProtocol_hasRequiredMethods() {
        // Verify OutputProtocol type exists and can be used as a constraint
        let _ = OutputProtocol.self
    }

    // MARK: - P0 New Method Signatures (AC1, AC4)

    func test_outputProtocol_displayRunStart_signature() {
        // displayRunStart(runId:task:mode:) must exist on OutputProtocol
        // This test validates the method signature by calling it through a conforming type.
        // TerminalOutput/JSONOutput will implement this method.
        let mock = MockOutput()
        mock.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")
        XCTAssertEqual(mock.runStartCallCount, 1)
        XCTAssertEqual(mock.capturedRunId, "20260510-abc123")
        XCTAssertEqual(mock.capturedTask, "Open Calculator")
        XCTAssertEqual(mock.capturedMode, "plan_execute")
    }

    func test_outputProtocol_displayReplan_signature() {
        // displayReplan(attempt:maxRetries:reason:) must exist on OutputProtocol
        let mock = MockOutput()
        mock.displayReplan(attempt: 2, maxRetries: 3, reason: "Step failed")
        XCTAssertEqual(mock.replanCallCount, 1)
        XCTAssertEqual(mock.capturedReplanAttempt, 2)
        XCTAssertEqual(mock.capturedReplanMaxRetries, 3)
        XCTAssertEqual(mock.capturedReplanReason, "Step failed")
    }

    func test_outputProtocol_displayVerificationResult_signature() {
        // displayVerificationResult(_:) must exist on OutputProtocol
        let mock = MockOutput()
        let result = VerificationResult.done(reason: "Task complete")
        mock.displayVerificationResult(result)
        XCTAssertEqual(mock.verificationResultCallCount, 1)
        XCTAssertEqual(mock.capturedVerificationResult?.state, .done)
    }

    // MARK: - P0 Existing Methods Unchanged (AC1-7)

    func test_outputProtocol_existingMethods_unchanged() {
        // All 5 original methods must still exist with same signatures
        let mock = MockOutput()

        // displayPlan(_:)
        let plan = Plan(
            id: UUID(),
            task: "test",
            steps: [Step(index: 0, tool: "click", parameters: [:], purpose: "test", expectedChange: "none")],
            stopWhen: [],
            maxRetries: 3
        )
        mock.displayPlan(plan)
        XCTAssertEqual(mock.displayPlanCallCount, 1)

        // displayStepResult(_:)
        let executedStep = ExecutedStep(
            stepIndex: 0,
            tool: "click",
            parameters: [:],
            result: "ok",
            success: true,
            timestamp: Date()
        )
        mock.displayStepResult(executedStep)
        XCTAssertEqual(mock.displayStepResultCallCount, 1)

        // displayStateChange(from:to:)
        mock.displayStateChange(from: .planning, to: .executing)
        XCTAssertEqual(mock.displayStateChangeCallCount, 1)

        // displayError(_:)
        mock.displayError(.cancelled)
        XCTAssertEqual(mock.displayErrorCallCount, 1)

        // displaySummary(context:)
        let context = RunContext(
            planId: UUID(),
            currentState: .done,
            currentStepIndex: 1,
            executedSteps: [executedStep],
            replanCount: 0,
            config: .default
        )
        mock.displaySummary(context: context)
        XCTAssertEqual(mock.displaySummaryCallCount, 1)
    }
}

// MARK: - Mock OutputProtocol

/// Minimal mock to verify OutputProtocol method signatures.
/// Each method records its call count and captured arguments.
final class MockOutput: OutputProtocol {
    var runStartCallCount = 0
    var capturedRunId: String?
    var capturedTask: String?
    var capturedMode: String?

    var replanCallCount = 0
    var capturedReplanAttempt: Int?
    var capturedReplanMaxRetries: Int?
    var capturedReplanReason: String?

    var verificationResultCallCount = 0
    var capturedVerificationResult: VerificationResult?

    var displayPlanCallCount = 0
    var displayStepResultCallCount = 0
    var displayStateChangeCallCount = 0
    var displayErrorCallCount = 0
    var displaySummaryCallCount = 0

    func displayRunStart(runId: String, task: String, mode: String) {
        runStartCallCount += 1
        capturedRunId = runId
        capturedTask = task
        capturedMode = mode
    }

    func displayReplan(attempt: Int, maxRetries: Int, reason: String) {
        replanCallCount += 1
        capturedReplanAttempt = attempt
        capturedReplanMaxRetries = maxRetries
        capturedReplanReason = reason
    }

    func displayVerificationResult(_ result: VerificationResult) {
        verificationResultCallCount += 1
        capturedVerificationResult = result
    }

    func displayPlan(_ plan: Plan) {
        displayPlanCallCount += 1
    }

    func displayStepResult(_ executedStep: ExecutedStep) {
        displayStepResultCallCount += 1
    }

    func displayStateChange(from oldState: RunState, to newState: RunState) {
        displayStateChangeCallCount += 1
    }

    func displayError(_ error: AxionError) {
        displayErrorCallCount += 1
    }

    func displaySummary(context: RunContext) {
        displaySummaryCallCount += 1
    }
}
