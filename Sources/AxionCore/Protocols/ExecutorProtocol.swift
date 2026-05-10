import Foundation

public protocol ExecutorProtocol {
    func executeStep(_ step: Step, context: RunContext) async throws -> ExecutedStep
}
