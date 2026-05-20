import Foundation
import OpenAgentSDK

/// Actor-based run tracker that manages Axion's rich TrackedRun lifecycle,
/// coordinates with SDK's EventBroadcaster for SSE, and persists via AxionRunPersistence.
actor AxionRunTracker {

    private var runs: [String: TrackedRun] = [:]
    private static let maxTrackedRuns = 1000

    private let eventBroadcaster: OpenAgentSDK.EventBroadcaster?
    private let persistenceService: AxionRunPersistence?

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

    init(
        eventBroadcaster: OpenAgentSDK.EventBroadcaster? = nil,
        persistenceService: AxionRunPersistence? = nil
    ) {
        self.eventBroadcaster = eventBroadcaster
        self.persistenceService = persistenceService
    }

    // MARK: - Run Lifecycle

    func generateRunId() -> String {
        let datePart = Self.runIdDateFormatter.string(from: Date())
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomPart = String((0..<6).map { _ in chars.randomElement()! })
        return "\(datePart)-\(randomPart)"
    }

    func submitRun(task: String, options: RunOptions) -> String {
        let runId = generateRunId()
        let submittedAt = Self.isoFormatter.string(from: Date())

        let run = TrackedRun(
            runId: runId,
            task: task,
            status: .running,
            submittedAt: submittedAt,
            live: true,
            allowForeground: options.allowForeground ?? false
        )
        runs[runId] = run
        persistenceService?.persistRecordSafely(run)

        evictOldRuns()
        return runId
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
        guard runs[runId] != nil else {
            print("[AxionRunTracker] Warning: updateRun called with unknown runId '\(runId)'")
            return
        }

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
            persistenceService?.persistRecordSafely(run)
        }
    }

    func updateRunResult(runId: String, result: ApiTaskResult) {
        guard runs[runId] != nil else {
            print("[AxionRunTracker] Warning: updateRunResult called with unknown runId '\(runId)'")
            return
        }
        runs[runId]?.result = result
        if let run = runs[runId] {
            persistenceService?.persistRecordSafely(run)
        }
    }

    func updateRunIntervention(runId: String, intervention: InterventionData) {
        guard runs[runId] != nil else {
            print("[AxionRunTracker] Warning: updateRunIntervention called with unknown runId '\(runId)'")
            return
        }
        runs[runId]?.intervention = intervention
        if let run = runs[runId] {
            persistenceService?.persistRecordSafely(run)
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
}
