import ArgumentParser
import AxionCore
import Foundation

struct RecordCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "录制桌面操作"
    )

    @Argument(help: "录制名称")
    var name: String

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    mutating func run() async throws {
        let output = TerminalOutput()

        // 1. Start Helper via HelperProcessManager
        let helperManager = HelperProcessManager()
        output.write("[axion] 正在启动 Helper...")
        try await helperManager.start()

        // 2. Call start_recording
        output.write("[axion] 正在启动录制模式...")
        _ = try await helperManager.callTool(name: "start_recording", arguments: [:])
        output.write("[axion] 录制中... 按 Ctrl-C 结束录制")

        // 3. Capture context for SIGINT handler
        let startTime = Date()
        let recordingName = name
        nonisolated(unsafe) let write = output.write

        // 4. Use withTaskCancellationHandler for clean shutdown
        try await withTaskCancellationHandler {
            // Keep running until cancelled (Ctrl-C)
            try await _Concurrency.Task.sleep(nanoseconds: UInt64(Int64.max))
        } onCancel: {
            _Concurrency.Task {
                let elapsed = Date().timeIntervalSince(startTime)
                write("[axion] 正在停止录制...")

                do {
                    let stopResult = try await helperManager.callTool(name: "stop_recording", arguments: [:])
                    let events = Self.parseRecordingEvents(from: stopResult)
                    let snapshots = Self.parseWindowSnapshots(from: stopResult)
                    let recording = Recording(
                        name: recordingName,
                        createdAt: startTime,
                        durationSeconds: elapsed,
                        events: events,
                        windowSnapshots: snapshots
                    )

                    let recordingsDir = Self.recordingsDirectory()
                    try FileManager.default.createDirectory(atPath: recordingsDir, withIntermediateDirectories: true)

                    let filePath = (recordingsDir as NSString).appendingPathComponent("\(Self.sanitizeFileName(recordingName)).json")
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(recording)
                    try data.write(to: URL(fileURLWithPath: filePath))

                    write("[axion] 录制已保存: \(filePath)")
                    write("[axion] 录制摘要: \(events.count) 个事件，耗时 \(String(format: "%.1f", elapsed)) 秒")
                } catch {
                    write("[axion] 保存录制失败: \(error.localizedDescription)")
                }

                await helperManager.stop()
            }
        }
    }

    // MARK: - Internal Helpers (testable)

    static func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.controlCharacters)
        let filtered = name.components(separatedBy: invalid).joined(separator: "_")
        let trimmed = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.isEmpty ? "untitled" : trimmed
        // Collapse ".." and "." segments to prevent traversal
        return safe.replacingOccurrences(of: "..", with: "_")
            .replacingOccurrences(of: "./", with: "_/")
    }

    static func recordingsDirectory() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return (homeDir as NSString).appendingPathComponent(".axion/recordings")
    }

    static func parseRecordingEvents(from result: String) -> [RecordedEvent] {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventStrings = json["events"] as? [String] else {
            return []
        }

        let decoder = JSONDecoder()
        return eventStrings.compactMap { eventString in
            guard let eventData = eventString.data(using: .utf8) else { return nil }
            return try? decoder.decode(RecordedEvent.self, from: eventData)
        }
    }

    static func parseWindowSnapshots(from result: String) -> [WindowSnapshot] {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapshotStrings = json["window_snapshots"] as? [String] else {
            return []
        }

        let decoder = JSONDecoder()
        return snapshotStrings.compactMap { snapshotString in
            guard let snapshotData = snapshotString.data(using: .utf8) else { return nil }
            return try? decoder.decode(WindowSnapshot.self, from: snapshotData)
        }
    }
}
