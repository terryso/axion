import Foundation
import OpenAgentSDK

/// Codable wrapper for persisting AgentSSEEvent to JSONL.
private struct PersistedEvent: Codable, Equatable, Sendable {
    let eventType: String
    let stepStarted: StepStartedData?
    let stepCompleted: StepCompletedData?
    let runCompleted: RunCompletedData?

    init(from event: AgentSSEEvent) {
        self.eventType = event.eventType
        switch event {
        case .stepStarted(let data):
            self.stepStarted = data
            self.stepCompleted = nil
            self.runCompleted = nil
        case .stepCompleted(let data):
            self.stepStarted = nil
            self.stepCompleted = data
            self.runCompleted = nil
        case .runCompleted(let data):
            self.stepStarted = nil
            self.stepCompleted = nil
            self.runCompleted = data
        }
    }

    func toSSEEvent() -> AgentSSEEvent? {
        switch eventType {
        case "step_started":
            guard let data = stepStarted else { return nil }
            return .stepStarted(data)
        case "step_completed":
            guard let data = stepCompleted else { return nil }
            return .stepCompleted(data)
        case "run_completed":
            guard let data = runCompleted else { return nil }
            return .runCompleted(data)
        default:
            return nil
        }
    }
}

/// Disk persistence for Axion's rich TrackedRun records and SSE events.
/// Uses `~/.axion/api-runs/` directory.
struct AxionRunPersistence: Sendable {

    private let customBaseDirectory: String?
    private let fileLock: NSLock

    init(baseDirectory: String? = nil) {
        self.customBaseDirectory = baseDirectory
        self.fileLock = NSLock()
    }

    // MARK: - Path Helpers

    func runsDirectory() -> String {
        if let custom = customBaseDirectory {
            return custom
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".axion/api-runs")
    }

    func runDirectory(runId: String) -> String {
        let dir = (runsDirectory() as NSString).appendingPathComponent(runId)
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return dir
    }

    // MARK: - TrackedRun Record Persistence

    func persistRecord(_ run: TrackedRun) throws {
        let dir = runDirectory(runId: run.runId)
        let finalPath = (dir as NSString).appendingPathComponent("api-output.json")
        let data = try JSONEncoder().encode(run)
        try data.write(to: URL(fileURLWithPath: finalPath), options: .atomic)
    }

    func loadRecord(runId: String) -> TrackedRun? {
        let dir = (runsDirectory() as NSString).appendingPathComponent(runId)
        let path = (dir as NSString).appendingPathComponent("api-output.json")
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else { return nil }
        return try? JSONDecoder().decode(TrackedRun.self, from: data)
    }

    func loadAllPersistedRuns() -> [TrackedRun] {
        let baseDir = runsDirectory()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            atPath: baseDir
        ) else { return [] }
        return contents.compactMap { loadRecord(runId: $0) }
    }

    // MARK: - SSE Event Persistence

    func persistEvent(runId: String, event: AgentSSEEvent) throws {
        let dir = runDirectory(runId: runId)
        let eventsPath = (dir as NSString).appendingPathComponent("api-events.jsonl")
        let wrapper = PersistedEvent(from: event)
        var data = try JSONEncoder().encode(wrapper)
        data.append(0x0A)

        fileLock.lock()
        defer { fileLock.unlock() }

        if FileManager.default.fileExists(atPath: eventsPath) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: eventsPath))
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try data.write(to: URL(fileURLWithPath: eventsPath))
        }
    }

    func loadEvents(runId: String) -> [AgentSSEEvent] {
        let dir = (runsDirectory() as NSString).appendingPathComponent(runId)
        let path = (dir as NSString).appendingPathComponent("api-events.jsonl")
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8)
        else { return [] }

        return content.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let wrapper = try? JSONDecoder().decode(PersistedEvent.self, from: data)
            else { return nil }
            return wrapper.toSSEEvent()
        }
    }

    // MARK: - Safe Wrappers

    func persistRecordSafely(_ run: TrackedRun) {
        do {
            try persistRecord(run)
        } catch {
            print("[RunPersistence] Warning: failed to persist record for run \(run.runId): \(error)")
        }
    }
}
