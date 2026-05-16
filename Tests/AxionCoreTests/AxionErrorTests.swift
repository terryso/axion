import Foundation
import Testing
@testable import AxionCore

@Suite("AxionError")
struct AxionErrorTests {

    // MARK: - MCP ToolResult Error Format

    @Test("error toToolResultJSON contains required fields")
    func errorToToolResultJSONContainsRequiredFields() throws {
        let error = AxionError.helperNotRunning
        let jsonString = error.toToolResultJSON()
        let json = try JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as! [String: Any]

        #expect(json["error"] != nil)
        #expect(json["message"] != nil)
        #expect(json["suggestion"] != nil)
    }

    @Test("error planningFailed format")
    func errorPlanningFailedFormat() throws {
        let error = AxionError.planningFailed(reason: "could not parse task")
        let payload = error.errorPayload

        #expect(payload.error == "planning_failed")
        #expect(payload.message.contains("could not parse task"))
        #expect(!payload.suggestion.isEmpty)
    }

    @Test("error executionFailed format")
    func errorExecutionFailedFormat() throws {
        let error = AxionError.executionFailed(step: 3, reason: "app not found")
        let payload = error.errorPayload

        #expect(payload.error == "execution_failed")
        #expect(payload.message.contains("Step 3"))
        #expect(payload.message.contains("app not found"))
    }

    @Test("error helperNotRunning format")
    func errorHelperNotRunningFormat() throws {
        let error = AxionError.helperNotRunning
        let payload = error.errorPayload

        #expect(payload.error == "helper_not_running")
        #expect(payload.message == "AxionHelper is not running.")
        #expect(!payload.suggestion.isEmpty)
    }

    @Test("error mcpError format")
    func errorMcpErrorFormat() throws {
        let error = AxionError.mcpError(tool: "click", reason: "coordinates out of bounds")
        let payload = error.errorPayload

        #expect(payload.error == "mcp_error")
        #expect(payload.message.contains("click"))
        #expect(payload.message.contains("coordinates out of bounds"))
    }

    @Test("error maxRetriesExceeded format")
    func errorMaxRetriesExceededFormat() throws {
        let error = AxionError.maxRetriesExceeded(retries: 5)
        let payload = error.errorPayload

        #expect(payload.error == "max_retries_exceeded")
        #expect(payload.message.contains("5"))
    }

