import Foundation

struct RunContext: Codable, Equatable {
    let planId: UUID
    var currentState: RunState
    var currentStepIndex: Int
    var executedSteps: [ExecutedStep]
    var replanCount: Int
    var config: AxionConfig
}
