import Foundation

protocol OutputProtocol {
    func displayPlan(_ plan: Plan)
    func displayStepResult(_ executedStep: ExecutedStep)
    func displayStateChange(from oldState: RunState, to newState: RunState)
    func displayError(_ error: AxionError)
    func displaySummary(context: RunContext)
}
