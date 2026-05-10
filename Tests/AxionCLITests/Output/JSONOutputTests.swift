import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] JSON structure validation: finalize produces valid JSON with required fields
// [P1] Data accumulation: steps, state transitions, verification results

// MARK: - JSONOutput ATDD Tests

/// ATDD red-phase tests for JSONOutput (Story 3-5 AC5).
/// Tests that JSONOutput accumulates output data and produces a valid JSON string
/// via its finalize() method.
///
/// TDD RED PHASE: These tests will not compile until JSONOutput is implemented
/// in Sources/AxionCLI/Output/JSONOutput.swift.
final class JSONOutputTests: XCTestCase {

    // MARK: - P0 Type Existence

    func test_jsonOutput_typeExists() {
        let _ = JSONOutput.self
    }

    func test_jsonOutput_conformsToOutputProtocol() {
        // JSONOutput must conform to OutputProtocol
        let output = JSONOutput()
        let _: OutputProtocol = output
    }

    // MARK: - P0 AC5: JSON Structured Output

    func test_jsonOutput_finalize_producesValidJSON() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let json = output.finalize()

        // Must be valid JSON
        let jsonData = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: jsonData)
        XCTAssertNotNil(parsed, "finalize() must produce valid JSON: \(json)")
    }

    func test_jsonOutput_finalize_containsRunId() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let json = output.finalize()
        let dict = parseJSON(json)

        XCTAssertEqual(dict?["runId"] as? String, "20260510-abc123",
            "JSON must contain correct runId")
    }

    func test_jsonOutput_finalize_containsTask() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let json = output.finalize()
        let dict = parseJSON(json)

        XCTAssertEqual(dict?["task"] as? String, "Open Calculator",
            "JSON must contain correct task")
    }

    func test_jsonOutput_finalize_containsSteps() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")

        let step = ExecutedStep(
            stepIndex: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")],
            result: "{\"pid\": 1234}", success: true, timestamp: Date()
        )
        output.displayStepResult(step)

        let json = output.finalize()
        let dict = parseJSON(json)

        XCTAssertNotNil(dict?["steps"] as? [[String: Any]],
            "JSON must contain steps array")
        let steps = dict?["steps"] as? [[String: Any]]
        XCTAssertEqual(steps?.count, 1, "steps array should have 1 entry")
    }

    func test_jsonOutput_finalize_containsSummary() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")

        let step = ExecutedStep(
            stepIndex: 0, tool: "launch_app", parameters: [:],
            result: "ok", success: true, timestamp: Date()
        )
        output.displayStepResult(step)

        let context = RunContext(
            planId: UUID(), currentState: .done, currentStepIndex: 1,
            executedSteps: [step], replanCount: 0, config: .default
        )
        output.displaySummary(context: context)

        let json = output.finalize()
        let dict = parseJSON(json)

        XCTAssertNotNil(dict?["summary"] as? [String: Any],
            "JSON must contain summary object")
    }

    // MARK: - P0 AC5: Steps Array Correctness

    func test_jsonOutput_stepsArray_reflectsExecutedSteps() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")

        let step1 = ExecutedStep(
            stepIndex: 0, tool: "launch_app", parameters: [:],
            result: "{\"pid\": 1}", success: true, timestamp: Date()
        )
        let step2 = ExecutedStep(
            stepIndex: 1, tool: "click", parameters: [:],
            result: "clicked", success: true, timestamp: Date()
        )
        output.displayStepResult(step1)
        output.displayStepResult(step2)

        let json = output.finalize()
        let dict = parseJSON(json)
        let steps = dict?["steps"] as? [[String: Any]]

        XCTAssertEqual(steps?.count, 2, "steps array should have 2 entries")
    }

    func test_jsonOutput_summary_computesTotalSteps() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")

        let step = ExecutedStep(
            stepIndex: 0, tool: "launch_app", parameters: [:],
            result: "ok", success: true, timestamp: Date()
        )
        output.displayStepResult(step)

        let context = RunContext(
            planId: UUID(), currentState: .done, currentStepIndex: 1,
            executedSteps: [step], replanCount: 0, config: .default
        )
        output.displaySummary(context: context)

        let json = output.finalize()
        let dict = parseJSON(json)
        let summary = dict?["summary"] as? [String: Any]

        XCTAssertEqual(summary?["totalSteps"] as? Int, 1,
            "summary.totalSteps should be 1")
    }

    func test_jsonOutput_summary_computesSuccessfulSteps() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")

        let step1 = ExecutedStep(
            stepIndex: 0, tool: "launch_app", parameters: [:],
            result: "ok", success: true, timestamp: Date()
        )
        let step2 = ExecutedStep(
            stepIndex: 1, tool: "click", parameters: [:],
            result: "fail", success: false, timestamp: Date()
        )
        output.displayStepResult(step1)
        output.displayStepResult(step2)

        let context = RunContext(
            planId: UUID(), currentState: .done, currentStepIndex: 2,
            executedSteps: [step1, step2], replanCount: 0, config: .default
        )
        output.displaySummary(context: context)

        let json = output.finalize()
        let dict = parseJSON(json)
        let summary = dict?["summary"] as? [String: Any]

        XCTAssertEqual(summary?["successfulSteps"] as? Int, 1,
            "summary.successfulSteps should be 1")
    }

    func test_jsonOutput_summary_computesFailedSteps() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")

        let step1 = ExecutedStep(
            stepIndex: 0, tool: "launch_app", parameters: [:],
            result: "ok", success: true, timestamp: Date()
        )
        let step2 = ExecutedStep(
            stepIndex: 1, tool: "click", parameters: [:],
            result: "fail", success: false, timestamp: Date()
        )
        output.displayStepResult(step1)
        output.displayStepResult(step2)

        let context = RunContext(
            planId: UUID(), currentState: .done, currentStepIndex: 2,
            executedSteps: [step1, step2], replanCount: 0, config: .default
        )
        output.displaySummary(context: context)

        let json = output.finalize()
        let dict = parseJSON(json)
        let summary = dict?["summary"] as? [String: Any]

        XCTAssertEqual(summary?["failedSteps"] as? Int, 1,
            "summary.failedSteps should be 1")
    }

    // MARK: - P1 AC5: Data Accumulation

    func test_jsonOutput_displayRunStart_storesRunInfo() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-xyz789", task: "Calculate 17*23", mode: "plan_execute")

        let json = output.finalize()
        let dict = parseJSON(json)

        XCTAssertEqual(dict?["runId"] as? String, "20260510-xyz789")
        XCTAssertEqual(dict?["task"] as? String, "Calculate 17*23")
        XCTAssertEqual(dict?["mode"] as? String, "plan_execute")
    }

    func test_jsonOutput_displayError_recordsError() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")
        output.displayError(.planningFailed(reason: "LLM timeout"))

        let json = output.finalize()
        let dict = parseJSON(json)

        // Error should appear somewhere in the output
        let errors = dict?["errors"] as? [[String: Any]]
        XCTAssertNotNil(errors, "JSON should contain errors array")
        XCTAssertGreaterThan(errors?.count ?? 0, 0, "errors array should have at least 1 entry")
    }

    func test_jsonOutput_displayStateChange_recordsTransition() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")
        output.displayStateChange(from: .planning, to: .executing)

        let json = output.finalize()
        let dict = parseJSON(json)

        // State transitions should appear somewhere
        let transitions = dict?["stateTransitions"] as? [[String: Any]]
        XCTAssertNotNil(transitions, "JSON should contain stateTransitions array")
        XCTAssertGreaterThan(transitions?.count ?? 0, 0, "stateTransitions should have at least 1 entry")
    }

    func test_jsonOutput_displayVerificationResult_recordsResult() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")
        output.displayVerificationResult(.done(reason: "Task complete"))

        let json = output.finalize()
        let dict = parseJSON(json)

        let results = dict?["verificationResults"] as? [[String: Any]]
        XCTAssertNotNil(results, "JSON should contain verificationResults array")
        XCTAssertGreaterThan(results?.count ?? 0, 0, "verificationResults should have at least 1 entry")
    }

    // MARK: - Helper

    private func parseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
