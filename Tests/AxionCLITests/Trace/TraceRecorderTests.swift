import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

/// ATDD red-phase tests for TraceRecorder (Story 3-5 AC6, AC7).
/// Tests that TraceRecorder creates JSONL trace files with correctly formatted
/// events containing ISO8601 timestamps and snake_case event names.
///
/// TDD RED PHASE: These tests will not compile until TraceRecorder is implemented
/// in Sources/AxionCLI/Trace/TraceRecorder.swift.
@Suite("TraceRecorder")
struct TraceRecorderTests: ~Copyable {

    private var tempDir: URL!

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TraceRecorderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir!)
    }

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

    @Test("TraceRecorder type exists")
    func traceRecorderTypeExists() {
        let _ = TraceRecorder.self
    }

    @Test("TraceRecorder is actor")
    func traceRecorderIsActor() {
        // TraceRecorder must be an actor — verified by needing `await` on its methods
        // This test just confirms the type exists and can be used in async context
        let _: @Sendable () async throws -> Void = {
            let _ = TraceRecorder.self
        }
    }

    @Test("creates directory and file")
    func traceRecorderCreatesDirectoryAndFile() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "test", payload: [:])
        try await recorder.close()

        let fileURL = traceFileURL()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("events have timestamp and event field")
    func traceRecorderEventsHaveTimestampAndEventField() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "test_event", payload: ["key": "value"])
        try await recorder.close()

        let lines = try readTraceLines()
        #expect(lines.count == 1)

        let json = parseJSONLine(lines[0])
        #expect(json != nil)
        #expect(json?["ts"] != nil)
        #expect(json?["event"] as? String == "test_event")
    }

    @Test("timestamp is ISO8601")
    func traceRecorderTimestampIsISO8601() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "test", payload: [:])
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        let ts = json?["ts"] as? String ?? ""

        // ISO8601 format should contain date separators and time separators
        // e.g., "2026-05-10T10:30:00Z" or "2026-05-10T10:30:00+08:00"
        let hasDate = ts.contains("-") && ts.contains("T")
        #expect(hasDate)

        // Should be parseable by ISO8601DateFormatter
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: ts)
        // Also try without fractional seconds
        let parsed2 = parsed ?? ISO8601DateFormatter().date(from: ts)
        #expect(parsed2 != nil)
    }

    @Test("event name is snake_case")
    func traceRecorderEventNameIsSnakeCase() async throws {
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
        #expect(lines.count == expectedEvents.count)

        for (index, line) in lines.enumerated() {
            let json = parseJSONLine(line)
            let eventName = json?["event"] as? String ?? ""
            #expect(eventName == expectedEvents[index])

            // Verify snake_case pattern: lowercase letters, digits, underscores only
            let snakeCasePattern = "^[a-z][a-z0-9_]*$"
            let regex = try NSRegularExpression(pattern: snakeCasePattern)
            let range = NSRange(eventName.startIndex..., in: eventName)
            #expect(regex.numberOfMatches(in: eventName, range: range) > 0)
        }
    }

    @Test("multiple records all written")
    func traceRecorderMultipleRecordsAllWritten() async throws {
        let recorder = try await makeRecorder()

        try await recorder.record(event: "run_start", payload: ["runId": "test"])
        try await recorder.record(event: "plan_created", payload: ["steps": 3])
        try await recorder.record(event: "step_done", payload: ["index": 0])
        try await recorder.record(event: "run_done", payload: ["totalSteps": 1])

        try await recorder.close()

        let lines = try readTraceLines()
        #expect(lines.count == 4)

        // Verify each line is independent JSON
        for (index, line) in lines.enumerated() {
            let json = parseJSONLine(line)
            #expect(json != nil)
        }
    }

    @Test("disabled does not write")
    func traceRecorderDisabledDoesNotWrite() async throws {
        let recorder = try await makeRecorder(enabled: false)
        try await recorder.record(event: "test", payload: [:])
        try await recorder.close()

        let fileURL = traceFileURL()
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        #expect(!exists)
    }

    @Test("close flushes data")
    func traceRecorderCloseFlushesData() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "test", payload: ["data": "important"])
        try await recorder.close()

        // After close, data must be readable
        let lines = try readTraceLines()
        #expect(lines.count == 1)

        let json = parseJSONLine(lines[0])
        #expect(json?["data"] as? String == "important")
    }

    @Test("recordRunStart event type")
    func traceRecorderRecordRunStartEventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordRunStart(runId: "test-123", task: "Open Calc", mode: "plan_execute")
        try await recorder.close()

        let lines = try readTraceLines()
        #expect(lines.count == 1)
        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "run_start")
        #expect(json?["runId"] as? String == "test-123")
    }

    @Test("recordPlanCreated event type")
    func traceRecorderRecordPlanCreatedEventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordPlanCreated(stepCount: 3, stopWhenCount: 1)
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "plan_created")
    }

    @Test("recordStepStart event type")
    func traceRecorderRecordStepStartEventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordStepStart(index: 0, tool: "launch_app", purpose: "Launch Calculator")
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "step_start")
        #expect(json?["tool"] as? String == "launch_app")
    }

    @Test("recordStepDone event type")
    func traceRecorderRecordStepDoneEventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordStepDone(index: 0, tool: "launch_app", success: true, resultSnippet: "ok")
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "step_done")
        #expect(json?["success"] as? Bool == true)
    }

    @Test("recordStateChange event type")
    func traceRecorderRecordStateChangeEventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordStateChange(from: "planning", to: "executing")
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "state_change")
    }

    @Test("recordVerificationResult event type")
    func traceRecorderRecordVerificationResultEventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordVerificationResult(state: "done", reason: "Task complete")
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "verification_result")
    }

    @Test("recordRunDone event type")
    func traceRecorderRecordRunDoneEventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordRunDone(totalSteps: 3, durationMs: 8200, replanCount: 0)
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "run_done")
        #expect(json?["totalSteps"] as? Int == 3)
    }

    @Test("recordError event type")
    func traceRecorderRecordErrorEventType() async throws {
        let recorder = try await makeRecorder()
        try await recorder.recordError(error: "planning_failed", message: "LLM timeout")
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "error")
        #expect(json?["error"] as? String == "planning_failed")
    }

    @Test("API key not in payload")
    func traceRecorderApiKeyNotInPayload() async throws {
        let recorder = try await makeRecorder()

        // Simulate a payload that might accidentally contain an API key
        try await recorder.record(event: "run_start", payload: [
            "runId": "test",
            "config": "model=gpt-4,apiKey=sk-secret-12345"
        ])
        try await recorder.close()

        let lines = try readTraceLines()
        let content = lines.joined(separator: "\n")

        #expect(!content.contains("sk-secret-12345"))
        #expect(!content.lowercased().contains("apikey"))
    }

    @Test("each line is independent JSON")
    func traceRecorderEachLineIsIndependentJSON() async throws {
        let recorder = try await makeRecorder()

        try await recorder.record(event: "run_start", payload: ["runId": "r1"])
        try await recorder.record(event: "step_start", payload: ["index": 0])
        try await recorder.record(event: "step_done", payload: ["index": 0, "success": true])
        try await recorder.record(event: "run_done", payload: ["totalSteps": 1])

        try await recorder.close()

        let lines = try readTraceLines()
        #expect(lines.count == 4)

        // Each line must parse independently
        for (index, line) in lines.enumerated() {
            let json = parseJSONLine(line)
            #expect(json != nil)
            #expect(json?["ts"] != nil)
            #expect(json?["event"] != nil)
        }
    }
}
