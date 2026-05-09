import Foundation

public struct RunContext: Codable, Equatable {
    public let planId: UUID
    public var currentState: RunState
    public var currentStepIndex: Int
    public var executedSteps: [ExecutedStep]
    public var replanCount: Int
    public var config: AxionConfig

    public init(planId: UUID, currentState: RunState, currentStepIndex: Int, executedSteps: [ExecutedStep], replanCount: Int, config: AxionConfig) {
        self.planId = planId
        self.currentState = currentState
        self.currentStepIndex = currentStepIndex
        self.executedSteps = executedSteps
        self.replanCount = replanCount
        self.config = config
    }
}
