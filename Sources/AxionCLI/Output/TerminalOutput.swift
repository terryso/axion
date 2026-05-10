import Foundation

import AxionCore

// MARK: - TerminalOutput

/// Outputs human-readable progress information to the terminal during task execution.
/// Uses an injectable `write` closure (defaults to `print`) for testability.
///
/// Format conventions:
/// - Every line is prefixed with `[axion]`
/// - Step progress: `步骤 {current}/{total}: {tool} — {status}`
/// - Status markers: `ok` (success), `x {reason}` (failure)
/// - No emoji — pure ASCII for terminal/pipeline compatibility
final class TerminalOutput: OutputProtocol {

    let write: (String) -> Void
    private var planStepsCount: Int = 0

    init(write: @escaping (String) -> Void = { print($0) }) {
        self.write = write
    }

    /// Writes a raw string directly without any prefix (for SDK streaming).
    func writeStream(_ text: String) {
        write(text)
    }

    // MARK: - OutputProtocol — New Methods (Story 3-5)

    func displayRunStart(runId: String, task: String, mode: String) {
        write("[axion] \u{6A21}\u{5F0F}: \(mode)")
        write("[axion] \u{8FD0}\u{884C} ID: \(runId)")
        write("[axion] \u{4EFB}\u{52A1}: \(task)")
    }

    func displayReplan(attempt: Int, maxRetries: Int, reason: String) {
        write("[axion] \u{6B63}\u{5728}\u{91CD}\u{89C4}\u{5212} (\(attempt)/\(maxRetries)): \(reason)")
    }

    func displayVerificationResult(_ result: VerificationResult) {
        switch result.state {
        case .done:
            let reason = result.reason ?? "\u{4EFB}\u{52A1}\u{5B8C}\u{6210}"
            write("[axion] \u{9A8C}\u{8BC1}: \(reason)")
        case .blocked:
            let reason = result.reason ?? "\u{4EFB}\u{52A1}\u{963B}\u{585E}"
            write("[axion] \u{9A8C}\u{8BC1}: \u{963B}\u{585E} — \(reason)")
        case .needsClarification:
            let reason = result.reason ?? "\u{9700}\u{8981}\u{8BF4}\u{660E}"
            write("[axion] \u{9A8C}\u{8BC1}: \u{9700}\u{8981}\u{8BF4}\u{660E} — \(reason)")
        default:
            if let reason = result.reason {
                write("[axion] \u{9A8C}\u{8BC1}: \(reason)")
            }
        }
    }

    // MARK: - OutputProtocol — Existing Methods

    func displayPlan(_ plan: Plan) {
        planStepsCount = plan.steps.count
        write("[axion] \u{89C4}\u{5212}\u{5B8C}\u{6210}: \(plan.steps.count) \u{4E2A}\u{6B65}\u{9AA4}")
    }

    func displayStepResult(_ executedStep: ExecutedStep) {
        let total = planStepsCount > 0 ? "\(planStepsCount)" : "?"
        let current = executedStep.stepIndex + 1
        let status: String
        if executedStep.success {
            status = "ok"
        } else {
            // Truncate result for display
            let snippet = String(executedStep.result.prefix(80))
            status = "x \(snippet)"
        }
        write("[axion] \u{6B65}\u{9AA4} \(current)/\(total): \(executedStep.tool) — \(status)")
    }

    func displayStateChange(from oldState: RunState, to newState: RunState) {
        let desc = stateDescription(newState)
        write("[axion] \u{6B63}\u{5728}\(desc)...")
    }

    func displayError(_ error: AxionError) {
        let payload = error.errorPayload
        write("[axion] \u{9519}\u{8BEF}: \(payload.message)")
    }

    func displaySummary(context: RunContext) {
        let totalSteps = context.executedSteps.count
        let replanCount = context.replanCount

        // Calculate duration from first and last step timestamps
        let durationStr: String
        if let first = context.executedSteps.first?.timestamp,
           let last = context.executedSteps.last?.timestamp {
            let interval = last.timeIntervalSince(first)
            durationStr = String(format: "%.1f", interval)
        } else {
            durationStr = "0.0"
        }

        write("[axion] \u{5B8C}\u{6210}。\(totalSteps) \u{6B65}，\u{8017}\u{65F6} \(durationStr) \u{79D2}，\u{91CD}\u{89C4}\u{5212} \(replanCount) \u{6B21}。")
    }

    // MARK: - Internal Helpers

    private func stateDescription(_ state: RunState) -> String {
        switch state {
        case .planning:
            return "\u{89C4}\u{5212}"
        case .executing:
            return "\u{6267}\u{884C}"
        case .verifying:
            return "\u{9A8C}\u{8BC1}"
        case .replanning:
            return "\u{91CD}\u{89C4}\u{5212}"
        case .done:
            return "\u{5B8C}\u{6210}"
        case .blocked:
            return "\u{963B}\u{585E}"
        case .needsClarification:
            return "\u{7B49}\u{5F85}\u{8BF4}\u{660E}"
        case .cancelled:
            return "\u{53D6}\u{6D88}"
        case .failed:
            return "\u{5931}\u{8D25}"
        }
    }
}
