import Foundation
import Testing
@testable import AxionCore

// [P0] Protocol method existence and signature validation
// [P1] Default implementation behavior

// MARK: - OutputProtocol ATDD Tests

/// ATDD red-phase tests for OutputProtocol (Story 3-5 AC1-7).
/// Validates that OutputProtocol has all required method signatures:
/// - 5 existing methods (displayPlan, displayStepResult, displayStateChange, displayError, displaySummary)
/// - 3 new methods (displayRunStart, displayReplan, displayVerificationResult)
@Suite("OutputProtocol")
struct OutputProtocolTests {

    // MARK: - P0 Type Existence

    @Test("outputProtocol has required methods")
    func outputProtocolHasRequiredMethods() {
        let _ = OutputProtocol.self
    }

    // MARK: - P0 New Method Signatures (AC1, AC4)

    @Test("outputProtocol displayRunStart signature")
    func outputProtocolDisplayRunStartSignature() {
        let mock = MockOutput()
        mock.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")
        #expect(mock.runStartCallCount == 1)
        #expect(mock.capturedRunId == "20260510-abc123")
        #expect(mock.capturedTask == "Open Calculator")
        #expect(mock.capturedMode == "plan_execute")
    }

    @Test("outputProtocol displayReplan signature")
    func outputProtocolDisplayReplanSignature() {
        let mock = MockOutput()
        mock.displayReplan(attempt: 2, maxRetries: 3, reason: "Step failed")
        #expect(mock.replanCallCount == 1)
        #expect(mock.capturedReplanAttempt == 2)
        #expect(mock.capturedReplanMaxRetries == 3)
        #expect(mock.capturedReplanReason == "Step failed")
    }

    @Test("outputProtocol displayVerificationResult signature")
    func outputProtocolDisplayVerificationResultSignature() {
        let mock = MockOutput()
        let result = VerificationResult.done(reason: "Task complete")
        mock.displayVerificationResult(result)
        #expect(mock.verificationResultCallCount == 1)
        #expect(mock.capturedVerificationResult?.state == .done)
    }

    // MARK: - P0 Existing Methods Unchanged (AC1-7)

    @Test("outputProtocol existing methods unchanged")
    func outputProtocolExistingMethodsUnchanged() {
        let mock = MockOutput()

        let plan = Plan(
            id: UUID(),
            task: "test",
            steps: [Step(index: 0, tool: "click", parameters: [:], purpose: "test", expectedChange: "none")],
            stopWhen: [],
            maxRetries: 3
        )
        mock.displayPlan(plan)
        #expect(mock.displayPlanCallCount == 1)

        let executedStep = ExecutedStep(
            stepIndex: 0,
            tool: "click",
            parameters: [:],
            result: "ok",
            success: true,
            timestamp: Date()
        )
        mock.displayStepResult(executedStep)
        #expect(mock.displayStepResultCallCount == 1)

        mock.displayStateChange(from: .planning, to: .executing)
        #expect(mock.displayStateChangeCallCount == 1)

        mock.displayError(.cancelled)
        #expect(mock.displayErrorCallCount == 1)

        let context = RunContext(
            planId: UUID(),
            currentState: .done,
            currentStepIndex: 1,
            executedSteps: [executedStep],
            replanCount: 0,
            config: .default
        )
        mock.displaySummary(context: context)
        #expect(mock.displaySummaryCallCount == 1)
    }
}

// MARK: - Mock OutputProtocol

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
