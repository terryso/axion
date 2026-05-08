import Foundation

struct Plan: Codable, Equatable {
    let id: UUID
    let task: String
    let steps: [Step]
    let stopWhen: [StopCondition]
    let maxRetries: Int
}
