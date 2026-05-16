import AxionCore
import Foundation
import Testing

@testable import AxionCore

// MARK: - RecordingLifecycleE2ETests
// Tests for complete recording file lifecycle: create → serialize → save → load → verify

@Suite("Recording Lifecycle E2E Tests")
struct RecordingLifecycleE2ETests {

    // MARK: - AC5: Save and Load Recording File

    @Test("Recording save/load round-trip preserves all data")
    func test_recordingFile_roundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let events = [
            RecordedEvent(type: .appSwitch, timestamp: 0.1,
                          parameters: ["app_name": .string("Calculator"), "pid": .int(12345)],
                          windowContext: WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")),
            RecordedEvent(type: .click, timestamp: 2.3,
                          parameters: ["x": .int(500), "y": .int(300)],
                          windowContext: WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")),
            RecordedEvent(type: .typeText, timestamp: 3.5,
                          parameters: ["text": .string("17")],
                          windowContext: WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")),
        ]
        let snapshots = [
            WindowSnapshot(windowId: 42, appName: "Calculator", title: "Calculator",
                           bounds: WindowBounds(x: 100, y: 100, width: 300, height: 400), capturedAtEventIndex: 0)
        ]
        let original = Recording(
            name: "打开计算器",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 12.5,
            events: events,
            windowSnapshots: snapshots
        )

        // Save
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let fileURL = tempDir.appendingPathComponent("test_recording.json")
        let data = try encoder.encode(original)
        try data.write(to: fileURL)

        // Load
        let loadedData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(Recording.self, from: loadedData)

        // Verify
        #expect(loaded == original)
        #expect(loaded.name == "打开计算器")
        #expect(loaded.events.count == 3)
        #expect(loaded.windowSnapshots.count == 1)
    }

    // MARK: - Recording JSON Format Validation (Spec Compliance)

    @Test("Recording JSON matches spec format")
    func test_recordingJSON_specCompliance() throws {
        let recording = Recording(
            name: "打开计算器",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 12.5,
            events: [
                RecordedEvent(type: .click, timestamp: 2.3,
                              parameters: ["x": .int(500), "y": .int(300)],
                              windowContext: WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")),
            ],
            windowSnapshots: [
                WindowSnapshot(windowId: 42, appName: "Calculator", title: "Calculator",
                               bounds: WindowBounds(x: 100, y: 100, width: 300, height: 400), capturedAtEventIndex: 0)
            ]
        )

        let data = try JSONEncoder().encode(recording)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Top-level required fields
        #expect(json["name"] != nil)
        #expect(json["created_at"] != nil)
        #expect(json["duration_seconds"] != nil)
        #expect(json["events"] != nil)
        #expect(json["window_snapshots"] != nil)

        // Verify event structure
        let events = json["events"] as! [[String: Any]]
        let event = events[0]
        #expect(event["type"] as? String == "click")
        #expect(event["timestamp"] != nil)
        #expect(event["parameters"] != nil)
        #expect(event["window_context"] != nil)

        // Verify window_context structure
        let ctx = event["window_context"] as! [String: Any]
        #expect(ctx["app_name"] != nil)
        #expect(ctx["pid"] != nil)
        #expect(ctx["window_id"] != nil)
        #expect(ctx["window_title"] != nil)

        // Verify snapshot structure
        let snapshots = json["window_snapshots"] as! [[String: Any]]
        let snapshot = snapshots[0]
        #expect(snapshot["window_id"] != nil)
        #expect(snapshot["app_name"] != nil)
        #expect(snapshot["title"] != nil)
        #expect(snapshot["bounds"] != nil)
        #expect(snapshot["captured_at_event_index"] != nil)
    }

    // MARK: - AC2: Click Event Validation

    @Test("Click event contains coordinates and window context")
    func test_clickEvent_hasCoordinatesAndContext() throws {
        let event = RecordedEvent(
            type: .click,
            timestamp: 2.3,
            parameters: ["x": .int(500), "y": .int(300)],
            windowContext: WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")
        )

        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "click")
        let params = json["parameters"] as! [String: Any]
        #expect(params["x"] as? Int == 500)
        #expect(params["y"] as? Int == 300)

        let ctx = json["window_context"] as! [String: Any]
        #expect(ctx["app_name"] as? String == "Calculator")
    }

    // MARK: - AC3: Keyboard Input Event Validation

    @Test("TypeText event contains text content")
    func test_typeTextEvent_hasTextContent() throws {
        let event = RecordedEvent(
            type: .typeText,
            timestamp: 3.5,
            parameters: ["text": .string("Hello World 123")],
            windowContext: nil
        )

        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "type_text")
        let params = json["parameters"] as! [String: Any]
        #expect(params["text"] as? String == "Hello World 123")
    }

    // MARK: - AC4: App Switch Event Validation

    @Test("AppSwitch event contains app name and PID")
    func test_appSwitchEvent_hasAppName() throws {
        let event = RecordedEvent(
            type: .appSwitch,
            timestamp: 0.1,
            parameters: ["app_name": .string("Calculator"), "pid": .int(12345)],
            windowContext: WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")
        )

        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "app_switch")
        let params = json["parameters"] as! [String: Any]
        #expect(params["app_name"] as? String == "Calculator")
        #expect(params["pid"] as? Int == 12345)
    }

    // MARK: - AC6: Error Event Resilience

