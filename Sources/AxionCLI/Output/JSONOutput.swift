import Foundation

import AxionCore

// MARK: - JSONOutput

/// Accumulates execution data and produces a single structured JSON output via `finalize()`.
/// Designed for `--json` mode where the terminal shows only the final JSON result.
///
/// OutputProtocol methods collect data without printing. `finalize()` serializes
/// everything into a formatted JSON string containing runId, task, steps, errors,
/// stateTransitions, verificationResults, and summary.
final class JSONOutput: OutputProtocol {

    // MARK: - Accumulated State

    private var runId: String?
    private var task: String?
    private var mode: String?
    private var steps: [[String: Any]] = []
    private var stateTransitions: [[String: String]] = []
    private var errors: [[String: String]] = []
    private var verificationResults: [[String: String]] = []
    private var replanInfo: [[String: Any]] = []
    private var summaryData: [String: Any]?

    init() {}

    // MARK: - OutputProtocol — New Methods (Story 3-5)

    func displayRunStart(runId: String, task: String, mode: String) {
        self.runId = runId
        self.task = task
        self.mode = mode
    }

    func displayReplan(attempt: Int, maxRetries: Int, reason: String) {
        replanInfo.append([
            "attempt": attempt,
            "maxRetries": maxRetries,
            "reason": reason
        ])
    }

    func displayVerificationResult(_ result: VerificationResult) {
        var entry: [String: String] = ["state": result.state.rawValue]
        if let reason = result.reason {
            entry["reason"] = reason
        }
        verificationResults.append(entry)
    }

    // MARK: - OutputProtocol — Existing Methods

    func displayPlan(_ plan: Plan) {
        // No data to accumulate for plan in JSON output
    }

    func displayStepResult(_ executedStep: ExecutedStep) {
        steps.append([
            "index": executedStep.stepIndex,
            "tool": executedStep.tool,
            "success": executedStep.success,
            "result": executedStep.result,
            "durationMs": 0
        ])
    }

    func displayStateChange(from oldState: RunState, to newState: RunState) {
        stateTransitions.append([
            "from": oldState.rawValue,
            "to": newState.rawValue
        ])
    }

    func displayError(_ error: AxionError) {
        let payload = error.errorPayload
        errors.append([
            "error": payload.error,
            "message": payload.message
        ])
    }

    func displaySummary(context: RunContext) {
        let totalSteps = context.executedSteps.count
        let successfulSteps = context.executedSteps.filter { $0.success }.count
        let failedSteps = totalSteps - successfulSteps

        // Calculate duration from step timestamps
        let durationMs: Int
        if let first = context.executedSteps.first?.timestamp,
           let last = context.executedSteps.last?.timestamp {
            durationMs = Int(last.timeIntervalSince(first) * 1000)
        } else {
            durationMs = 0
        }

        summaryData = [
            "totalSteps": totalSteps,
            "successfulSteps": successfulSteps,
            "failedSteps": failedSteps,
            "durationMs": durationMs,
            "replanCount": context.replanCount
        ]
    }

    // MARK: - Finalize

    /// Serializes all accumulated data into a formatted JSON string.
    /// This is the single output point for `--json` mode.
    func finalize() -> String {
        var result: [String: Any] = [:]

        result["runId"] = runId ?? ""
        result["task"] = task ?? ""
        result["mode"] = mode ?? ""
        result["state"] = "done"
        result["steps"] = steps
        result["stateTransitions"] = stateTransitions
        result["errors"] = errors
        result["verificationResults"] = verificationResults
        result["replanInfo"] = replanInfo

        if let summary = summaryData {
            result["summary"] = summary
        } else {
            result["summary"] = [
                "totalSteps": steps.count,
                "successfulSteps": steps.filter { $0["success"] as? Bool == true }.count,
                "failedSteps": steps.filter { $0["success"] as? Bool == false }.count,
                "durationMs": 0,
                "replanCount": 0
            ] as [String: Any]
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys, .prettyPrinted]
        ) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
