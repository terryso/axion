import Foundation

public enum LLMProvider: String, Sendable, Equatable, Codable {
    case anthropic
    case openai
}

public struct AxionConfig: Equatable, Sendable {
    public var apiKey: String?
    public var provider: LLMProvider
    public var baseURL: String?
    public var model: String
    public var maxSteps: Int
    public var maxBatches: Int
    public var maxReplanRetries: Int
    public var traceEnabled: Bool
    public var sharedSeatMode: Bool
    public var maxModelCalls: Int?
    public var maxScreenshots: Int?
    public var reviewMemoryInterval: Int?
    public var reviewSkillInterval: Int?
    public var reviewMinMessages: Int?
    public var reviewModel: String?

    public static let `default` = AxionConfig(
        apiKey: nil,
        provider: .anthropic,
        baseURL: nil,
        model: "claude-sonnet-4-20250514",
        maxSteps: 20,
        maxBatches: 6,
        maxReplanRetries: 3,
        traceEnabled: true,
        sharedSeatMode: false,
        maxModelCalls: nil,
        maxScreenshots: nil,
        reviewMemoryInterval: nil,
        reviewSkillInterval: nil,
        reviewMinMessages: nil,
        reviewModel: nil
    )

    public init(
        apiKey: String?,
        provider: LLMProvider = .anthropic,
        baseURL: String? = nil,
        model: String = "claude-sonnet-4-20250514",
        maxSteps: Int = 20,
        maxBatches: Int = 6,
        maxReplanRetries: Int = 3,
        traceEnabled: Bool = true,
        sharedSeatMode: Bool = false,
        maxModelCalls: Int? = nil,
        maxScreenshots: Int? = nil,
        reviewMemoryInterval: Int? = nil,
        reviewSkillInterval: Int? = nil,
        reviewMinMessages: Int? = nil,
        reviewModel: String? = nil
    ) {
        self.apiKey = apiKey
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.maxSteps = maxSteps
        self.maxBatches = maxBatches
        self.maxReplanRetries = maxReplanRetries
        self.traceEnabled = traceEnabled
        self.sharedSeatMode = sharedSeatMode
        self.maxModelCalls = maxModelCalls
        self.maxScreenshots = maxScreenshots
        self.reviewMemoryInterval = reviewMemoryInterval
        self.reviewSkillInterval = reviewSkillInterval
        self.reviewMinMessages = reviewMinMessages
        self.reviewModel = reviewModel
    }
}

extension AxionConfig: Codable {
    public enum CodingKeys: String, CodingKey {
        case apiKey, provider, baseURL, model, maxSteps, maxBatches, maxReplanRetries, traceEnabled, sharedSeatMode, maxModelCalls, maxScreenshots
        case reviewMemoryInterval, reviewSkillInterval, reviewMinMessages, reviewModel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        provider = try c.decodeIfPresent(LLMProvider.self, forKey: .provider) ?? Self.default.provider
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? Self.default.model
        maxSteps = try c.decodeIfPresent(Int.self, forKey: .maxSteps) ?? Self.default.maxSteps
        maxBatches = try c.decodeIfPresent(Int.self, forKey: .maxBatches) ?? Self.default.maxBatches
        maxReplanRetries = try c.decodeIfPresent(Int.self, forKey: .maxReplanRetries) ?? Self.default.maxReplanRetries
        traceEnabled = try c.decodeIfPresent(Bool.self, forKey: .traceEnabled) ?? Self.default.traceEnabled
        sharedSeatMode = try c.decodeIfPresent(Bool.self, forKey: .sharedSeatMode) ?? Self.default.sharedSeatMode
        maxModelCalls = try c.decodeIfPresent(Int.self, forKey: .maxModelCalls) ?? Self.default.maxModelCalls
        maxScreenshots = try c.decodeIfPresent(Int.self, forKey: .maxScreenshots) ?? Self.default.maxScreenshots
        reviewMemoryInterval = try c.decodeIfPresent(Int.self, forKey: .reviewMemoryInterval)
        reviewSkillInterval = try c.decodeIfPresent(Int.self, forKey: .reviewSkillInterval)
        reviewMinMessages = try c.decodeIfPresent(Int.self, forKey: .reviewMinMessages)
        reviewModel = try c.decodeIfPresent(String.self, forKey: .reviewModel)
    }
}