    @Test("Error event type is serializable and preserves failure info")
    func test_errorEvent_serializable() throws {
        let event = RecordedEvent(
            type: .error,
            timestamp: 5.0,
            parameters: ["message": .string("CGEvent tap creation failed"), "code": .string("tap_creation_failed")],
            windowContext: nil
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RecordedEvent.self, from: data)

        #expect(decoded.type == .error)
        #expect(decoded.parameters["message"] == .string("CGEvent tap creation failed"))
    }

    // MARK: - Scroll Event

    @Test("Scroll event has direction and amount")
    func test_scrollEvent_hasDirectionAndAmount() throws {
        let event = RecordedEvent(
            type: .scroll,
            timestamp: 4.0,
            parameters: ["direction": .string("down"), "amount": .int(5)],
            windowContext: nil
        )

        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let params = json["parameters"] as! [String: Any]
        #expect(params["direction"] as? String == "down")
        #expect(params["amount"] as? Int == 5)
    }

    // MARK: - Hotkey Event

    @Test("Hotkey event has key combination string")
    func test_hotkeyEvent_hasKeys() throws {
        let event = RecordedEvent(
            type: .hotkey,
            timestamp: 1.2,
            parameters: ["keys": .string("cmd+c")],
            windowContext: nil
        )

        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let params = json["parameters"] as! [String: Any]
        #expect(params["keys"] as? String == "cmd+c")
    }

    // MARK: - NFR36: File Size Under 100KB

    @Test("Recording file stays under 100KB for 100 events")
    func test_nfr36_fileSizeUnder100KB() throws {
        var events: [RecordedEvent] = []
        for i in 0..<100 {
            events.append(RecordedEvent(
                type: .click,
                timestamp: Double(i) * 0.1,
                parameters: ["x": .int(i * 10), "y": .int(i * 5)],
                windowContext: WindowContext(appName: "TestApp", pid: 12345, windowId: 1, windowTitle: "Window")
            ))
        }

        let recording = Recording(
            name: "stress_test",
            createdAt: Date(),
            durationSeconds: 10.0,
            events: events,
            windowSnapshots: []
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(recording)

        let sizeKB = Double(data.count) / 1024.0
        #expect(sizeKB < 100.0, "Recording file is \(sizeKB)KB, exceeds 100KB NFR36 limit")
    }

    // MARK: - Empty Recording

    @Test("Empty recording saves and loads correctly")
    func test_emptyRecording_savesCorrectly() throws {
        let recording = Recording(
            name: "empty_test",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 0.0,
            events: [],
            windowSnapshots: []
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(recording)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Recording.self, from: data)

        #expect(decoded.events.isEmpty)
        #expect(decoded.windowSnapshots.isEmpty)
        #expect(decoded.name == "empty_test")
    }

    // MARK: - Special Characters in Recording Name

    @Test("Recording name with special characters is handled correctly")
    func test_specialCharacters_nameHandled() throws {
        let recording = Recording(
            name: "打开文件 & 编辑 (v2.0)",
            createdAt: Date(),
            durationSeconds: 5.0,
            events: [
                RecordedEvent(type: .click, timestamp: 1.0, parameters: ["x": .int(100)], windowContext: nil),
            ],
            windowSnapshots: []
        )

        let data = try JSONEncoder().encode(recording)
        let decoded = try JSONDecoder().decode(Recording.self, from: data)
        #expect(decoded.name == "打开文件 & 编辑 (v2.0)")
    }

    // MARK: - Timestamp Ordering

    @Test("Recording events maintain timestamp ordering")
    func test_events_maintainTimestampOrder() throws {
        let events = [
            RecordedEvent(type: .appSwitch, timestamp: 0.1, parameters: ["app_name": .string("App")], windowContext: nil),
            RecordedEvent(type: .click, timestamp: 2.3, parameters: ["x": .int(500)], windowContext: nil),
            RecordedEvent(type: .typeText, timestamp: 3.5, parameters: ["text": .string("hi")], windowContext: nil),
        ]

        let recording = Recording(name: "ordered", createdAt: Date(), durationSeconds: 5.0, events: events, windowSnapshots: [])

        let data = try JSONEncoder().encode(recording)
        let decoded = try JSONDecoder().decode(Recording.self, from: data)

        for i in 0..<(decoded.events.count - 1) {
            #expect(decoded.events[i].timestamp <= decoded.events[i + 1].timestamp)
        }
    }

    // MARK: - Recording Does Not Contain Base64 Data (NFR36)

    @Test("Recording JSON does not contain base64 image data")
    func test_recording_noBase64Data() throws {
        let recording = Recording(
            name: "clean_test",
            createdAt: Date(),
            durationSeconds: 1.0,
            events: [
                RecordedEvent(type: .click, timestamp: 0.5, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
            ],
            windowSnapshots: [
                WindowSnapshot(windowId: 1, appName: "App", title: "App",
                               bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600), capturedAtEventIndex: 0)
            ]
        )

        let data = try JSONEncoder().encode(recording)
        let jsonString = String(data: data, encoding: .utf8)!

        // Check no base64-like patterns (long alphanumeric strings)
        let base64Pattern = /[A-Za-z0-9+\/]{100,}/
        #expect(jsonString.firstMatch(of: base64Pattern) == nil, "Recording should not contain base64 data")
    }
}
