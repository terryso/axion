import Foundation

public protocol ExecutorProtocol {
    func executeStep(_ step: Step, context: RunContext) async throws -> ExecutedStep
    func executePlan(_ plan: Plan, context: RunContext) async throws -> (executedSteps: [ExecutedStep], context: RunContext)
}
