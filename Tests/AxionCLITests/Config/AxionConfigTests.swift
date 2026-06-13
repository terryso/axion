import Foundation
import Testing
@testable import AxionCLI
import AxionCore

@Suite("AxionConfig")
struct AxionConfigTests {

    // MARK: - camelCase JSON Output

    @Test("config codable output is camelCase")
    func configCodableOutputIsCamelCase() throws {
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

        #expect(json["maxSteps"] != nil)
        #expect(json["maxBatches"] != nil)
        #expect(json["maxReplanRetries"] != nil)
        #expect(json["traceEnabled"] != nil)
        #expect(json["sharedSeatMode"] != nil)
        #expect(json["model"] != nil)

        #expect(json["max_steps"] == nil)
        #expect(json["max_batches"] == nil)
        #expect(json["max_replan_retries"] == nil)
        #expect(json["trace_enabled"] == nil)
        #expect(json["shared_seat_mode"] == nil)
    }

    @Test("config codable round trip")
    func configCodableRoundTrip() throws {
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

        #expect(decoded.apiKey == "sk-test-key")
        #expect(decoded.model == "claude-opus-4-20250514")
        #expect(decoded.maxSteps == 30)
        #expect(decoded.maxBatches == 10)
        #expect(decoded.maxReplanRetries == 5)
        #expect(!decoded.traceEnabled)
        #expect(!decoded.sharedSeatMode)
    }

    // MARK: - Default Values

    @Test("config default values")
    func configDefaultValues() {
        let config = AxionConfig.default

        #expect(config.apiKey == nil)
        #expect(config.model == "claude-sonnet-4-20250514")
        #expect(config.maxSteps == 20)
        #expect(config.maxBatches == 6)
        #expect(config.maxReplanRetries == 3)
        #expect(config.traceEnabled)
        #expect(!config.sharedSeatMode)
    }

