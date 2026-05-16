import Foundation
import Testing
@testable import AxionCLI
@testable import AxionCore

/// ATDD red-phase tests for JSONOutput (Story 3-5 AC5).
/// Tests that JSONOutput accumulates output data and produces a valid JSON string
/// via its finalize() method.
@Suite("JSONOutput")
struct JSONOutputTests {

    @Test("type exists")
    func jsonOutputTypeExists() {
        let _ = JSONOutput.self
    }

    @Test("conforms to OutputProtocol")
    func jsonOutputConformsToOutputProtocol() {
        let output = JSONOutput()
        let _: OutputProtocol = output
    }

    @Test("finalize produces valid JSON")
    func jsonOutputFinalizeProducesValidJSON() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let json = output.finalize()

        let jsonData = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: jsonData)
        #expect(parsed != nil)
    }

    @Test("finalize contains runId")
    func jsonOutputFinalizeContainsRunId() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let json = output.finalize()
        let dict = parseJSON(json)

        #expect(dict?["runId"] as? String == "20260510-abc123")
    }

    @Test("finalize contains task")
    func jsonOutputFinalizeContainsTask() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-abc123", task: "Open Calculator", mode: "plan_execute")

        let json = output.finalize()
        let dict = parseJSON(json)

        #expect(dict?["task"] as? String == "Open Calculator")
    }

    @Test("finalize contains steps")
    func jsonOutputFinalizeContainsSteps() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")

        let step = ExecutedStep(
            stepIndex: 0, tool: "launch_app", parameters: ["app_name": .string("Calculator")],
            result: "{\"pid\": 1234}", success: true, timestamp: Date()
        )
        output.displayStepResult(step)

        let json = output.finalize()
        let dict = parseJSON(json)

        let steps = dict?["steps"] as? [[String: Any]]
        #expect(steps != nil)
        #expect(steps?.count == 1)
    }

    @Test("finalize contains summary")
    func jsonOutputFinalizeContainsSummary() {
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

        #expect(dict?["summary"] as? [String: Any] != nil)
    }

    @Test("steps array reflects executed steps")
    func jsonOutputStepsArrayReflectsExecutedSteps() {
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

        #expect(steps?.count == 2)
    }

    @Test("summary computes totalSteps")
    func jsonOutputSummaryComputesTotalSteps() {
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

        #expect(summary?["totalSteps"] as? Int == 1)
    }

    @Test("summary computes successfulSteps")
    func jsonOutputSummaryComputesSuccessfulSteps() {
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

        #expect(summary?["successfulSteps"] as? Int == 1)
    }

    @Test("summary computes failedSteps")
    func jsonOutputSummaryComputesFailedSteps() {
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

        #expect(summary?["failedSteps"] as? Int == 1)
    }

    @Test("displayRunStart stores run info")
    func jsonOutputDisplayRunStartStoresRunInfo() {
        let output = JSONOutput()
        output.displayRunStart(runId: "20260510-xyz789", task: "Calculate 17*23", mode: "plan_execute")

        let json = output.finalize()
        let dict = parseJSON(json)

        #expect(dict?["runId"] as? String == "20260510-xyz789")
        #expect(dict?["task"] as? String == "Calculate 17*23")
        #expect(dict?["mode"] as? String == "plan_execute")
    }

    @Test("displayError records error")
    func jsonOutputDisplayErrorRecordsError() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")
        output.displayError(.planningFailed(reason: "LLM timeout"))

        let json = output.finalize()
        let dict = parseJSON(json)

        let errors = dict?["errors"] as? [[String: Any]]
        #expect(errors != nil)
        #expect((errors?.count ?? 0) > 0)
    }

    @Test("displayStateChange records transition")
    func jsonOutputDisplayStateChangeRecordsTransition() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")
        output.displayStateChange(from: .planning, to: .executing)

        let json = output.finalize()
        let dict = parseJSON(json)

        let transitions = dict?["stateTransitions"] as? [[String: Any]]
        #expect(transitions != nil)
        #expect((transitions?.count ?? 0) > 0)
    }

    @Test("displayVerificationResult records result")
    func jsonOutputDisplayVerificationResultRecordsResult() {
        let output = JSONOutput()
        output.displayRunStart(runId: "test", task: "test", mode: "test")
        output.displayVerificationResult(.done(reason: "Task complete"))

        let json = output.finalize()
        let dict = parseJSON(json)

        let results = dict?["verificationResults"] as? [[String: Any]]
        #expect(results != nil)
        #expect((results?.count ?? 0) > 0)
    }

    private func parseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
