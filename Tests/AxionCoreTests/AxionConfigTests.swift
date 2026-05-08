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

        // apiKey is excluded from Codable (security: read from Keychain only)
        XCTAssertNil(decoded.apiKey)
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
}
