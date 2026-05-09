import Foundation

public struct AxionConfig: Equatable, Sendable {
    public var apiKey: String?
    public var model: String
    public var maxSteps: Int
    public var maxBatches: Int
    public var maxReplanRetries: Int
    public var traceEnabled: Bool
    public var sharedSeatMode: Bool

    public static let `default` = AxionConfig(
        apiKey: nil,
        model: "claude-sonnet-4-20250514",
        maxSteps: 20,
        maxBatches: 6,
        maxReplanRetries: 3,
        traceEnabled: true,
        sharedSeatMode: true
    )

    public init(
        apiKey: String?,
        model: String,
        maxSteps: Int,
        maxBatches: Int,
        maxReplanRetries: Int,
        traceEnabled: Bool,
        sharedSeatMode: Bool
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxSteps = maxSteps
        self.maxBatches = maxBatches
        self.maxReplanRetries = maxReplanRetries
        self.traceEnabled = traceEnabled
        self.sharedSeatMode = sharedSeatMode
    }
}

extension AxionConfig: Codable {
    public enum CodingKeys: String, CodingKey {
        case apiKey, model, maxSteps, maxBatches, maxReplanRetries, traceEnabled, sharedSeatMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? Self.default.model
        maxSteps = try c.decodeIfPresent(Int.self, forKey: .maxSteps) ?? Self.default.maxSteps
        maxBatches = try c.decodeIfPresent(Int.self, forKey: .maxBatches) ?? Self.default.maxBatches
        maxReplanRetries = try c.decodeIfPresent(Int.self, forKey: .maxReplanRetries) ?? Self.default.maxReplanRetries
        traceEnabled = try c.decodeIfPresent(Bool.self, forKey: .traceEnabled) ?? Self.default.traceEnabled
        sharedSeatMode = try c.decodeIfPresent(Bool.self, forKey: .sharedSeatMode) ?? Self.default.sharedSeatMode
    }
}
