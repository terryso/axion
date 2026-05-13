import Foundation

// MARK: - RunTracker

/// Actor-based async task status manager.
/// Tracks run lifecycle from submission through completion.
/// Thread-safe via actor isolation.
actor RunTracker {

    // MARK: - Properties

    private var runs: [String: TrackedRun] = [:]
    private static let maxTrackedRuns = 1000

    /// Event broadcaster for SSE streaming (Story 5.2).
    private let eventBroadcaster: EventBroadcaster?

    /// SSE extension point (Story 5.2) — callback invoked when run status changes.
    private var onRunStatusChanged: ((String, APIRunStatus) -> Void)?

    // MARK: - Initialization

    init(eventBroadcaster: EventBroadcaster? = nil) {
        self.eventBroadcaster = eventBroadcaster
    }

    // MARK: - Public API

    /// Generates a unique run ID in the format `YYYYMMDD-{6random}`.
    /// Matches the format used by `RunCommand.generateRunId()`.
    func generateRunId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let datePart = formatter.string(from: Date())
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomPart = String((0..<6).map { _ in chars.randomElement()! })
        return "\(datePart)-\(randomPart)"
    }

    /// Submit a new run and return the generated runId.
    /// - Parameters:
    ///   - task: The task description to execute.
    ///   - options: Run options from the API request.
    /// - Returns: A unique runId string.
    func submitRun(task: String, options: RunOptions) -> String {
        let runId = generateRunId()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let submittedAt = formatter.string(from: Date())

        let run = TrackedRun(
            runId: runId,
            task: task,
            status: .running,
            submittedAt: submittedAt,
            completedAt: nil,
            totalSteps: 0,
            durationMs: nil,
            replanCount: 0,
            steps: []
        )
        runs[runId] = run

        // Evict oldest completed runs if at capacity
        if runs.count > Self.maxTrackedRuns {
            let completedKeys = runs.filter { $0.value.status != .running }
                .sorted { ($0.value.submittedAt) < ($1.value.submittedAt) }
                .map(\.key)
            let evictCount = min(completedKeys.count, runs.count - Self.maxTrackedRuns)
            for key in completedKeys.prefix(evictCount) {
                runs.removeValue(forKey: key)
            }
        }

        return runId
    }

    /// Update an existing run's status and results.
    /// - Parameters:
    ///   - runId: The run to update.
    ///   - status: New status (done, failed, cancelled).
    ///   - steps: Array of step summaries from execution.
    ///   - durationMs: Total execution duration in milliseconds.
    ///   - replanCount: Number of replanning attempts.
    func updateRun(
        runId: String,
        status: APIRunStatus,
        steps: [StepSummary],
        durationMs: Int?,
        replanCount: Int
    ) async {
        guard runs[runId] != nil else {
            print("[RunTracker] Warning: updateRun called with unknown runId '\(runId)'")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let completedAt = formatter.string(from: Date())

        runs[runId]?.status = status
        runs[runId]?.completedAt = completedAt
        runs[runId]?.totalSteps = steps.count
        runs[runId]?.durationMs = durationMs
        runs[runId]?.replanCount = replanCount
        runs[runId]?.steps = steps

        // Emit run_completed event via EventBroadcaster (Story 5.2)
        if let broadcaster = eventBroadcaster {
            let runCompletedEvent = SSEEvent.runCompleted(RunCompletedData(
                runId: runId,
                finalStatus: status.rawValue,
                totalSteps: steps.count,
                durationMs: durationMs,
                replanCount: replanCount
            ))
            await broadcaster.emit(runId: runId, event: runCompletedEvent)
            await broadcaster.complete(runId: runId)
        }

        // Legacy callback: notify status change
        onRunStatusChanged?(runId, status)
    }

    /// Retrieve a run by its ID.
    /// - Parameter runId: The run ID to look up.
    /// - Returns: The TrackedRun, or nil if not found.
    func getRun(runId: String) -> TrackedRun? {
        runs[runId]
    }

    /// List all tracked runs.
    /// - Returns: Array of all TrackedRun instances.
    func listRuns() -> [TrackedRun] {
        Array(runs.values)
    }

    // MARK: - SSE Extension Point (Story 5.2)

    /// Set a callback to be invoked when any run's status changes.
    /// This is reserved for SSE event streaming in Story 5.2.
    func setOnStatusChanged(_ handler: @escaping (String, APIRunStatus) -> Void) {
        onRunStatusChanged = handler
    }
}
