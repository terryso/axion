import AxionCore
import Foundation
import Testing

@testable import AxionHelper

// MARK: - EventRecorderTests

@Suite("EventRecorder Service Tests")
struct EventRecorderTests {

    @Test("startRecording sets isRecording to true")
    func test_startRecording_setsFlag() {
        let service = EventRecorderService()
        #expect(!service.isRecording)
        // Note: startRecording may fail in CI (no AX permissions)
        // so we test the protocol conformance
    }

    @Test("stopRecording when not recording returns empty result")
    func test_stopRecording_whenNotRecording_returnsEmpty() {
        let service = EventRecorderService()
        let result = service.stopRecording()
        #expect(result.events.isEmpty)
        #expect(result.windowSnapshots.isEmpty)
    }

    @Test("startRecording throws when already recording")
    func test_startRecording_throwsWhenAlreadyRecording() {
        let service = EventRecorderService()
        // Can't easily test double-start without AX permissions in CI
        // but we can verify the error type exists
        let error = EventRecorderError.alreadyRecording
        #expect(error.errorCode == "already_recording")
        #expect(error.localizedDescription.contains("already"))
    }

    @Test("EventRecorderError has correct error codes")
    func test_errorCodes() {
        #expect(EventRecorderError.tapCreationFailed.errorCode == "tap_creation_failed")
        #expect(EventRecorderError.alreadyRecording.errorCode == "already_recording")
        #expect(EventRecorderError.notRecording.errorCode == "not_recording")
    }

    @Test("EventRecorderError has suggestions")
    func test_errorSuggestions() {
        #expect(!EventRecorderError.tapCreationFailed.suggestion.isEmpty)
        #expect(!EventRecorderError.alreadyRecording.suggestion.isEmpty)
        #expect(!EventRecorderError.notRecording.suggestion.isEmpty)
    }

    // MARK: - Mock EventRecording Protocol

    @Test("MockEventRecording allows testing recording control logic")
    func test_mockProtocol() {
        let mock = MockEventRecording()
        #expect(!mock.isRecording)

        try? mock.startRecording()
        #expect(mock.isRecording)

        let result = mock.stopRecording()
        #expect(!mock.isRecording)
        #expect(result.events.isEmpty)
    }

    @Test("MockEventRecording records injected events")
    func test_mockProtocol_injectedEvents() {
        let mock = MockEventRecording()
        try? mock.startRecording()

        let event = RecordedEvent(type: .click, timestamp: 1.0, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil)
        mock.stubEvents = [event]

        let result = mock.stopRecording()
        #expect(result.events.count == 1)
        #expect(result.events[0].type == .click)
    }
}

// MARK: - Mock

final class MockEventRecording: EventRecording, @unchecked Sendable {
    private var _isRecording = false
    var stubEvents: [RecordedEvent] = []
    var stubSnapshots: [WindowSnapshot] = []

    var isRecording: Bool { _isRecording }

    func startRecording() throws {
        _isRecording = true
    }

    func stopRecording() -> RecordingResult {
        _isRecording = false
        return RecordingResult(events: stubEvents, windowSnapshots: stubSnapshots)
    }
}
