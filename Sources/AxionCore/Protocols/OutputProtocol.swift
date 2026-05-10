import Foundation

public protocol OutputProtocol {
    // MARK: - Existing Methods (preserved from Stories 3-3/3-4)

    func displayPlan(_ plan: Plan)
    func displayStepResult(_ executedStep: ExecutedStep)
    func displayStateChange(from oldState: RunState, to newState: RunState)
    func displayError(_ error: AxionError)
    func displaySummary(context: RunContext)

    // MARK: - New Methods (Story 3-5)

    /// Displays run startup information: execution mode, run ID, and task description.
    func displayRunStart(runId: String, task: String, mode: String)

    /// Displays replan attempt information.
    func displayReplan(attempt: Int, maxRetries: Int, reason: String)

    /// Displays the result of task verification.
    func displayVerificationResult(_ result: VerificationResult)
}
