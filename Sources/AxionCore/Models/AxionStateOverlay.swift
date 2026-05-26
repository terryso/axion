import Foundation

public struct AxionStateOverlay: Codable, Sendable {
    public let status: String
    public let totalSteps: Int
    public let durationMs: Int?
    public let updatedAt: String

    public init(status: String, totalSteps: Int, durationMs: Int?, updatedAt: String) {
        self.status = status
        self.totalSteps = totalSteps
        self.durationMs = durationMs
        self.updatedAt = updatedAt
    }
}
