import AxionCore
import Foundation
import Testing

@testable import AxionCLI

// MARK: - RecordCommandTests

@Suite("RecordCommand Tests")
struct RecordCommandTests {

    @Test("recordingsDirectory returns path under ~/.axion/recordings")
    func test_recordingsDirectory_underAxionDir() {
        let dir = RecordCommand.recordingsDirectory()
        #expect(dir.hasSuffix(".axion/recordings"))
        #expect(dir.contains(".axion"))
    }

    @Test("sanitizeFileName strips path separators and traversal")
    func test_sanitizeFileName_stripsPathChars() {
        #expect(RecordCommand.sanitizeFileName("../../../etc/passwd") == "______etc_passwd")
        #expect(RecordCommand.sanitizeFileName("my/recording") == "my_recording")
        #expect(RecordCommand.sanitizeFileName("normal name") == "normal name")
        #expect(RecordCommand.sanitizeFileName("") == "untitled")
        #expect(RecordCommand.sanitizeFileName("test:file") == "test_file")
    }

    @Test("parseRecordingEvents returns empty array for invalid JSON")
    func test_parseEvents_invalidJSON_returnsEmpty() {
        let events = RecordCommand.parseRecordingEvents(from: "not json")
        #expect(events.isEmpty)
    }

    @Test("parseRecordingEvents returns empty array for missing events key")
    func test_parseEvents_missingEventsKey_returnsEmpty() {
        let events = RecordCommand.parseRecordingEvents(from: "{\"success\":true}")
        #expect(events.isEmpty)
    }

    @Test("parseRecordingEvents parses valid event JSON strings")
    func test_parseEvents_validEvents() {
        // Events array contains JSON-encoded strings (as returned by StopRecordingTool)
        let eventJSON = #"{"type":"click","timestamp":1.5,"parameters":{"x":100,"y":200},"window_context":null}"#
        // Escape the event JSON as a string within the wrapper JSON
        let escapedEvent = eventJSON
            .replacingOccurrences(of: "\"", with: "\\\"")
        let wrapperJSON = """
        {"success":true,"action":"stop_recording","event_count":1,"events":["\(escapedEvent)"],"window_snapshots":[]}
        """

        let events = RecordCommand.parseRecordingEvents(from: wrapperJSON)
        #expect(events.count == 1)
        #expect(events[0].type == .click)
    }

    @Test("parseRecordingEvents handles multiple events")
    func test_parseEvents_multipleEvents() {
        let event1 = #"{"type":"app_switch","timestamp":0.1,"parameters":{"app_name":"Calculator"},"window_context":null}"#
        let event2 = #"{"type":"type_text","timestamp":1.0,"parameters":{"text":"hello"},"window_context":null}"#

        let escaped1 = event1.replacingOccurrences(of: "\"", with: "\\\"")
        let escaped2 = event2.replacingOccurrences(of: "\"", with: "\\\"")
        let wrapper = """
        {"success":true,"action":"stop_recording","event_count":2,"events":["\(escaped1)","\(escaped2)"],"window_snapshots":[]}
        """

        let events = RecordCommand.parseRecordingEvents(from: wrapper)
        #expect(events.count == 2)
        #expect(events[0].type == .appSwitch)
        #expect(events[1].type == .typeText)
    }

    @Test("parseRecordingEvents skips malformed event entries")
    func test_parseEvents_skipsMalformed() {
        let event1 = #"{"type":"click","timestamp":1.0,"parameters":{"x":50,"y":60},"window_context":null}"#
        let escaped1 = event1.replacingOccurrences(of: "\"", with: "\\\"")
        let wrapper = """
        {"success":true,"event_count":2,"events":["\(escaped1)","not valid json"],"window_snapshots":[]}
        """

        let events = RecordCommand.parseRecordingEvents(from: wrapper)
        #expect(events.count == 1)
        #expect(events[0].type == .click)
    }

    @Test("parseWindowSnapshots parses snapshot JSON strings")
    func test_parseWindowSnapshots_valid() {
        let snapshotJSON = #"{"window_id":42,"app_name":"Calculator","title":"Calculator","bounds":{"x":100,"y":100,"width":300,"height":400},"captured_at_event_index":0}"#
        let escaped = snapshotJSON.replacingOccurrences(of: "\"", with: "\\\"")
        let wrapper = """
        {"events":[],"window_snapshots":["\(escaped)"]}
        """

        let snapshots = RecordCommand.parseWindowSnapshots(from: wrapper)
        #expect(snapshots.count == 1)
        #expect(snapshots[0].windowId == 42)
        #expect(snapshots[0].bounds.width == 300)
    }

    @Test("parseWindowSnapshots returns empty for missing key")
    func test_parseWindowSnapshots_missingKey() {
        let snapshots = RecordCommand.parseWindowSnapshots(from: "{\"events\":[]}")
        #expect(snapshots.isEmpty)
    }
}
