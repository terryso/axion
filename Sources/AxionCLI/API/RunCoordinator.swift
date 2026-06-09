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

    func submitRun(task: String, request: OpenAgentSDK.CreateRunRequest = OpenAgentSDK.CreateRunRequest(task: "")) -> String {
        let runId = RunOrchestrator.generateRunId()
        _submitRun(runId: runId, task: task, request: request)
        return runId
    }

    /// Submit a run with a pre-assigned runId (e.g. from SDK's RunTracker).
    func submitRunWithId(_ runId: String, task: String, request: OpenAgentSDK.CreateRunRequest = OpenAgentSDK.CreateRunRequest(task: "")) {
        _submitRun(runId: runId, task: task, request: request)
    }

    private func _submitRun(runId: String, task: String, request: OpenAgentSDK.CreateRunRequest) {
        let submittedAt = axionISO8601Formatter.string(from: Date())

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
        totalSteps: Int? = nil,
        durationMs: Int?,
        replanCount: Int,
        costTelemetry: CostTelemetry? = nil,
        error: String? = nil
    ) async {
        guard runs[runId] != nil else { return }

        let completedAt = axionISO8601Formatter.string(from: Date())
        let resolvedTotalSteps = totalSteps ?? steps.count

        runs[runId]?.status = status
        runs[runId]?.completedAt = completedAt
        runs[runId]?.totalSteps = resolvedTotalSteps
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
                totalSteps: resolvedTotalSteps,
                durationMs: durationMs
            ))
            await broadcaster.emit(runId: runId, event: event)
            await broadcaster.complete(runId: runId)
        }

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
        persistRunRecord(run, toDirectory: persistence.runDirectory(runId: run.runId))
    }
}
