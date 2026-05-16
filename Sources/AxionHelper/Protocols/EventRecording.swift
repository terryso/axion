import AxionCore
import Foundation

protocol EventRecording: Sendable {
    func startRecording() throws
    func stopRecording() -> RecordingResult
    var isRecording: Bool { get }
}

/// Result of stopping a recording session.
struct RecordingResult: Sendable {
    let events: [RecordedEvent]
    let windowSnapshots: [WindowSnapshot]
}
