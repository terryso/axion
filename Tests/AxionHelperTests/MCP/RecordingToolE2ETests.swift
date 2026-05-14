import AxionCore
import Foundation
import Testing

@testable import AxionHelper

// MARK: - RecordingToolE2ETests
// E2E tests for StartRecordingTool and StopRecordingTool MCP tools
// Uses ServiceContainerFixture to inject ToolTestEventRecorder mock

@Suite("Recording MCP Tool E2E Tests")
struct RecordingToolE2ETests {

    // MARK: - StartRecordingTool

    @Test("StartRecordingTool returns success JSON when recording starts")
    func test_startRecording_success() async throws {
        let mock = ToolTestEventRecorder()
        let restore = ServiceContainerFixture.apply(eventRecorder: mock)
        defer { restore() }

        let tool = StartRecordingTool()
        let result = try await tool.perform()

        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["success"] as? Bool == true)
        #expect(json["action"] as? String == "start_recording")
        #expect(json["message"] != nil)
    }

    @Test("EventRecorderError alreadyRecording produces correct error payload")
    func test_startRecording_errorPayloadFormat() {
        let error = EventRecorderError.alreadyRecording
        // Verify the error produces the 3-field ToolErrorPayload format (error/message/suggestion)
        #expect(!error.errorCode.isEmpty)
        #expect(!error.localizedDescription.isEmpty)
        #expect(!error.suggestion.isEmpty)
        #expect(error.errorCode == "already_recording")
    }

    // MARK: - StopRecordingTool

    @Test("StopRecordingTool returns empty events when no recording")
    func test_stopRecording_noEvents() async throws {
        let mock = ToolTestEventRecorder()
        let restore = ServiceContainerFixture.apply(eventRecorder: mock)
        defer { restore() }

        let tool = StopRecordingTool()
        let result = try await tool.perform()

        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["success"] as? Bool == true)
        #expect(json["action"] as? String == "stop_recording")
        #expect(json["event_count"] as? Int == 0)
        #expect(json["window_snapshots"] != nil)
    }

    @Test("StopRecordingTool returns captured events as JSON strings")
    func test_stopRecording_withEvents() async throws {
        let mock = ToolTestEventRecorder()

        let clickEvent = RecordedEvent(
            type: .click,
            timestamp: 1.5,
            parameters: ["x": .int(500), "y": .int(300)],
            windowContext: WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")
        )
        let typeEvent = RecordedEvent(
            type: .typeText,
            timestamp: 3.0,
            parameters: ["text": .string("hello")],
            windowContext: nil
        )
        mock.stubEvents = [clickEvent, typeEvent]

        let restore = ServiceContainerFixture.apply(eventRecorder: mock)
        defer { restore() }

        let tool = StopRecordingTool()
        let result = try await tool.perform()

        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["success"] as? Bool == true)
        #expect(json["event_count"] as? Int == 2)

        let events = json["events"] as? [String]
        #expect(events?.count == 2)

        let firstEventData = events![0].data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RecordedEvent.self, from: firstEventData)
        #expect(decoded.type == .click)
        #expect(decoded.timestamp == 1.5)
    }

    @Test("StopRecordingTool returns all event types correctly")
    func test_stopRecording_allEventTypes() async throws {
        let mock = ToolTestEventRecorder()

        mock.stubEvents = [
            RecordedEvent(type: .click, timestamp: 0.5, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
            RecordedEvent(type: .typeText, timestamp: 1.0, parameters: ["text": .string("abc")], windowContext: nil),
            RecordedEvent(type: .hotkey, timestamp: 1.5, parameters: ["keys": .string("cmd+c")], windowContext: nil),
            RecordedEvent(type: .appSwitch, timestamp: 2.0, parameters: ["app_name": .string("Safari"), "pid": .int(999)], windowContext: nil),
            RecordedEvent(type: .scroll, timestamp: 2.5, parameters: ["direction": .string("down"), "amount": .int(3)], windowContext: nil),
            RecordedEvent(type: .error, timestamp: 3.0, parameters: ["message": .string("test error")], windowContext: nil),
        ]

        let restore = ServiceContainerFixture.apply(eventRecorder: mock)
        defer { restore() }

        let tool = StopRecordingTool()
        let result = try await tool.perform()

        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let events = json["events"] as? [String]
        #expect(events?.count == 6)

        let decoder = JSONDecoder()
        let types = events!.compactMap { str -> RecordedEvent.EventType? in
            guard let d = str.data(using: .utf8) else { return nil }
            return try? decoder.decode(RecordedEvent.self, from: d).type
        }
        #expect(types == [.click, .typeText, .hotkey, .appSwitch, .scroll, .error])
    }

    @Test("StopRecordingTool preserves window context in events")
    func test_stopRecording_preservesWindowContext() async throws {
        let mock = ToolTestEventRecorder()
        let ctx = WindowContext(appName: "Calculator", pid: 12345, windowId: 42, windowTitle: "Calculator")
        mock.stubEvents = [
            RecordedEvent(type: .click, timestamp: 1.0, parameters: ["x": .int(100), "y": .int(200)], windowContext: ctx),
        ]

        let restore = ServiceContainerFixture.apply(eventRecorder: mock)
        defer { restore() }

        let tool = StopRecordingTool()
        let result = try await tool.perform()

        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let events = json["events"] as! [String]

        let decoded = try JSONDecoder().decode(RecordedEvent.self, from: events[0].data(using: .utf8)!)
        #expect(decoded.windowContext == ctx)
        #expect(decoded.windowContext?.appName == "Calculator")
        #expect(decoded.windowContext?.pid == 12345)
    }

    @Test("StopRecordingTool JSON has snake_case event_count key")
    func test_stopRecording_snakeCaseKeys() async throws {
        let mock = ToolTestEventRecorder()
        let restore = ServiceContainerFixture.apply(eventRecorder: mock)
        defer { restore() }

        let tool = StopRecordingTool()
        let result = try await tool.perform()

        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["event_count"] != nil)
        #expect(json["eventCount"] == nil)
    }
}

// MARK: - Tool Test Mock

final class ToolTestEventRecorder: EventRecording, @unchecked Sendable {
    private var _isRecording = false
    var stubEvents: [RecordedEvent] = []
    var stubSnapshots: [WindowSnapshot] = []
    var shouldThrowOnStart = false

    var isRecording: Bool { _isRecording }

    func startRecording() throws {
        if shouldThrowOnStart {
            throw EventRecorderError.alreadyRecording
        }
        _isRecording = true
    }

    func stopRecording() -> RecordingResult {
        _isRecording = false
        return RecordingResult(events: stubEvents, windowSnapshots: stubSnapshots)
    }
}
