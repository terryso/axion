import Foundation
import OpenAgentSDK

/// Lightweight run coordinator that replaces AxionRunTracker + AxionRunPersistence.
/// Stores Axion's rich TrackedRun in memory, uses SDK's RunPersistenceService for
/// SSE event persistence, and writes Axion TrackedRun records to disk directly.
actor RunCoordinator {

    private var runs: [String: TrackedRun] = [:]
    private static let maxTrackedRuns = 1000

    private let eventBroadcaster: EventBroadcaster?
    private let persistenceService: RunPersistenceService?

    init(
        eventBroadcaster: EventBroadcaster? = nil,
        persistenceService: RunPersistenceService? = nil
    ) {
        self.eventBroadcaster = eventBroadcaster
        self.persistenceService = persistenceService
    }

    // MARK: - Run Lifecycle

    private nonisolated(unsafe) static let runIdDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func submitRun(task: String, request: OpenAgentSDK.CreateRunRequest = OpenAgentSDK.CreateRunRequest(task: "")) -> String {
        let runId = Self.generateRunId()
        _submitRun(runId: runId, task: task, request: request)
        return runId
    }

    /// Submit a run with a pre-assigned runId (e.g. from SDK's RunTracker).
    func submitRunWithId(_ runId: String, task: String, request: OpenAgentSDK.CreateRunRequest = OpenAgentSDK.CreateRunRequest(task: "")) {
        _submitRun(runId: runId, task: task, request: request)
    }

    private func _submitRun(runId: String, task: String, request: OpenAgentSDK.CreateRunRequest) {
        let submittedAt = Self.isoFormatter.string(from: Date())

        let run = TrackedRun(
            runId: runId,
            task: task,
            status: .running,
            submittedAt: submittedAt,
            live: true,
            allowForeground: request.allowForeground ?? false
        )
        runs[runId] = run
        persistRecordSafely(run)

        evictOldRuns()
    }

    func updateRun(
        runId: String,
        status: APIRunStatus,
        steps: [StepSummary],
        durationMs: Int?,
        replanCount: Int,
        costTelemetry: CostTelemetry? = nil,
        error: String? = nil
    ) async {
        guard runs[runId] != nil else { return }

        let completedAt = Self.isoFormatter.string(from: Date())

        runs[runId]?.status = status
        runs[runId]?.completedAt = completedAt
        runs[runId]?.totalSteps = steps.count
        runs[runId]?.durationMs = durationMs
        runs[runId]?.replanCount = replanCount
        runs[runId]?.steps = steps
        runs[runId]?.costTelemetry = costTelemetry
        runs[runId]?.error = error
        runs[runId]?.exitCode = (status == .failed) ? 1 : (status == .completed ? 0 : nil)

        if let broadcaster = eventBroadcaster {
            let event = AgentSSEEvent.runCompleted(RunCompletedData(
                runId: runId,
                finalStatus: status.rawValue,
                totalSteps: steps.count,
                durationMs: durationMs
            ))
            await broadcaster.emit(runId: runId, event: event)
            await broadcaster.complete(runId: runId)
        }

        if let run = runs[runId] {
            persistRecordSafely(run)
        }
    }

    func updateRunResult(runId: String, result: ApiTaskResult) {
        guard runs[runId] != nil else { return }
        runs[runId]?.result = result
        if let run = runs[runId] {
            persistRecordSafely(run)
        }
    }

    func updateRunIntervention(runId: String, intervention: InterventionData) {
        guard runs[runId] != nil else { return }
        runs[runId]?.intervention = intervention
        if let run = runs[runId] {
            persistRecordSafely(run)
        }
    }

    // MARK: - Query

    func restoreRun(_ run: TrackedRun) {
        runs[run.runId] = run
    }

    func getRun(runId: String) -> TrackedRun? {
        runs[runId]
    }

    func listRuns() -> [TrackedRun] {
        Array(runs.values)
    }

    // MARK: - Private

    private static func generateRunId() -> String {
        let datePart = runIdDateFormatter.string(from: Date())
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomPart = String((0..<6).map { _ in chars.randomElement()! })
        return "\(datePart)-\(randomPart)"
    }

    private func evictOldRuns() {
        if runs.count > Self.maxTrackedRuns {
            let completedKeys = runs.filter { $0.value.status != .running }
                .sorted { $0.value.submittedAt < $1.value.submittedAt }
                .map(\.key)
            let evictCount = min(completedKeys.count, runs.count - Self.maxTrackedRuns)
            for key in completedKeys.prefix(evictCount) {
                runs.removeValue(forKey: key)
            }
        }
    }

    private func persistRecordSafely(_ run: TrackedRun) {
        guard let persistence = persistenceService else { return }
        do {
            let dir = persistence.runDirectory(runId: run.runId)
            let path = (dir as NSString).appendingPathComponent("api-output.json")
            let data = try JSONEncoder().encode(run)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            print("[RunCoordinator] Warning: failed to persist record for run \(run.runId): \(error)")
        }
    }
}