    @Test("error toToolResultJSON valid JSON for all cases")
    func errorToToolResultJSONValidJSONForAllCases() throws {
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

            #expect(json["error"] != nil, "Missing 'error' field for \(error)")
            #expect(json["message"] != nil, "Missing 'message' field for \(error)")
            #expect(json["suggestion"] != nil, "Missing 'suggestion' field for \(error)")
        }
    }

    // MARK: - All Error Cases

    @Test("error verificationFailed format")
    func errorVerificationFailedFormat() throws {
        let error = AxionError.verificationFailed(step: 5, reason: "window not visible")
        let payload = error.errorPayload

        #expect(payload.error == "verification_failed")
        #expect(payload.message.contains("step 5"))
        #expect(payload.message.contains("window not visible"))
        #expect(!payload.suggestion.isEmpty)
    }

    @Test("error helperConnectionFailed format")
    func errorHelperConnectionFailedFormat() throws {
        let error = AxionError.helperConnectionFailed(reason: "timeout")
        let payload = error.errorPayload

        #expect(payload.error == "helper_connection_failed")
        #expect(payload.message.contains("timeout"))
        #expect(!payload.suggestion.isEmpty)
    }

    @Test("error configError format")
    func errorConfigErrorFormat() throws {
        let error = AxionError.configError(reason: "missing apiKey")
        let payload = error.errorPayload

        #expect(payload.error == "config_error")
        #expect(payload.message.contains("missing apiKey"))
        #expect(!payload.suggestion.isEmpty)
    }

    @Test("error invalidPlan format")
    func errorInvalidPlanFormat() throws {
        let error = AxionError.invalidPlan(reason: "no steps")
        let payload = error.errorPayload

        #expect(payload.error == "invalid_plan")
        #expect(payload.message.contains("no steps"))
        #expect(!payload.suggestion.isEmpty)
    }

    @Test("error timeout format")
    func errorTimeoutFormat() throws {
        let error = AxionError.timeout(operation: "launch", seconds: 30.0)
        let payload = error.errorPayload

        #expect(payload.error == "timeout")
        #expect(payload.message.contains("launch"))
        #expect(payload.message.contains("30"))
        #expect(!payload.suggestion.isEmpty)
    }

    @Test("error cancelled format")
    func errorCancelledFormat() throws {
        let error = AxionError.cancelled
        let payload = error.errorPayload

        #expect(payload.error == "cancelled")
        #expect(!payload.suggestion.isEmpty)
    }

    @Test("error unknown format")
    func errorUnknownFormat() throws {
        let error = AxionError.unknown(reason: "something unexpected")
        let payload = error.errorPayload

        #expect(payload.error == "unknown")
        #expect(payload.message.contains("something unexpected"))
        #expect(!payload.suggestion.isEmpty)
    }

    // MARK: - toToolResultJSON Format

    @Test("toToolResultJSON produces sorted keys")
    func toToolResultJSONProducesSortedKeys() throws {
        let error = AxionError.mcpError(tool: "click", reason: "failed")
        let jsonString = error.toToolResultJSON()
        let data = Data(jsonString.utf8)

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let sortedKeys = Array(json.keys).sorted()
        #expect(sortedKeys == ["error", "message", "suggestion"])
    }

    @Test("toToolResultJSON all cases produce valid JSON")
    func toToolResultJSONAllCasesProduceValidJSON() throws {
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
            #expect(json != nil, "toToolResultJSON should produce valid JSON for \(error)")
            #expect(json?["error"] as? String == error.errorPayload.error)
        }
    }

    // MARK: - MCPErrorPayload

    @Test("MCPErrorPayload equality")
    func mcpErrorPayloadEquality() {
        let a = AxionError.MCPErrorPayload(error: "e", message: "m", suggestion: "s")
        let b = AxionError.MCPErrorPayload(error: "e", message: "m", suggestion: "s")
        let c = AxionError.MCPErrorPayload(error: "x", message: "m", suggestion: "s")
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Equality

    @Test("error equality")
    func errorEquality() {
        #expect(AxionError.helperNotRunning == AxionError.helperNotRunning)
        #expect(AxionError.helperNotRunning != AxionError.cancelled)
        #expect(
            AxionError.planningFailed(reason: "a")
            == AxionError.planningFailed(reason: "a")
        )
        #expect(
            AxionError.planningFailed(reason: "a")
            != AxionError.planningFailed(reason: "b")
        )
    }

    @Test("error equality all cases")
    func errorEqualityAllCases() {
        #expect(AxionError.cancelled == AxionError.cancelled)
        #expect(AxionError.timeout(operation: "a", seconds: 1.0) == AxionError.timeout(operation: "a", seconds: 1.0))
        #expect(AxionError.timeout(operation: "a", seconds: 1.0) != AxionError.timeout(operation: "b", seconds: 1.0))
        #expect(AxionError.timeout(operation: "a", seconds: 1.0) != AxionError.timeout(operation: "a", seconds: 2.0))
        #expect(AxionError.maxRetriesExceeded(retries: 3) == AxionError.maxRetriesExceeded(retries: 3))
        #expect(AxionError.maxRetriesExceeded(retries: 3) != AxionError.maxRetriesExceeded(retries: 4))
        #expect(AxionError.stepBudgetExceeded(steps: 10, limit: 10) == AxionError.stepBudgetExceeded(steps: 10, limit: 10))
        #expect(AxionError.stepBudgetExceeded(steps: 10, limit: 10) != AxionError.stepBudgetExceeded(steps: 11, limit: 10))
        #expect(AxionError.batchBudgetExceeded(batches: 6, limit: 6) == AxionError.batchBudgetExceeded(batches: 6, limit: 6))
        #expect(AxionError.batchBudgetExceeded(batches: 6, limit: 6) != AxionError.batchBudgetExceeded(batches: 7, limit: 6))
        #expect(AxionError.unknown(reason: "x") == AxionError.unknown(reason: "x"))
        #expect(AxionError.unknown(reason: "x") != AxionError.unknown(reason: "y"))
    }
}
