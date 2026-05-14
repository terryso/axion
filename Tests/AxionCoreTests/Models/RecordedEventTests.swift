import Foundation
import Testing

@testable import AxionCore

// MARK: - RecordedEventTests

@Suite("RecordedEvent Model Tests")
struct RecordedEventTests {

    // MARK: - WindowContext

    @Test("WindowContext Codable round-trip preserves all fields")
    func test_windowContext_roundTrip() throws {
        let original = WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowContext.self, from: data)
        #expect(decoded == original)
    }

    @Test("WindowContext JSON uses snake_case keys")
    func test_windowContext_snakeCaseKeys() throws {
        let ctx = WindowContext(appName: "Safari", pid: 100, windowId: 1, windowTitle: "Welcome")
        let data = try JSONEncoder().encode(ctx)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["app_name"] != nil)
        #expect(json["window_id"] != nil)
        #expect(json["window_title"] != nil)
    }

    // MARK: - JSONValue

    @Test("JSONValue Codable round-trip for all variants")
    func test_jsonValue_roundTrip() throws {
        let values: [JSONValue] = [.string("hello"), .int(42), .double(3.14), .bool(true), .null]
        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            #expect(decoded == value)
        }
    }

    // MARK: - RecordedEvent

    @Test("RecordedEvent Codable round-trip with click event")
    func test_recordedEvent_click_roundTrip() throws {
        let original = RecordedEvent(
            type: .click,
            timestamp: 2.3,
            parameters: ["x": .int(500), "y": .int(300)],
            windowContext: WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecordedEvent.self, from: data)
        #expect(decoded == original)
    }

    @Test("RecordedEvent Codable round-trip with typeText event")
    func test_recordedEvent_typeText_roundTrip() throws {
        let original = RecordedEvent(
            type: .typeText,
            timestamp: 3.5,
            parameters: ["text": .string("17")],
            windowContext: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecordedEvent.self, from: data)
        #expect(decoded == original)
    }

    @Test("RecordedEvent Codable round-trip with appSwitch event")
    func test_recordedEvent_appSwitch_roundTrip() throws {
        let original = RecordedEvent(
            type: .appSwitch,
            timestamp: 0.1,
            parameters: ["app_name": .string("Calculator"), "pid": .int(12345)],
            windowContext: WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecordedEvent.self, from: data)
        #expect(decoded == original)
    }

    @Test("RecordedEvent JSON uses snake_case keys")
    func test_recordedEvent_snakeCaseKeys() throws {
        let event = RecordedEvent(
            type: .click, timestamp: 1.0,
            parameters: ["x": .int(100)],
            windowContext: WindowContext(appName: "Test", pid: 1, windowId: 1, windowTitle: "T")
        )
        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] != nil)
        #expect(json["window_context"] != nil)
        #expect(json["type_text"] == nil)  // EventType uses rawValue
    }

    @Test("RecordedEvent.EventType raw values are correct")
    func test_eventType_rawValues() {
        #expect(RecordedEvent.EventType.click.rawValue == "click")
        #expect(RecordedEvent.EventType.typeText.rawValue == "type_text")
        #expect(RecordedEvent.EventType.hotkey.rawValue == "hotkey")
        #expect(RecordedEvent.EventType.appSwitch.rawValue == "app_switch")
        #expect(RecordedEvent.EventType.scroll.rawValue == "scroll")
        #expect(RecordedEvent.EventType.error.rawValue == "error")
    }

    // MARK: - WindowSnapshot

    @Test("WindowSnapshot Codable round-trip")
    func test_windowSnapshot_roundTrip() throws {
        let original = WindowSnapshot(
            windowId: 42, appName: "Calculator", title: "Calculator",
            bounds: WindowBounds(x: 100, y: 100, width: 300, height: 400),
            capturedAtEventIndex: 0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowSnapshot.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Recording

    @Test("Recording Codable round-trip with full data")
    func test_recording_fullRoundTrip() throws {
        let events = [
            RecordedEvent(type: .appSwitch, timestamp: 0.1, parameters: ["app_name": .string("Calculator")], windowContext: nil),
            RecordedEvent(type: .click, timestamp: 2.3, parameters: ["x": .int(500), "y": .int(300)], windowContext: nil),
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
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Recording.self, from: data)
        #expect(decoded == original)
    }

    @Test("Recording JSON uses snake_case keys")
    func test_recording_snakeCaseKeys() throws {
        let recording = Recording(
            name: "test", createdAt: Date(), durationSeconds: 5.0,
            events: [], windowSnapshots: []
        )
        let data = try JSONEncoder().encode(recording)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["created_at"] != nil)
        #expect(json["duration_seconds"] != nil)
        #expect(json["window_snapshots"] != nil)
    }
}
