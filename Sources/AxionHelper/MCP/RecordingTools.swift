import MCP
import MCPTool

enum RecordingTools {
    static func register(to server: MCPServer) async throws {
        try await server.register {
            StartRecordingTool.self
            StopRecordingTool.self
        }
    }
}

// MARK: - Recording Tools (Story 9.1)

@Tool
struct StartRecordingTool {
    static let name = "start_recording"
    static let description = "Start recording user input events (mouse clicks, keyboard, app switches) in listen-only mode"

    func perform() async throws -> String {
        do {
            try ServiceContainer.shared.eventRecorder.startRecording()
            let result = RecordingActionResult(
                success: true, action: "start_recording",
                message: "Recording started. Events are being captured in listen-only mode."
            )
            return encodeToolResult(result)
        } catch let error as EventRecorderError {
            return encodeToolError(error)
        }
    }
}

@Tool
struct StopRecordingTool {
    static let name = "stop_recording"
    static let description = "Stop recording and return all captured events as JSON"

    func perform() async throws -> String {
        let recordingResult = ServiceContainer.shared.eventRecorder.stopRecording()

        let eventStrings = recordingResult.events.compactMap { event -> String? in
            encodeToolResult(event).nilIfEmpty
        }

        let snapshotStrings = recordingResult.windowSnapshots.compactMap { snapshot -> String? in
            encodeToolResult(snapshot).nilIfEmpty
        }

        let result = StopRecordingResult(
            success: true, action: "stop_recording",
            eventCount: recordingResult.events.count, events: eventStrings,
            windowSnapshots: snapshotStrings
        )
        return encodeToolResult(result)
    }
}

// Small helper to filter out empty "{}" results from compactMap
extension String {
    var nilIfEmpty: String? { self == "{}" ? nil : self }
}
