// MARK: - CostTelemetry

struct CostTelemetry: Codable, Equatable, Sendable {
    let modelCalls: Int
    let totalTokens: Int
    let estimatedCostUsd: Double
    let screenshotCount: Int

    enum CodingKeys: String, CodingKey {
        case modelCalls = "model_calls"
        case totalTokens = "total_tokens"
        case estimatedCostUsd = "estimated_cost_usd"
        case screenshotCount = "screenshot_count"
    }
}
