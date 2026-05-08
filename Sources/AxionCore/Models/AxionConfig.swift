import Foundation

struct AxionConfig: Equatable {
    var apiKey: String?
    var model: String
    var maxSteps: Int
    var maxBatches: Int
    var maxReplanRetries: Int
    var traceEnabled: Bool
    var sharedSeatMode: Bool

    static let `default` = AxionConfig(
        apiKey: nil,
        model: "claude-sonnet-4-20250514",
        maxSteps: 20,
        maxBatches: 6,
        maxReplanRetries: 3,
        traceEnabled: true,
        sharedSeatMode: true
    )
}

extension AxionConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case model, maxSteps, maxBatches, maxReplanRetries, traceEnabled, sharedSeatMode
    }
}
