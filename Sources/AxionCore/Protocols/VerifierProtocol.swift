import Foundation

protocol VerifierProtocol {
    func verify(step: ExecutedStep, expectedChange: String, context: RunContext) async throws -> Bool
}
