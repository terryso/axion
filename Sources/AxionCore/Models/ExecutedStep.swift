import Foundation

struct ExecutedStep: Codable, Equatable {
    let stepIndex: Int
    let tool: String
    let parameters: [String: Value]
    let result: String
    let success: Bool
    let timestamp: Date
}
