import Foundation
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch let error as EventRecorderError {
            let payload = ToolErrorPayload(
                error: error.errorCode,
                message: error.localizedDescription,
                suggestion: error.suggestion
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}

@Tool
struct StopRecordingTool {
    static let name = "stop_recording"
    static let description = "Stop recording and return all captured events as JSON"

    func perform() async throws -> String {
        let recordingResult = ServiceContainer.shared.eventRecorder.stopRecording()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let eventStrings = recordingResult.events.compactMap { event -> String? in
            guard let data = try? encoder.encode(event) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        let snapshotStrings = recordingResult.windowSnapshots.compactMap { snapshot -> String? in
            guard let data = try? encoder.encode(snapshot) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        let result = StopRecordingResult(
            success: true, action: "stop_recording",
            eventCount: recordingResult.events.count, events: eventStrings,
            windowSnapshots: snapshotStrings
        )
        let data = try encoder.encode(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
