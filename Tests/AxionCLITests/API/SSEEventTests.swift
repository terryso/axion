import XCTest
@testable import AxionCLI

// [P0] ATDD RED-PHASE — Story 5.2 AC1-AC3
// SSE event model tests. These tests assert EXPECTED behavior.
// They will fail until SSEEvent and related types are implemented.

final class SSEEventTests: XCTestCase {

    // MARK: - AC2: StepStartedData

    func test_stepStartedData_codable_roundTrip_preservesAllFields() throws {
        let data = StepStartedData(stepIndex: 0, tool: "launch_app")

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(StepStartedData.self, from: encoded)

        XCTAssertEqual(decoded.stepIndex, 0)
        XCTAssertEqual(decoded.tool, "launch_app")
    }

    func test_stepStartedData_jsonKeys_areSnakeCase() throws {
        let data = StepStartedData(stepIndex: 2, tool: "click")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(data)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("\"step_index\""), "StepStartedData JSON should contain 'step_index' key")
        XCTAssertTrue(json.contains("\"tool\""), "StepStartedData JSON should contain 'tool' key")
    }

    // MARK: - AC2: StepCompletedData

    func test_stepCompletedData_codable_roundTrip_preservesAllFields() throws {
        let data = StepCompletedData(
            stepIndex: 0,
            tool: "launch_app",
            purpose: "Launch Calculator",
            success: true,
            durationMs: 150
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(StepCompletedData.self, from: encoded)

        XCTAssertEqual(decoded.stepIndex, 0)
        XCTAssertEqual(decoded.tool, "launch_app")
        XCTAssertEqual(decoded.purpose, "Launch Calculator")
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.durationMs, 150)
    }

    func test_stepCompletedData_optionalDurationMs_defaultsToNil() throws {
        let data = StepCompletedData(
            stepIndex: 1,
            tool: "click",
            purpose: "Click button",
            success: false,
            durationMs: nil
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(StepCompletedData.self, from: encoded)

        XCTAssertNil(decoded.durationMs)
    }

    func test_stepCompletedData_jsonKeys_areSnakeCase() throws {
        let data = StepCompletedData(
            stepIndex: 1,
            tool: "click",
            purpose: "Input expression",
            success: true,
            durationMs: 200
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(data)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("\"step_index\""), "StepCompletedData JSON should contain 'step_index' key")
        XCTAssertTrue(json.contains("\"duration_ms\""), "StepCompletedData JSON should contain 'duration_ms' key")
    }

    // MARK: - AC3: RunCompletedData

    func test_runCompletedData_codable_roundTrip_preservesAllFields() throws {
        let data = RunCompletedData(
            runId: "20260513-abc123",
            finalStatus: "done",
            totalSteps: 3,
            durationMs: 8200,
            replanCount: 0
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(RunCompletedData.self, from: encoded)

        XCTAssertEqual(decoded.runId, "20260513-abc123")
        XCTAssertEqual(decoded.finalStatus, "done")
        XCTAssertEqual(decoded.totalSteps, 3)
        XCTAssertEqual(decoded.durationMs, 8200)
        XCTAssertEqual(decoded.replanCount, 0)
    }

    func test_runCompletedData_optionalDurationMs_defaultsToNil() throws {
        let data = RunCompletedData(
            runId: "20260513-xyz789",
            finalStatus: "failed",
            totalSteps: 1,
            durationMs: nil,
            replanCount: 0
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(RunCompletedData.self, from: encoded)

        XCTAssertNil(decoded.durationMs)
    }

    func test_runCompletedData_jsonKeys_areSnakeCase() throws {
        let data = RunCompletedData(
            runId: "20260513-abc123",
            finalStatus: "done",
            totalSteps: 3,
            durationMs: 8200,
            replanCount: 0
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(data)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(json.contains("\"run_id\""), "RunCompletedData JSON should contain 'run_id' key")
        XCTAssertTrue(json.contains("\"final_status\""), "RunCompletedData JSON should contain 'final_status' key")
        XCTAssertTrue(json.contains("\"total_steps\""), "RunCompletedData JSON should contain 'total_steps' key")
        XCTAssertTrue(json.contains("\"duration_ms\""), "RunCompletedData JSON should contain 'duration_ms' key")
        XCTAssertTrue(json.contains("\"replan_count\""), "RunCompletedData JSON should contain 'replan_count' key")
    }

    // MARK: - AC1: SSEEvent enum

    func test_sseEvent_stepStarted_encodesCorrectly() throws {
        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))

        let sseString = try event.encodeToSSE(sequenceId: 1)

        XCTAssertTrue(sseString.hasPrefix("event: step_started\n"), "SSE event should start with 'event: step_started'")
        XCTAssertTrue(sseString.contains("data: "), "SSE event should contain 'data: ' line")
        XCTAssertTrue(sseString.contains("id: 1\n"), "SSE event should contain 'id: 1'")
        XCTAssertTrue(sseString.hasSuffix("\n\n"), "SSE event should end with double newline")
    }

    func test_sseEvent_stepCompleted_encodesCorrectly() throws {
        let event = SSEEvent.stepCompleted(StepCompletedData(
            stepIndex: 0,
            tool: "launch_app",
            purpose: "Launch Calculator",
            success: true,
            durationMs: 150
        ))

        let sseString = try event.encodeToSSE(sequenceId: 2)

        XCTAssertTrue(sseString.hasPrefix("event: step_completed\n"), "SSE event should start with 'event: step_completed'")
        XCTAssertTrue(sseString.contains("id: 2\n"), "SSE event should contain 'id: 2'")
    }

    func test_sseEvent_runCompleted_encodesCorrectly() throws {
        let event = SSEEvent.runCompleted(RunCompletedData(
            runId: "20260513-abc123",
            finalStatus: "done",
            totalSteps: 3,
            durationMs: 8200,
            replanCount: 0
        ))

        let sseString = try event.encodeToSSE(sequenceId: 3)

        XCTAssertTrue(sseString.hasPrefix("event: run_completed\n"), "SSE event should start with 'event: run_completed'")
        XCTAssertTrue(sseString.contains("id: 3\n"), "SSE event should contain 'id: 3'")
    }

    func test_sseEvent_dataField_containsValidJson() throws {
        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        let sseString = try event.encodeToSSE(sequenceId: 1)

        // Extract data field content
        let lines = sseString.components(separatedBy: "\n")
        let dataLine = try XCTUnwrap(lines.first { $0.hasPrefix("data: ") })
        let jsonSubstring = String(dataLine.dropFirst(6))

        // Should be valid JSON
        let jsonData = try XCTUnwrap(jsonSubstring.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: jsonData)
        XCTAssertNotNil(parsed, "SSE data field should contain valid JSON")
    }
}
