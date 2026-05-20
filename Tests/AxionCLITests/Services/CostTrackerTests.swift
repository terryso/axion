import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI
@testable import AxionCore

@Suite("CostTracker Tests")
struct CostTrackerTests {

    // MARK: - Screenshot Counting

    @Test("recordScreenshot increments count and returns ok when under limit")
    func test_recordScreenshot_incrementsAndOk() async {
        let tracker = CostTracker(maxScreenshots: 5)
        let result = await tracker.recordScreenshot()
        #expect(result == .ok)
        let count = await tracker.currentScreenshotCount
        #expect(count == 1)
    }

    @Test("recordScreenshot returns exceeded when limit reached")
    func test_recordScreenshot_exceeded() async {
        let tracker = CostTracker(maxScreenshots: 2)
        let r1 = await tracker.recordScreenshot()
        #expect(r1 == .ok)
        let r2 = await tracker.recordScreenshot()
        #expect(r2 == .screenshotsExceeded(limit: 2))
    }

    @Test("recordScreenshot nil limit means unlimited")
    func test_recordScreenshot_nilLimit() async {
        let tracker = CostTracker(maxScreenshots: nil)
        for _ in 0..<50 {
            let result = await tracker.recordScreenshot()
            #expect(result == .ok)
        }
        let count = await tracker.currentScreenshotCount
        #expect(count == 50)
    }

    // MARK: - CostSummary

    @Test("getSummary returns correct initial summary")
    func test_getSummary_initial() async {
        let tracker = CostTracker()
        let summary = await tracker.getSummary()
        #expect(summary.modelCalls == 0)
        #expect(summary.totalTokens == 0)
        #expect(summary.estimatedCostUsd == 0.0)
        #expect(summary.screenshotCount == 0)
        #expect(summary.costBreakdown.isEmpty)
    }

    @Test("getSummary reflects recorded screenshots")
    func test_getSummary_afterCalls() async {
        let tracker = CostTracker()
        _ = await tracker.recordScreenshot()
        _ = await tracker.recordScreenshot()
        let summary = await tracker.getSummary()
        #expect(summary.screenshotCount == 2)
    }

    // MARK: - finalizeWithSDKData

    @Test("finalizeWithSDKData updates cost data from SDK")
    func test_finalizeWithSDKData() async {
        let tracker = CostTracker()

        let usage = TokenUsage(inputTokens: 1000, outputTokens: 500)
        let breakdown = [CostBreakdownEntry(model: "claude-sonnet-4-6", inputTokens: 1000, outputTokens: 500, costUsd: 0.012)]

        await tracker.finalizeWithSDKData(usage: usage, totalCostUsd: 0.012, costBreakdown: breakdown)

        let summary = await tracker.getSummary()
        #expect(summary.modelCalls == 1)
        #expect(summary.totalTokens == 1500)
        #expect(summary.estimatedCostUsd == 0.012)
        #expect(summary.costBreakdown.count == 1)
        #expect(summary.costBreakdown["claude-sonnet-4-6"]?.inputTokens == 1000)
        #expect(summary.costBreakdown["claude-sonnet-4-6"]?.outputTokens == 500)
    }

    @Test("finalizeWithSDKData with multiple models counts all")
    func test_finalizeWithSDKData_multipleModels() async {
        let tracker = CostTracker()

        let usage = TokenUsage(inputTokens: 2000, outputTokens: 1000)
        let breakdown = [
            CostBreakdownEntry(model: "claude-sonnet-4-6", inputTokens: 1500, outputTokens: 800, costUsd: 0.01),
            CostBreakdownEntry(model: "claude-opus-4-6", inputTokens: 500, outputTokens: 200, costUsd: 0.02),
        ]

        await tracker.finalizeWithSDKData(usage: usage, totalCostUsd: 0.03, costBreakdown: breakdown)

        let summary = await tracker.getSummary()
        #expect(summary.modelCalls == 2)
        #expect(summary.totalTokens == 3000)
        #expect(summary.estimatedCostUsd == 0.03)
    }

    // MARK: - CostTelemetry