    @Test("config apiKey nil not encoded")
    func configApiKeyNilNotEncoded() throws {
        let config = AxionConfig.default
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["apiKey"] == nil)
    }

    // MARK: - Partial JSON Decoding (defaults fill in)

    @Test("config partial json only apiKey fills defaults")
    func configPartialJsonOnlyApiKeyFillsDefaults() throws {
        let json = """
        {"apiKey": "sk-test"}
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(AxionConfig.self, from: data)

        #expect(config.apiKey == "sk-test")
        #expect(config.model == AxionConfig.default.model)
        #expect(config.maxSteps == AxionConfig.default.maxSteps)
        #expect(config.maxBatches == AxionConfig.default.maxBatches)
        #expect(config.maxReplanRetries == AxionConfig.default.maxReplanRetries)
        #expect(config.traceEnabled == AxionConfig.default.traceEnabled)
        #expect(config.sharedSeatMode == AxionConfig.default.sharedSeatMode)
        #expect(config.provider == .anthropic)
    }

    @Test("config partial json only overrides changed")
    func configPartialJsonOnlyOverridesChanged() throws {
        let json = """
        {"maxSteps": 50, "traceEnabled": false}
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(AxionConfig.self, from: data)

        #expect(config.maxSteps == 50)
        #expect(!config.traceEnabled)
        #expect(config.apiKey == nil)
        #expect(config.model == AxionConfig.default.model)
        #expect(config.maxBatches == AxionConfig.default.maxBatches)
    }

    @Test("config empty json decodes to defaults")
    func configEmptyJsonDecodesToDefaults() throws {
        let json = "{}"
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(AxionConfig.self, from: data)

        #expect(config.model == AxionConfig.default.model)
        #expect(config.maxSteps == AxionConfig.default.maxSteps)
        #expect(config.provider == .anthropic)
        #expect(config.apiKey == nil)
    }

    // MARK: - LLMProvider

    @Test("LLMProvider anthropic raw value")
    func llmProviderAnthropicRawValue() {
        #expect(LLMProvider.anthropic.rawValue == "anthropic")
    }

    @Test("LLMProvider openai raw value")
    func llmProviderOpenaiRawValue() {
        #expect(LLMProvider.openai.rawValue == "openai")
    }

    @Test("LLMProvider codable round trip anthropic")
    func llmProviderCodableRoundTripAnthropic() throws {
        let provider = LLMProvider.anthropic
        let data = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(LLMProvider.self, from: data)
        #expect(decoded == .anthropic)
    }

    @Test("LLMProvider codable round trip openai")
    func llmProviderCodableRoundTripOpenai() throws {
        let provider = LLMProvider.openai
        let data = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(LLMProvider.self, from: data)
        #expect(decoded == .openai)
    }

    @Test("LLMProvider json string anthropic")
    func llmProviderJsonStringAnthropic() throws {
        let data = try JSONEncoder().encode(LLMProvider.anthropic)
        let str = String(data: data, encoding: .utf8)
        #expect(str == "\"anthropic\"")
    }

    @Test("LLMProvider json string openai")
    func llmProviderJsonStringOpenai() throws {
        let data = try JSONEncoder().encode(LLMProvider.openai)
        let str = String(data: data, encoding: .utf8)
        #expect(str == "\"openai\"")
    }

    // MARK: - Custom Init

    @Test("config custom init all parameters")
    func configCustomInitAllParameters() {
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
        #expect(config.apiKey == "sk-key")
        #expect(config.provider == .openai)
        #expect(config.baseURL == "https://custom.api.com")
        #expect(config.model == "gpt-4")
        #expect(config.maxSteps == 50)
        #expect(config.maxBatches == 10)
        #expect(config.maxReplanRetries == 5)
        #expect(!config.traceEnabled)
        #expect(!config.sharedSeatMode)
    }

    @Test("config custom init default parameters")
    func configCustomInitDefaultParameters() {
        let config = AxionConfig(apiKey: "key")
        #expect(config.apiKey == "key")
        #expect(config.provider == .anthropic)
        #expect(config.baseURL == nil)
        #expect(config.model == "claude-sonnet-4-20250514")
        #expect(config.maxSteps == 20)
    }

    // MARK: - Equality

    @Test("config equality same configs")
    func configEqualitySameConfigs() {
        let a = AxionConfig(apiKey: "key", maxSteps: 10)
        let b = AxionConfig(apiKey: "key", maxSteps: 10)
        #expect(a == b)
    }

    @Test("config equality different configs")
    func configEqualityDifferentConfigs() {
        let a = AxionConfig(apiKey: "key1", maxSteps: 10)
        let b = AxionConfig(apiKey: "key2", maxSteps: 10)
        #expect(a != b)
    }

    @Test("config equality different provider")
    func configEqualityDifferentProvider() {
        let a = AxionConfig(apiKey: "key", provider: .anthropic)
        let b = AxionConfig(apiKey: "key", provider: .openai)
        #expect(a != b)
    }

    @Test("config equality different baseURL")
    func configEqualityDifferentBaseURL() {
        let a = AxionConfig(apiKey: "key", baseURL: "https://a.com")
        let b = AxionConfig(apiKey: "key", baseURL: "https://b.com")
        #expect(a != b)
    }

    @Test("config equality nil vs not nil")
    func configEqualityNilVsNotNil() {
        let a = AxionConfig(apiKey: nil, maxSteps: 20)
        let b = AxionConfig(apiKey: "key", maxSteps: 20)
        #expect(a != b)
    }

    // MARK: - Codable with provider

    @Test("config codable with provider")
    func configCodableWithProvider() throws {
        let config = AxionConfig(apiKey: "key", provider: .openai)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)
        #expect(decoded.provider == .openai)
    }

    @Test("config codable with baseURL")
    func configCodableWithBaseURL() throws {
        let config = AxionConfig(apiKey: "key", baseURL: "https://proxy.example.com")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)
        #expect(decoded.baseURL == "https://proxy.example.com")
    }

    @Test("config codable nil baseURL not in json")
    func configCodableNilBaseURLNotInJson() throws {
        let config = AxionConfig(apiKey: "key")
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["baseURL"] == nil)
    }

    // MARK: - Gateway Config

    @Test("gateway default values are nil (matching curator pattern)")
    func gatewayDefaultValues() {
        let config = AxionConfig.default
        #expect(config.gatewayEnabled == nil)
        #expect(config.gatewayCuratorIdleHours == nil)
        #expect(config.gatewayCuratorIntervalHours == nil)
        #expect(config.gatewayTaskTimeoutMinutes == nil)
        #expect(config.gatewayNotifyCuratorResults == nil)
    }

    @Test("gateway effective defaults applied via explicit config")
    func gatewayEffectiveDefaults() {
        let config = AxionConfig(
            apiKey: nil,
            gatewayEnabled: false,
            gatewayCuratorIdleHours: 2.0,
            gatewayCuratorIntervalHours: 168.0,
            gatewayTaskTimeoutMinutes: 10.0,
            gatewayNotifyCuratorResults: false
        )
        #expect(config.gatewayEnabled == false)
        #expect(config.gatewayCuratorIdleHours == 2.0)
        #expect(config.gatewayCuratorIntervalHours == 168.0)
        #expect(config.gatewayTaskTimeoutMinutes == 10.0)
        #expect(config.gatewayNotifyCuratorResults == false)
    }

    @Test("gateway partial JSON decode: missing keys decode to nil, not static defaults")
    func gatewayPartialJsonDecode() throws {
        let json = """
        {"gatewayCuratorIdleHours": 4.0}
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(AxionConfig.self, from: data)

        #expect(config.gatewayCuratorIdleHours == 4.0)
        #expect(config.gatewayEnabled == nil)
        #expect(config.gatewayCuratorIntervalHours == nil)
        #expect(config.gatewayTaskTimeoutMinutes == nil)
        #expect(config.gatewayNotifyCuratorResults == nil)
    }

    @Test("gateway fields Codable round-trip")
    func gatewayCodableRoundTrip() throws {
        let config = AxionConfig(
            apiKey: nil,
            gatewayEnabled: true,
            gatewayCuratorIdleHours: 5.0,
            gatewayCuratorIntervalHours: 72.0,
            gatewayTaskTimeoutMinutes: 30.0,
            gatewayNotifyCuratorResults: true
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)

        #expect(decoded.gatewayEnabled == true)
        #expect(decoded.gatewayCuratorIdleHours == 5.0)
        #expect(decoded.gatewayCuratorIntervalHours == 72.0)
        #expect(decoded.gatewayTaskTimeoutMinutes == 30.0)
        #expect(decoded.gatewayNotifyCuratorResults == true)
    }

    @Test("gateway nil fields are omitted from JSON output")
    func gatewayNilFieldsOmittedFromJson() throws {
        let config = AxionConfig(apiKey: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["gatewayEnabled"] == nil)
        #expect(json["gatewayCuratorIdleHours"] == nil)
        #expect(json["gatewayCuratorIntervalHours"] == nil)
        #expect(json["gatewayTaskTimeoutMinutes"] == nil)
        #expect(json["gatewayNotifyCuratorResults"] == nil)
    }

    @Test("gateway empty JSON decodes with all gateway fields as nil")
    func gatewayEmptyJsonDecodesToNil() throws {
        let json = "{}"
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(AxionConfig.self, from: data)

        #expect(config.gatewayEnabled == nil)
        #expect(config.gatewayCuratorIdleHours == nil)
        #expect(config.gatewayCuratorIntervalHours == nil)
        #expect(config.gatewayTaskTimeoutMinutes == nil)
        #expect(config.gatewayNotifyCuratorResults == nil)
    }

    // MARK: - Storage Config Integration

    @Test("AxionConfig storage falls back to default when absent")
    func axionConfigStorageDefault() throws {
        let json = "{\"apiKey\": \"k\"}".data(using: .utf8)!
        let cfg = try JSONDecoder().decode(AxionConfig.self, from: json)
        #expect(cfg.storage.largeFileThresholdBytes == 1_073_741_824)
    }

    @Test("AxionConfig storage decodes when present")
    func axionConfigStoragePresent() throws {
        let json = #"{"apiKey": "k", "storage": {"large_file_threshold_bytes": 200}}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(AxionConfig.self, from: json)
        #expect(cfg.storage.largeFileThresholdBytes == 200)
    }

    // MARK: - MCP Server Config

    @Test("AxionConfig mcpServers defaults to nil when absent")
    func axionConfigMcpServersAbsentDefaultsToNil() throws {
        let cfg = try JSONDecoder().decode(AxionConfig.self, from: Data(#"{"model":"custom"}"#.utf8))

        #expect(cfg.model == "custom")
        #expect(cfg.mcpServers == nil)
    }

    @Test("AxionConfig mcpServers decodes when present")
    func axionConfigMcpServersDecodesWhenPresent() throws {
        let json = """
        {
          "model": "custom",
          "mcpServers": {
            "my-server": {
              "type": "stdio",
              "command": "node",
              "args": ["server.js"],
              "env": {"FOO": "bar"}
            }
          }
        }
        """
        let cfg = try JSONDecoder().decode(AxionConfig.self, from: Data(json.utf8))

        #expect(cfg.model == "custom")
        #expect(cfg.mcpServers?["my-server"] == .stdio(
            command: "node",
            args: ["server.js"],
            env: ["FOO": "bar"]
        ))
    }

    @Test("AxionConfig bad mcpServers degrades to nil and preserves other config")
    func axionConfigBadMcpServersDegradesToNil() throws {
        let json = """
        {
          "model": "custom",
          "maxSteps": 42,
          "mcpServers": {
            "bad": {"type": "stdio"}
          }
        }
        """
        let cfg = try JSONDecoder().decode(AxionConfig.self, from: Data(json.utf8))

        #expect(cfg.model == "custom")
        #expect(cfg.maxSteps == 42)
        #expect(cfg.mcpServers == nil)
    }

    @Test("AxionConfig mcpServers codable round trip")
    func axionConfigMcpServersCodableRoundTrip() throws {
        let config = AxionConfig(
            apiKey: "key",
            mcpServers: [
                "sse-server": .sse(url: "http://localhost:8080/sse")
            ]
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AxionConfig.self, from: data)

        #expect(decoded.mcpServers == config.mcpServers)
    }
}
