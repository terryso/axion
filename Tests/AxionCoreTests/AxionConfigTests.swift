import XCTest
@testable import AxionCore

final class AxionConfigTests: XCTestCase {

    // MARK: - camelCase JSON Output

    func test_config_codable_outputIsCamelCase() throws {
        let config = AxionConfig(
            apiKey: nil,
            model: "claude-sonnet-4-20250514",
            maxSteps: 20,
            maxBatches: 6,
            maxReplanRetries: 3,
            traceEnabled: true,
            sharedSeatMode: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify camelCase keys (not snake_case)
        XCTAssertNotNil(json["maxSteps"])
        XCTAssertNotNil(json["maxBatches"])
        XCTAssertNotNil(json["maxReplanRetries"])
        XCTAssertNotNil(json["traceEnabled"])
        XCTAssertNotNil(json["sharedSeatMode"])
        XCTAssertNotNil(json["model"])

        // Verify no snake_case keys
        XCTAssertNil(json["max_steps"])
        XCTAssertNil(json["max_batches"])
        XCTAssertNil(json["max_replan_retries"])
        XCTAssertNil(json["trace_enabled"])
        XCTAssertNil(json["shared_seat_mode"])
    }

    func test_config_codable_roundTrip() throws {
        let config = AxionConfig(
            apiKey: "sk-test-key",
            model: "claude-opus-4-20250514",
            maxSteps: 30,
            maxBatches: 10,
            maxReplanRetries: 5,
            traceEnabled: false,
            sharedSeatMode: false
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)

        XCTAssertEqual(decoded.apiKey, "sk-test-key")
        XCTAssertEqual(decoded.model, "claude-opus-4-20250514")
        XCTAssertEqual(decoded.maxSteps, 30)
        XCTAssertEqual(decoded.maxBatches, 10)
        XCTAssertEqual(decoded.maxReplanRetries, 5)
        XCTAssertFalse(decoded.traceEnabled)
        XCTAssertFalse(decoded.sharedSeatMode)
    }

    // MARK: - Default Values

    func test_config_defaultValues() {
        let config = AxionConfig.default

        XCTAssertNil(config.apiKey)
        XCTAssertEqual(config.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(config.maxSteps, 20)
        XCTAssertEqual(config.maxBatches, 6)
        XCTAssertEqual(config.maxReplanRetries, 3)
        XCTAssertTrue(config.traceEnabled)
        XCTAssertTrue(config.sharedSeatMode)
    }

    func test_config_apiKeyNil_notEncoded() throws {
        let config = AxionConfig.default
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // apiKey is nil, should not appear in JSON
        XCTAssertNil(json["apiKey"])
    }

    // MARK: - Partial JSON Decoding (defaults fill in)

    func test_config_partialJson_onlyApiKey_fillsDefaults() throws {
        let json = """
        {"apiKey": "sk-test"}
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(AxionConfig.self, from: data)

        XCTAssertEqual(config.apiKey, "sk-test")
        XCTAssertEqual(config.model, AxionConfig.default.model)
        XCTAssertEqual(config.maxSteps, AxionConfig.default.maxSteps)
        XCTAssertEqual(config.maxBatches, AxionConfig.default.maxBatches)
        XCTAssertEqual(config.maxReplanRetries, AxionConfig.default.maxReplanRetries)
        XCTAssertEqual(config.traceEnabled, AxionConfig.default.traceEnabled)
        XCTAssertEqual(config.sharedSeatMode, AxionConfig.default.sharedSeatMode)
        XCTAssertEqual(config.provider, .anthropic)
    }

    func test_config_partialJson_onlyOverridesChanged() throws {
        let json = """
        {"maxSteps": 50, "traceEnabled": false}
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(AxionConfig.self, from: data)

        XCTAssertEqual(config.maxSteps, 50)
        XCTAssertFalse(config.traceEnabled)
        XCTAssertNil(config.apiKey)
        XCTAssertEqual(config.model, AxionConfig.default.model)
        XCTAssertEqual(config.maxBatches, AxionConfig.default.maxBatches)
    }

    func test_config_emptyJson_decodesToDefaults() throws {
        let json = "{}"
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(AxionConfig.self, from: data)

        XCTAssertEqual(config.model, AxionConfig.default.model)
        XCTAssertEqual(config.maxSteps, AxionConfig.default.maxSteps)
        XCTAssertEqual(config.provider, .anthropic)
        XCTAssertNil(config.apiKey)
    }

    // MARK: - LLMProvider

    func test_llmProvider_anthropic_rawValue() {
        XCTAssertEqual(LLMProvider.anthropic.rawValue, "anthropic")
    }

    func test_llmProvider_openai_rawValue() {
        XCTAssertEqual(LLMProvider.openai.rawValue, "openai")
    }

    func test_llmProvider_codableRoundTrip_anthropic() throws {
        let provider = LLMProvider.anthropic
        let data = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(LLMProvider.self, from: data)
        XCTAssertEqual(decoded, .anthropic)
    }

    func test_llmProvider_codableRoundTrip_openai() throws {
        let provider = LLMProvider.openai
        let data = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(LLMProvider.self, from: data)
        XCTAssertEqual(decoded, .openai)
    }

    func test_llmProvider_jsonString_anthropic() throws {
        let data = try JSONEncoder().encode(LLMProvider.anthropic)
        let str = String(data: data, encoding: .utf8)
        XCTAssertEqual(str, "\"anthropic\"")
    }

    func test_llmProvider_jsonString_openai() throws {
        let data = try JSONEncoder().encode(LLMProvider.openai)
        let str = String(data: data, encoding: .utf8)
        XCTAssertEqual(str, "\"openai\"")
    }

    // MARK: - Custom Init

    func test_config_customInit_allParameters() {
        let config = AxionConfig(
            apiKey: "sk-key",
            provider: .openai,
            baseURL: "https://custom.api.com",
            model: "gpt-4",
            maxSteps: 50,
            maxBatches: 10,
            maxReplanRetries: 5,
            traceEnabled: false,
            sharedSeatMode: false
        )
        XCTAssertEqual(config.apiKey, "sk-key")
        XCTAssertEqual(config.provider, .openai)
        XCTAssertEqual(config.baseURL, "https://custom.api.com")
        XCTAssertEqual(config.model, "gpt-4")
        XCTAssertEqual(config.maxSteps, 50)
        XCTAssertEqual(config.maxBatches, 10)
        XCTAssertEqual(config.maxReplanRetries, 5)
        XCTAssertFalse(config.traceEnabled)
        XCTAssertFalse(config.sharedSeatMode)
    }

    func test_config_customInit_defaultParameters() {
        let config = AxionConfig(apiKey: "key")
        XCTAssertEqual(config.apiKey, "key")
        XCTAssertEqual(config.provider, .anthropic)
        XCTAssertNil(config.baseURL)
        XCTAssertEqual(config.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(config.maxSteps, 20)
    }

    // MARK: - Equality

    func test_config_equality_sameConfigs() {
        let a = AxionConfig(apiKey: "key", maxSteps: 10)
        let b = AxionConfig(apiKey: "key", maxSteps: 10)
        XCTAssertEqual(a, b)
    }

    func test_config_equality_differentConfigs() {
        let a = AxionConfig(apiKey: "key1", maxSteps: 10)
        let b = AxionConfig(apiKey: "key2", maxSteps: 10)
        XCTAssertNotEqual(a, b)
    }

    func test_config_equality_differentProvider() {
        let a = AxionConfig(apiKey: "key", provider: .anthropic)
        let b = AxionConfig(apiKey: "key", provider: .openai)
        XCTAssertNotEqual(a, b)
    }

    func test_config_equality_differentBaseURL() {
        let a = AxionConfig(apiKey: "key", baseURL: "https://a.com")
        let b = AxionConfig(apiKey: "key", baseURL: "https://b.com")
        XCTAssertNotEqual(a, b)
    }

    func test_config_equality_nilVsNotNil() {
        let a = AxionConfig(apiKey: nil, maxSteps: 20)
        let b = AxionConfig(apiKey: "key", maxSteps: 20)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Codable with provider

    func test_config_codable_withProvider() throws {
        let config = AxionConfig(apiKey: "key", provider: .openai)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)
        XCTAssertEqual(decoded.provider, .openai)
    }

    func test_config_codable_withBaseURL() throws {
        let config = AxionConfig(apiKey: "key", baseURL: "https://proxy.example.com")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)
        XCTAssertEqual(decoded.baseURL, "https://proxy.example.com")
    }

    func test_config_codable_nilBaseURL_notInJson() throws {
        let config = AxionConfig(apiKey: "key")
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["baseURL"])
    }
}
