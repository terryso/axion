import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

// Story 8.1 AC5: Trace records multi-window context
// Verifies that TraceRecorder correctly stores window_id, pid, and app_name
// in tool_use and tool_result events, matching the extraction logic in
// RunCommand.recordToTrace().

@Suite("TraceWindowContext")
struct TraceWindowContextTests: ~Copyable {

    private var tempDir: URL!

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TraceWindowCtx-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir!)
    }

    private func makeRecorder(runId: String = "20260514-winctx") async throws -> TraceRecorder {
        var config = AxionConfig.default
        config.traceEnabled = true
        return try await TraceRecorder(runId: runId, config: config, baseURL: tempDir)
    }

    private func traceFileURL(runId: String = "20260514-winctx") -> URL {
        tempDir!.appendingPathComponent("\(runId)/trace.jsonl")
    }

    private func readTraceLines(runId: String = "20260514-winctx") throws -> [String] {
        let url = traceFileURL(runId: runId)
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private func parseJSONLine(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @Test("tool_use event stores window_id")
    func toolUseEventStoresWindowId() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "tool_use", payload: [
            "tool": "click",
            "toolUseId": "tu-1",
            "window_id": 42,
            "pid": 1234
        ])
        try await recorder.close()

        let lines = try readTraceLines()
        #expect(lines.count == 1)

        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "tool_use")
        #expect(json?["window_id"] as? Int == 42)
        #expect(json?["pid"] as? Int == 1234)
    }

    @Test("tool_result event stores app_name")
    func toolResultEventStoresAppName() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "tool_result", payload: [
            "toolUseId": "tu-1",
            "isError": false,
            "app_name": "Safari",
            "window_id": 10
        ])
        try await recorder.close()

        let lines = try readTraceLines()
        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "tool_result")
        #expect(json?["app_name"] as? String == "Safari")
        #expect(json?["window_id"] as? Int == 10)
    }

    @Test("multi-window sequence records context for each step")
    func multiWindowSequenceRecordsContextForEachStep() async throws {
        let recorder = try await makeRecorder()

        // Step 1: list_windows tool_use
        try await recorder.record(event: "tool_use", payload: [
            "tool": "list_windows",
            "toolUseId": "tu-1"
        ])

        // Step 2: list_windows tool_result (multiple windows)
        try await recorder.record(event: "tool_result", payload: [
            "toolUseId": "tu-1",
            "isError": false
        ])

        // Step 3: activate_window tool_use with pid (switch to Safari)
        try await recorder.record(event: "tool_use", payload: [
            "tool": "activate_window",
            "toolUseId": "tu-2",
            "pid": 200
        ])

        // Step 4: get_window_state tool_use with window_id
        try await recorder.record(event: "tool_use", payload: [
            "tool": "get_window_state",
            "toolUseId": "tu-3",
            "window_id": 20
        ])

        // Step 5: get_window_state tool_result with app_name
        try await recorder.record(event: "tool_result", payload: [
            "toolUseId": "tu-3",
            "isError": false,
            "app_name": "Safari",
            "window_id": 20
        ])

        try await recorder.close()

        let lines = try readTraceLines()
        #expect(lines.count == 5)

        // Verify tool_use events have window context
        let tu2 = parseJSONLine(lines[2])
        #expect(tu2?["tool"] as? String == "activate_window")
        #expect(tu2?["pid"] as? Int == 200)

        let tu3 = parseJSONLine(lines[3])
        #expect(tu3?["tool"] as? String == "get_window_state")
        #expect(tu3?["window_id"] as? Int == 20)

        // Verify tool_result event has app_name
        let tr3 = parseJSONLine(lines[4])
        #expect(tr3?["app_name"] as? String == "Safari")
        #expect(tr3?["window_id"] as? Int == 20)
    }

    @Test("tool_use without window context still records")
    func toolUseEventWithoutWindowContextStillRecords() async throws {
        let recorder = try await makeRecorder()
        try await recorder.record(event: "tool_use", payload: [
            "tool": "screenshot",
            "toolUseId": "tu-99"
        ])
        try await recorder.close()

        let lines = try readTraceLines()
        #expect(lines.count == 1)

        let json = parseJSONLine(lines[0])
        #expect(json?["event"] as? String == "tool_use")
        #expect(json?["tool"] as? String == "screenshot")
        #expect(json?["window_id"] == nil)
        #expect(json?["pid"] == nil)
    }
}
