import Foundation
import OpenAgentSDK

// MARK: - BudgetCheckResult

enum BudgetCheckResult: Sendable, Equatable {
    case ok
    case modelCallsExceeded(limit: Int)
    case screenshotsExceeded(limit: Int)
}

// MARK: - CostSummary

struct CostSummary: Sendable {
    let modelCalls: Int
    let totalTokens: Int
    let estimatedCostUsd: Double
    let screenshotCount: Int
    let costBreakdown: [String: ModelCostEntry]
}

// MARK: - ModelCostEntry

struct ModelCostEntry: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCostUsd: Double
}

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

// MARK: - CostTracker

actor CostTracker {

    private var modelCallCount: Int = 0
    private var screenshotCount: Int = 0
    private let maxModelCalls: Int?
    private let maxScreenshots: Int?
    private var totalInputTokens: Int = 0
    private var totalOutputTokens: Int = 0
    private var estimatedCostUsd: Double = 0.0
    private var costBreakdown: [String: ModelCostEntry] = [:]

    init(maxModelCalls: Int? = nil, maxScreenshots: Int? = nil) {
        self.maxModelCalls = maxModelCalls
        self.maxScreenshots = maxScreenshots
    }

    /// Record an LLM model call and check budget.
    /// Returns `.modelCallsExceeded` if the limit was reached by this call.
    func recordModelCall(model: String) -> BudgetCheckResult {
        modelCallCount += 1

        if let limit = maxModelCalls, modelCallCount >= limit {
            return .modelCallsExceeded(limit: limit)
        }
        return .ok
    }

    /// Record a screenshot call and check budget.
    /// Returns `.screenshotsExceeded` if the limit was reached by this call.
    func recordScreenshot() -> BudgetCheckResult {
        screenshotCount += 1

        if let limit = maxScreenshots, screenshotCount >= limit {
            return .screenshotsExceeded(limit: limit)
        }
        return .ok
    }

    /// Finalize cost data using SDK-provided precise values from the .result message.
    func finalizeWithSDKData(
        usage: TokenUsage?,
        totalCostUsd: Double,
        costBreakdown: [CostBreakdownEntry]
    ) {
        if let usage {
            self.totalInputTokens = usage.inputTokens
            self.totalOutputTokens = usage.outputTokens
        }
        self.estimatedCostUsd = totalCostUsd
        for entry in costBreakdown {
            self.costBreakdown[entry.model] = ModelCostEntry(
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                estimatedCostUsd: entry.costUsd
            )
        }
    }

    /// Return current cost summary.
    func getSummary() -> CostSummary {
        CostSummary(
            modelCalls: modelCallCount,
            totalTokens: totalInputTokens + totalOutputTokens,
            estimatedCostUsd: estimatedCostUsd,
            screenshotCount: screenshotCount,
            costBreakdown: costBreakdown
        )
    }

    /// Return cost telemetry for API responses.
    func getTelemetry() -> CostTelemetry {
        let summary = getSummary()
        return CostTelemetry(
            modelCalls: summary.modelCalls,
            totalTokens: summary.totalTokens,
            estimatedCostUsd: summary.estimatedCostUsd,
            screenshotCount: summary.screenshotCount
        )
    }

    var currentModelCallCount: Int { modelCallCount }
    var currentScreenshotCount: Int { screenshotCount }
}
