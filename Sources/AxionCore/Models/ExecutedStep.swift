import Foundation

public struct ExecutedStep: Codable, Equatable {
    public let stepIndex: Int
    public let tool: String
    public let parameters: [String: Value]
    public let result: String
    public let success: Bool
    public let timestamp: Date

    public init(stepIndex: Int, tool: String, parameters: [String: Value], result: String, success: Bool, timestamp: Date) {
        self.stepIndex = stepIndex
        self.tool = tool
        self.parameters = parameters
        self.result = result
        self.success = success
        self.timestamp = timestamp
    }
}
