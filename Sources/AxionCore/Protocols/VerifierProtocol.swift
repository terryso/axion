import Foundation

public protocol VerifierProtocol {
    func verify(plan: Plan, executedSteps: [ExecutedStep], context: RunContext) async throws -> VerificationResult
}