    @Test("getTelemetry returns correct telemetry struct")
    func test_getTelemetry() async {
        let tracker = CostTracker()
        _ = await tracker.recordScreenshot()

        let usage = TokenUsage(inputTokens: 500, outputTokens: 200)
        await tracker.finalizeWithSDKData(usage: usage, totalCostUsd: 0.005, costBreakdown: [])

        let telemetry = await tracker.getTelemetry()
        #expect(telemetry.totalTokens == 700)
        #expect(telemetry.estimatedCostUsd == 0.005)
        #expect(telemetry.screenshotCount == 1)
    }

    @Test("CostTelemetry Codable round-trip")
    func test_costTelemetry_roundTrip() throws {
        let original = CostTelemetry(
            modelCalls: 8,
            totalTokens: 45230,
            estimatedCostUsd: 0.12,
            screenshotCount: 3
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CostTelemetry.self, from: data)
        #expect(decoded == original)
    }

    @Test("CostTelemetry CodingKeys use snake_case")
    func test_costTelemetry_snakeCaseKeys() throws {
        let telemetry = CostTelemetry(modelCalls: 1, totalTokens: 100, estimatedCostUsd: 0.01, screenshotCount: 2)
        let data = try JSONEncoder().encode(telemetry)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["model_calls"] != nil)
        #expect(json["total_tokens"] != nil)
        #expect(json["estimated_cost_usd"] != nil)
        #expect(json["screenshot_count"] != nil)
    }
}

// MARK: - AxionConfig Tests

@Suite("AxionConfig Budget Fields Tests")
struct AxionConfigBudgetTests {

    @Test("AxionConfig new fields Codable round-trip with nil values")
    func test_config_roundTrip_nilBudgetFields() throws {
        let original = AxionConfig(
            apiKey: nil,
            maxModelCalls: nil,
            maxScreenshots: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)
        #expect(decoded.maxModelCalls == nil)
        #expect(decoded.maxScreenshots == nil)
        #expect(decoded == original)
    }

    @Test("AxionConfig new fields Codable round-trip with values")
    func test_config_roundTrip_withBudgetFields() throws {
        let original = AxionConfig(
            apiKey: nil,
            maxModelCalls: 10,
            maxScreenshots: 5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)
        #expect(decoded.maxModelCalls == 10)
        #expect(decoded.maxScreenshots == 5)
    }

    @Test("AxionConfig defaults have nil budget fields")
    func test_config_defaults_nilBudget() {
        let defaults = AxionConfig.default
        #expect(defaults.maxModelCalls == nil)
        #expect(defaults.maxScreenshots == nil)
    }

    @Test("AxionConfig decoding missing fields uses nil defaults")
    func test_config_decoding_missingFields_nil() throws {
        let json = """
        {"apiKey": null, "provider": "anthropic", "model": "claude-sonnet-4-20250514"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)
        #expect(decoded.maxModelCalls == nil)
        #expect(decoded.maxScreenshots == nil)
    }
}

// MARK: - AxionError Tests

@Suite("AxionError Budget Cases Tests")
struct AxionErrorBudgetTests {

    @Test("modelCallBudgetExceeded errorPayload format")
    func test_modelCallBudgetExceeded_errorPayload() {
        let error = AxionError.modelCallBudgetExceeded(calls: 10, limit: 10)
        let payload = error.errorPayload
        #expect(payload.error == "model_call_budget_exceeded")
        #expect(payload.message.contains("10"))
        #expect(payload.suggestion.contains("--max-model-calls"))
    }

    @Test("screenshotBudgetExceeded errorPayload format")
    func test_screenshotBudgetExceeded_errorPayload() {
        let error = AxionError.screenshotBudgetExceeded(count: 5, limit: 5)
        let payload = error.errorPayload
        #expect(payload.error == "screenshot_budget_exceeded")
        #expect(payload.message.contains("5"))
        #expect(payload.suggestion.contains("--max-screenshots"))
    }

    @Test("budget errors toToolResultJSON produces valid JSON")
    func test_budgetErrors_toToolResultJSON() {
        let error = AxionError.modelCallBudgetExceeded(calls: 10, limit: 10)
        let json = error.toToolResultJSON()
        #expect(json.contains("model_call_budget_exceeded"))
        #expect(json.contains("error"))
        #expect(json.contains("message"))
        #expect(json.contains("suggestion"))
    }
}
