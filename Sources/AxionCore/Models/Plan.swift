import Foundation

public struct Plan: Codable, Equatable {
    public let id: UUID
    public let task: String
    public let steps: [Step]
    public let stopWhen: [StopCondition]
    public let maxRetries: Int

    public init(id: UUID, task: String, steps: [Step], stopWhen: [StopCondition], maxRetries: Int) {
        self.id = id
        self.task = task
        self.steps = steps
        self.stopWhen = stopWhen
        self.maxRetries = maxRetries
    }
}
