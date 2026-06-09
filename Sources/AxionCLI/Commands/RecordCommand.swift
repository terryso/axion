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
        let write: (String) -> Void = { fputs($0 + "\n", stdout); fflush(stdout) }

        // 1. Start Helper via HelperProcessManager
        let helperManager = HelperProcessManager()
        write("[axion] 正在启动 Helper...")
        try await helperManager.start()

        // 2. Call start_recording
        write("[axion] 正在启动录制模式...")
        _ = try await helperManager.callTool(name: "start_recording", arguments: [:])
        write("[axion] 录制中... 按 Ctrl-C 结束录制")

        // 3. Set up SIGINT signal handler
        let startTime = Date()
        let recordingName = name

        // Use DispatchSource to catch SIGINT
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.resume()

        // 4. Wait for SIGINT
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            source.setEventHandler {
                source.cancel()
                continuation.resume()
            }
        }

        // 5. Stop recording and save
        write("[axion] 正在停止录制...")

        do {
            let stopResult = try await helperManager.callTool(name: "stop_recording", arguments: [:])
            let events = Self.parseRecordingEvents(from: stopResult)
            let snapshots = Self.parseWindowSnapshots(from: stopResult)
            let elapsed = Date().timeIntervalSince(startTime)
            let recording = Recording(
                name: recordingName,
                createdAt: startTime,
                durationSeconds: elapsed,
                events: events,
                windowSnapshots: snapshots
            )

            let recordingsDir = ConfigManager.recordingsDirectory
            try FileManager.default.createDirectory(atPath: recordingsDir, withIntermediateDirectories: true)

            let filePath = (recordingsDir as NSString).appendingPathComponent("\(sanitizeFileName(recordingName)).json")
            let data = try axionPersistentEncoder.encode(recording)
            try data.write(to: URL(fileURLWithPath: filePath))

            write("[axion] 录制已保存: \(filePath)")
            write("[axion] 录制摘要: \(events.count) 个事件，耗时 \(String(format: "%.1f", elapsed)) 秒")
        } catch {
            write("[axion] 保存录制失败: \(error.localizedDescription)")
        }

        await helperManager.stop()
    }

    // MARK: - Internal Helpers (testable)

    static func parseRecordingEvents(from result: String) -> [RecordedEvent] {
        parseJSONEncodedArray(from: result, key: "events")
    }

    static func parseWindowSnapshots(from result: String) -> [WindowSnapshot] {
        parseJSONEncodedArray(from: result, key: "window_snapshots")
    }
}
