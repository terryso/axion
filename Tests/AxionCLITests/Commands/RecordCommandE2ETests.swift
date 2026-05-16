import AxionCore
import Foundation
import Testing

@testable import AxionCLI

// MARK: - RecordCommandE2ETests
// E2E tests for the RecordCommand CLI flow: parse → build recording → save → verify

@Suite("RecordCommand E2E Tests")
struct RecordCommandE2ETests {

    // MARK: - AC1: Recordings Directory

    @Test("Recordings directory is under home .axion folder")
    func test_recordingsDirectory_location() {
        let dir = RecordCommand.recordingsDirectory()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(dir.hasPrefix(homeDir))
        #expect(dir.hasSuffix(".axion/recordings"))
    }

    // MARK: - AC5: Parse + Save Full Flow

    @Test("parseRecordingEvents → Recording → file save → file load round-trip")
    func test_fullCLIWorkflow_saveAndLoad() async throws {
        // Simulate what stop_recording tool returns
        let event1JSON = #"{"type":"click","timestamp":1.5,"parameters":{"x":100,"y":200},"window_context":null}"#
        let event2JSON = #"{"type":"type_text","timestamp":2.5,"parameters":{"text":"hello"},"window_context":null}"#
        let escaped1 = event1JSON.replacingOccurrences(of: "\"", with: "\\\"")
        let escaped2 = event2JSON.replacingOccurrences(of: "\"", with: "\\\"")
        let toolResult = """
        {"success":true,"action":"stop_recording","event_count":2,"events":["\(escaped1)","\(escaped2)"]}
        """

        // Step 1: Parse events from tool result
        let events = RecordCommand.parseRecordingEvents(from: toolResult)
        #expect(events.count == 2)

        // Step 2: Build Recording
        let recording = Recording(
            name: "e2e_test",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 5.0,
            events: events,
            windowSnapshots: []
        )

        // Step 3: Save to temp file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let fileURL = tempDir.appendingPathComponent("e2e_test.json")
        try encoder.encode(recording).write(to: fileURL)

        // Step 4: Load and verify
        let loadedData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(Recording.self, from: loadedData)

        #expect(loaded.name == "e2e_test")
        #expect(loaded.events.count == 2)
        #expect(loaded.events[0].type == .click)
        #expect(loaded.events[1].type == .typeText)
        #expect(loaded.events[0].parameters["x"] == .int(100))
        #expect(loaded.events[1].parameters["text"] == .string("hello"))
    }

    @Test("parseRecordingEvents with window context preserves context")
    func test_parseEvents_withWindowContext() {
        let ctxJSON = #"{"app_name":"Calculator","pid":12345,"window_id":42,"window_title":"Calculator"}"#
        let eventJSON = #"{"type":"click","timestamp":1.0,"parameters":{"x":500,"y":300},"window_context":\#(ctxJSON)}"#
        let escaped = eventJSON.replacingOccurrences(of: "\"", with: "\\\"")
        let wrapper = """
        {"success":true,"event_count":1,"events":["\(escaped)"]}
        """

        let events = RecordCommand.parseRecordingEvents(from: wrapper)
        #expect(events.count == 1)

        let event = events[0]
        #expect(event.windowContext != nil)
        #expect(event.windowContext?.appName == "Calculator")
        #expect(event.windowContext?.pid == 12345)
        #expect(event.windowContext?.windowId == 42)
        #expect(event.windowContext?.windowTitle == "Calculator")
    }

    // MARK: - AC5: File Save Creates Directory

    @Test("Recording file path uses recordings directory")
    func test_recordingFilePath_correctLocation() {
        let dir = RecordCommand.recordingsDirectory()
        let name = "test_recording"
        let filePath = (dir as NSString).appendingPathComponent("\(name).json")
        #expect(filePath.hasSuffix(".axion/recordings/test_recording.json"))
    }

    // MARK: - AC6: Graceful Error Handling in Parse

    @Test("parseRecordingEvents handles mixed valid and invalid events gracefully")
    func test_parseEvents_mixedValidity() {
        let validEvent = #"{"type":"click","timestamp":1.0,"parameters":{"x":50,"y":60},"window_context":null}"#
        let escapedValid = validEvent.replacingOccurrences(of: "\"", with: "\\\"")
        let wrapper = """
        {"events":["\(escapedValid)","not_json","{}","[]"]}
        """

        let events = RecordCommand.parseRecordingEvents(from: wrapper)
        // Only the valid event should parse; others are skipped
        #expect(events.count == 1)
        #expect(events[0].type == .click)
    }

    // MARK: - Recording Save Format

    @Test("Saved recording file has correct JSON structure")
    func test_savedRecordingStructure() async throws {
        let events = [
            RecordedEvent(type: .appSwitch, timestamp: 0.1,
                          parameters: ["app_name": .string("Safari"), "pid": .int(100)],
                          windowContext: WindowContext(appName: "Safari", pid: 100, windowId: 1, windowTitle: "Safari")),
            RecordedEvent(type: .click, timestamp: 1.5,
                          parameters: ["x": .int(200), "y": .int(400)],
                          windowContext: WindowContext(appName: "Safari", pid: 100, windowId: 1, windowTitle: "Safari")),
        ]
        let recording = Recording(
            name: "format_test",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 3.5,
            events: events,
            windowSnapshots: [
                WindowSnapshot(windowId: 1, appName: "Safari", title: "Safari",
                               bounds: WindowBounds(x: 0, y: 0, width: 1024, height: 768),
                               capturedAtEventIndex: 0)
            ]
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let fileURL = tempDir.appendingPathComponent("format_test.json")
        try encoder.encode(recording).write(to: fileURL)

        let loadedData = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: loadedData) as! [String: Any]

        // Verify required top-level keys match spec
        #expect(json["name"] as? String == "format_test")
        #expect(json["created_at"] != nil)
        #expect(json["duration_seconds"] as? Double == 3.5)
        #expect((json["events"] as? [Any])?.count == 2)
        #expect((json["window_snapshots"] as? [Any])?.count == 1)

        // Verify first event (app_switch)
        let firstEvent = (json["events"] as! [[String: Any]])[0]
        #expect(firstEvent["type"] as? String == "app_switch")
        #expect(firstEvent["timestamp"] != nil)
        let params = firstEvent["parameters"] as! [String: Any]
        #expect(params["app_name"] as? String == "Safari")

        // Verify snapshot
        let snapshot = (json["window_snapshots"] as! [[String: Any]])[0]
        #expect(snapshot["captured_at_event_index"] as? Int == 0)
        let bounds = snapshot["bounds"] as! [String: Any]
        #expect(bounds["width"] as? Int == 1024)
    }

    // MARK: - Recording Summary Output

    @Test("Recording produces correct summary info")
    func test_recordingSummary() throws {
        let events = [
            RecordedEvent(type: .click, timestamp: 1.0, parameters: ["x": .int(100)], windowContext: nil),
            RecordedEvent(type: .typeText, timestamp: 2.0, parameters: ["text": .string("a")], windowContext: nil),
            RecordedEvent(type: .hotkey, timestamp: 3.0, parameters: ["keys": .string("cmd+c")], windowContext: nil),
        ]
        let recording = Recording(
            name: "summary_test",
            createdAt: Date(),
            durationSeconds: 3.0,
            events: events,
            windowSnapshots: []
        )

        #expect(recording.events.count == 3)
        #expect(recording.durationSeconds == 3.0)
        let summary = "\(recording.events.count) 个事件，耗时 \(String(format: "%.1f", recording.durationSeconds)) 秒"
        #expect(summary == "3 个事件，耗时 3.0 秒")
    }
}
