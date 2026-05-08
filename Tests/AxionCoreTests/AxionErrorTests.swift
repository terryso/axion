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
}
