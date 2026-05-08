import Foundation

protocol ExecutorProtocol {
    func executeStep(_ step: Step, context: RunContext) async throws -> ExecutedStep
}
