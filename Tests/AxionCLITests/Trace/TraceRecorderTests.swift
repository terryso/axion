import XCTest
@testable import AxionCLI
@testable import AxionCore

// [P0] Trace file creation, JSONL format, event types, traceEnabled toggle
// [P1] Close flush, API key safety

// MARK: - TraceRecorder ATDD Tests

/// ATDD red-phase tests for TraceRecorder (Story 3-5 AC6, AC7).
/// Tests that TraceRecorder creates JSONL trace files with correctly formatted
/// events containing ISO8601 timestamps and snake_case event names.
///
/// TDD RED PHASE: These tests will not compile until TraceRecorder is implemented
/// in Sources/AxionCLI/Trace/TraceRecorder.swift.
final class TraceRecorderTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TraceRecorderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir!)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helper: Create TraceRecorder with temp directory

    private func makeRecorder(runId: String = "20260510-test01", enabled: Bool = true) async throws -> TraceRecorder {
        var config = AxionConfig.default
        config.traceEnabled = enabled
        return try await TraceRecorder(runId: runId, config: config, baseURL: tempDir)
    }

    private func traceFileURL(runId: String = "20260510-test01") -> URL {
        tempDir!.appendingPathComponent("\(runId)/trace.jsonl")
    }

    private func readTraceLines(runId: String = "20260510-test01") throws -> [String] {
        let url = traceFileURL(runId: runId)
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private func parseJSONLine(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - P0 Type Existence

    func test_traceRecorder_typeExists() {
        let _ = TraceRecorder.self
    }

    func test_traceRecorder_isActor() {
        // TraceRecorder must be an actor — verified by needing `await` on its methods
        // This test just confirms the type exists and can be used in async context
        let _: @Sendable () async throws -> Void = {
            let _ = TraceRecorder.self
        }
    }

    // MARK: - P0 AC6: Trace File Creation

    func test_traceRecorder_createsDirectoryAndFile() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "test", payload: [:])
        try await recorder.close()

        let fileURL = traceFileURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
            "Trace file should exist at \(fileURL.path)")
    }

    // MARK: - P0 AC7: Trace File Format

    func test_traceRecorder_eventsHaveTimestampAndEventField() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "test_event", payload: ["key": "value"])
        try await recorder.close()

        let lines = try readTraceLines()
        XCTAssertEqual(lines.count, 1, "Should have 1 trace line")

        let json = parseJSONLine(lines[0])
        XCTAssertNotNil(json, "Line should be valid JSON: \(lines[0])")
        XCTAssertNotNil(json?["ts"], "Event must have 'ts' field")
        XCTAssertEqual(json?["event"] as? String, "test_event", "Event must have 'event' field")
    }

    func test_traceRecorder_timestampIsISO8601() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "test", payload: [:])
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        let ts = json?["ts"] as? String ?? ""

        // ISO8601 format should contain date separators and time separators
        // e.g., "2026-05-10T10:30:00Z" or "2026-05-10T10:30:00+08:00"
        let hasDate = ts.contains("-") && ts.contains("T")
        XCTAssertTrue(hasDate, "Timestamp should be ISO8601 format: '\(ts)'")

        // Should be parseable by ISO8601DateFormatter
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: ts)
        // Also try without fractional seconds
        let parsed2 = parsed ?? ISO8601DateFormatter().date(from: ts)
        XCTAssertNotNil(parsed2, "Timestamp should be parseable as ISO8601: '\(ts)'")
    }

    func test_traceRecorder_eventNameIsSnakeCase() async throws {
        let recorder = try await makeRecorder()

        // Test all expected event names
        let expectedEvents = [
            "run_start", "plan_created", "step_start", "step_done",
            "state_change", "verification_result", "run_done", "error"
        ]

        for event in expectedEvents {
            try await recorder.record(event: event, payload: [:])
        }
        try await recorder.close()

        let lines = try readTraceLines()
        XCTAssertEqual(lines.count, expectedEvents.count)

        for (index, line) in lines.enumerated() {
            let json = parseJSONLine(line)
            let eventName = json?["event"] as? String ?? ""
            XCTAssertEqual(eventName, expectedEvents[index],
                "Event name should be '\(expectedEvents[index])', got '\(eventName)'")

            // Verify snake_case pattern: lowercase letters, digits, underscores only
            let snakeCasePattern = "^[a-z][a-z0-9_]*$"
            let regex = try NSRegularExpression(pattern: snakeCasePattern)
            let range = NSRange(eventName.startIndex..., in: eventName)
            XCTAssertGreaterThan(regex.numberOfMatches(in: eventName, range: range), 0,
                "Event name '\(eventName)' should be snake_case")
        }
    }

    // MARK: - P0 AC6: Multiple Records

    func test_traceRecorder_multipleRecords_allWritten() async throws {
        let recorder = try await makeRecorder()

        try await recorder.record(event: "run_start", payload: ["runId": "test"])
        try await recorder.record(event: "plan_created", payload: ["steps": 3])
        try await recorder.record(event: "step_done", payload: ["index": 0])
        try await recorder.record(event: "run_done", payload: ["totalSteps": 1])

        try await recorder.close()

        let lines = try readTraceLines()
        XCTAssertEqual(lines.count, 4, "Should have 4 trace lines, got \(lines.count)")

        // Verify each line is independent JSON
        for (index, line) in lines.enumerated() {
            let json = parseJSONLine(line)
            XCTAssertNotNil(json, "Line \(index) should be valid JSON: \(line)")
        }
    }

    // MARK: - P0 AC6: traceEnabled Toggle

    func test_traceRecorder_disabled_doesNotWrite() async throws {
        let recorder = try await makeRecorder(enabled: false)
        try await recorder.record(event: "test", payload: [:])
        try await recorder.close()

        let fileURL = traceFileURL()
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        XCTAssertFalse(exists,
            "Trace file should NOT exist when traceEnabled=false")
    }

    // MARK: - P1 Close Flush

    func test_traceRecorder_close_flushesData() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "test", payload: ["data": "important"])
        try await recorder.close()

        // After close, data must be readable
        let lines = try readTraceLines()
        XCTAssertEqual(lines.count, 1, "Data should be flushed after close()")

        let json = parseJSONLine(lines[0])
        XCTAssertEqual(json?["data"] as? String, "important")
    }

    // MARK: - P0 AC6: Convenience Event Methods

    func test_traceRecorder_recordRunStart_eventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordRunStart(runId: "test-123", task: "Open Calc", mode: "plan_execute")
        try await recorder.close()

        let lines = try readTraceLines()
        XCTAssertEqual(lines.count, 1)
        let json = parseJSONLine(lines[0])
        XCTAssertEqual(json?["event"] as? String, "run_start")
        XCTAssertEqual(json?["runId"] as? String, "test-123")
    }

    func test_traceRecorder_recordPlanCreated_eventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordPlanCreated(stepCount: 3, stopWhenCount: 1)
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        XCTAssertEqual(json?["event"] as? String, "plan_created")
    }

    func test_traceRecorder_recordStepStart_eventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordStepStart(index: 0, tool: "launch_app", purpose: "Launch Calculator")
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        XCTAssertEqual(json?["event"] as? String, "step_start")
        XCTAssertEqual(json?["tool"] as? String, "launch_app")
    }

    func test_traceRecorder_recordStepDone_eventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordStepDone(index: 0, tool: "launch_app", success: true, resultSnippet: "ok")
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        XCTAssertEqual(json?["event"] as? String, "step_done")
        XCTAssertEqual(json?["success"] as? Bool, true)
    }

    func test_traceRecorder_recordStateChange_eventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordStateChange(from: "planning", to: "executing")
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        XCTAssertEqual(json?["event"] as? String, "state_change")
    }

    func test_traceRecorder_recordVerificationResult_eventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordVerificationResult(state: "done", reason: "Task complete")
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        XCTAssertEqual(json?["event"] as? String, "verification_result")
    }

    func test_traceRecorder_recordRunDone_eventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordRunDone(totalSteps: 3, durationMs: 8200, replanCount: 0)
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        XCTAssertEqual(json?["event"] as? String, "run_done")
        XCTAssertEqual(json?["totalSteps"] as? Int, 3)
    }

    func test_traceRecorder_recordError_eventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordError(error: "planning_failed", message: "LLM timeout")
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        XCTAssertEqual(json?["event"] as? String, "error")
        XCTAssertEqual(json?["error"] as? String, "planning_failed")
    }

    // MARK: - P0 AC7: API Key Safety

    func test_traceRecorder_apiKeyNotInPayload() async throws {
        let recorder = try await makeRecorder()

        // Simulate a payload that might accidentally contain an API key
        try await recorder.record(event: "run_start", payload: [
            "runId": "test",
            "config": "model=gpt-4,apiKey=sk-secret-12345"
        ])
        try await recorder.close()

        let lines = try readTraceLines()
        let content = lines.joined(separator: "\n")

        XCTAssertFalse(content.contains("sk-secret-12345"),
            "API key must never appear in trace output")
        XCTAssertFalse(content.lowercased().contains("apikey"),
            "apiKey field must never appear in trace output")
    }

    // MARK: - P0 AC7: Each Line Is Independent JSON

    func test_traceRecorder_eachLineIsIndependentJSON() async throws {
        let recorder = try await makeRecorder()

        try await recorder.record(event: "run_start", payload: ["runId": "r1"])
        try await recorder.record(event: "step_start", payload: ["index": 0])
        try await recorder.record(event: "step_done", payload: ["index": 0, "success": true])
        try await recorder.record(event: "run_done", payload: ["totalSteps": 1])

        try await recorder.close()

        let lines = try readTraceLines()
        XCTAssertEqual(lines.count, 4)

        // Each line must parse independently
        for (index, line) in lines.enumerated() {
            let json = parseJSONLine(line)
            XCTAssertNotNil(json,
                "Line \(index) must be valid independent JSON: \(line)")
            XCTAssertNotNil(json?["ts"],
                "Line \(index) must have 'ts' field")
            XCTAssertNotNil(json?["event"],
                "Line \(index) must have 'event' field")
        }
    }
}
