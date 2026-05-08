import Foundation

protocol PlannerProtocol {
    func createPlan(for task: String, context: RunContext) async throws -> Plan
    func replan(from currentPlan: Plan, executedSteps: [ExecutedStep], failureReason: String, context: RunContext) async throws -> Plan
}
