import XCTest
@testable import AxionCore

final class AxionErrorTests: XCTestCase {

    // MARK: - MCP ToolResult Error Format

    func test_error_toToolResultJSON_containsRequiredFields() throws {
        let error = AxionError.helperNotRunning
        let jsonString = error.toToolResultJSON()
        let json = try JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as! [String: Any]

        XCTAssertNotNil(json["error"])
        XCTAssertNotNil(json["message"])
        XCTAssertNotNil(json["suggestion"])
    }

    func test_error_planningFailed_format() throws {
        let error = AxionError.planningFailed(reason: "could not parse task")
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "planning_failed")
        XCTAssertTrue(payload.message.contains("could not parse task"))
        XCTAssertFalse(payload.suggestion.isEmpty)
    }

    func test_error_executionFailed_format() throws {
        let error = AxionError.executionFailed(step: 3, reason: "app not found")
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "execution_failed")
        XCTAssertTrue(payload.message.contains("Step 3"))
        XCTAssertTrue(payload.message.contains("app not found"))
    }

    func test_error_helperNotRunning_format() throws {
        let error = AxionError.helperNotRunning
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "helper_not_running")
        XCTAssertEqual(payload.message, "AxionHelper is not running.")
        XCTAssertFalse(payload.suggestion.isEmpty)
    }

    func test_error_mcpError_format() throws {
        let error = AxionError.mcpError(tool: "click", reason: "coordinates out of bounds")
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "mcp_error")
        XCTAssertTrue(payload.message.contains("click"))
        XCTAssertTrue(payload.message.contains("coordinates out of bounds"))
    }

    func test_error_maxRetriesExceeded_format() throws {
        let error = AxionError.maxRetriesExceeded(retries: 5)
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "max_retries_exceeded")
        XCTAssertTrue(payload.message.contains("5"))
    }

    func test_error_toToolResultJSON_validJSON() throws {
        let allErrors: [AxionError] = [
            .planningFailed(reason: "test"),
            .executionFailed(step: 0, reason: "test"),
            .verificationFailed(step: 0, reason: "test"),
            .helperNotRunning,
            .helperConnectionFailed(reason: "test"),
            .configError(reason: "test"),
            .mcpError(tool: "test", reason: "test"),
            .invalidPlan(reason: "test"),
            .maxRetriesExceeded(retries: 1),
            .stepBudgetExceeded(steps: 20, limit: 20),
            .batchBudgetExceeded(batches: 6, limit: 6),
            .timeout(operation: "test", seconds: 30),
            .cancelled,
            .unknown(reason: "test"),
        ]

        for error in allErrors {
            let jsonString = error.toToolResultJSON()
            let data = jsonString.data(using: .utf8)!
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            XCTAssertNotNil(json["error"], "Missing 'error' field for \(error)")
            XCTAssertNotNil(json["message"], "Missing 'message' field for \(error)")
            XCTAssertNotNil(json["suggestion"], "Missing 'suggestion' field for \(error)")
        }
    }

    // MARK: - All Error Cases

    func test_error_verificationFailed_format() throws {
        let error = AxionError.verificationFailed(step: 5, reason: "window not visible")
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "verification_failed")
        XCTAssertTrue(payload.message.contains("step 5"))
        XCTAssertTrue(payload.message.contains("window not visible"))
        XCTAssertFalse(payload.suggestion.isEmpty)
    }

    func test_error_helperConnectionFailed_format() throws {
        let error = AxionError.helperConnectionFailed(reason: "timeout")
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "helper_connection_failed")
        XCTAssertTrue(payload.message.contains("timeout"))
        XCTAssertFalse(payload.suggestion.isEmpty)
    }

    func test_error_configError_format() throws {
        let error = AxionError.configError(reason: "missing apiKey")
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "config_error")
        XCTAssertTrue(payload.message.contains("missing apiKey"))
        XCTAssertFalse(payload.suggestion.isEmpty)
    }

    func test_error_invalidPlan_format() throws {
        let error = AxionError.invalidPlan(reason: "no steps")
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "invalid_plan")
        XCTAssertTrue(payload.message.contains("no steps"))
        XCTAssertFalse(payload.suggestion.isEmpty)
    }

    func test_error_timeout_format() throws {
        let error = AxionError.timeout(operation: "launch", seconds: 30.0)
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "timeout")
        XCTAssertTrue(payload.message.contains("launch"))
        XCTAssertTrue(payload.message.contains("30"))
        XCTAssertFalse(payload.suggestion.isEmpty)
    }

    func test_error_cancelled_format() throws {
        let error = AxionError.cancelled
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "cancelled")
        XCTAssertFalse(payload.suggestion.isEmpty)
    }

    func test_error_unknown_format() throws {
        let error = AxionError.unknown(reason: "something unexpected")
        let payload = error.errorPayload

        XCTAssertEqual(payload.error, "unknown")
        XCTAssertTrue(payload.message.contains("something unexpected"))
        XCTAssertFalse(payload.suggestion.isEmpty)
    }

    // MARK: - toToolResultJSON Format

    func test_toToolResultJSON_producesSortedKeys() throws {
        let error = AxionError.mcpError(tool: "click", reason: "failed")
        let jsonString = error.toToolResultJSON()
        let data = Data(jsonString.utf8)

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // SortedKeys encoder should produce keys in order
        let sortedKeys = Array(json.keys).sorted()
        XCTAssertEqual(sortedKeys, ["error", "message", "suggestion"])
    }

    func test_toToolResultJSON_allCases_produceValidJSON() throws {
        let allErrors: [AxionError] = [
            .planningFailed(reason: "r"),
            .executionFailed(step: 1, reason: "r"),
            .verificationFailed(step: 1, reason: "r"),
            .helperNotRunning,
            .helperConnectionFailed(reason: "r"),
            .configError(reason: "r"),
            .mcpError(tool: "t", reason: "r"),
            .invalidPlan(reason: "r"),
            .maxRetriesExceeded(retries: 3),
            .stepBudgetExceeded(steps: 20, limit: 20),
            .batchBudgetExceeded(batches: 6, limit: 6),
            .timeout(operation: "op", seconds: 1.0),
            .cancelled,
            .unknown(reason: "r"),
        ]
        for error in allErrors {
            let jsonString = error.toToolResultJSON()
            let data = Data(jsonString.utf8)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertNotNil(json, "toToolResultJSON should produce valid JSON for \(error)")
            XCTAssertEqual(json?["error"] as? String, error.errorPayload.error)
        }
    }

    // MARK: - MCPErrorPayload

    func test_mcpErrorPayload_equality() {
        let a = AxionError.MCPErrorPayload(error: "e", message: "m", suggestion: "s")
        let b = AxionError.MCPErrorPayload(error: "e", message: "m", suggestion: "s")
        let c = AxionError.MCPErrorPayload(error: "x", message: "m", suggestion: "s")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Equality

    func test_error_equality() {
        XCTAssertEqual(AxionError.helperNotRunning, AxionError.helperNotRunning)
        XCTAssertNotEqual(AxionError.helperNotRunning, AxionError.cancelled)
        XCTAssertEqual(
            AxionError.planningFailed(reason: "a"),
            AxionError.planningFailed(reason: "a")
        )
        XCTAssertNotEqual(
            AxionError.planningFailed(reason: "a"),
            AxionError.planningFailed(reason: "b")
        )
    }

    func test_error_equality_allCases() {
        XCTAssertEqual(AxionError.cancelled, AxionError.cancelled)
        XCTAssertEqual(AxionError.timeout(operation: "a", seconds: 1.0), AxionError.timeout(operation: "a", seconds: 1.0))
        XCTAssertNotEqual(AxionError.timeout(operation: "a", seconds: 1.0), AxionError.timeout(operation: "b", seconds: 1.0))
        XCTAssertNotEqual(AxionError.timeout(operation: "a", seconds: 1.0), AxionError.timeout(operation: "a", seconds: 2.0))
        XCTAssertEqual(AxionError.maxRetriesExceeded(retries: 3), AxionError.maxRetriesExceeded(retries: 3))
        XCTAssertNotEqual(AxionError.maxRetriesExceeded(retries: 3), AxionError.maxRetriesExceeded(retries: 4))
        XCTAssertEqual(AxionError.stepBudgetExceeded(steps: 10, limit: 10), AxionError.stepBudgetExceeded(steps: 10, limit: 10))
        XCTAssertNotEqual(AxionError.stepBudgetExceeded(steps: 10, limit: 10), AxionError.stepBudgetExceeded(steps: 11, limit: 10))
        XCTAssertEqual(AxionError.batchBudgetExceeded(batches: 6, limit: 6), AxionError.batchBudgetExceeded(batches: 6, limit: 6))
        XCTAssertNotEqual(AxionError.batchBudgetExceeded(batches: 6, limit: 6), AxionError.batchBudgetExceeded(batches: 7, limit: 6))
        XCTAssertEqual(AxionError.unknown(reason: "x"), AxionError.unknown(reason: "x"))
        XCTAssertNotEqual(AxionError.unknown(reason: "x"), AxionError.unknown(reason: "y"))
    }
}
