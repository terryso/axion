import Foundation
import OpenAgentSDK

/// Recovers persisted run state on server restart.
/// Handles all 8 Axion APIRunStatus values (including resuming, userTakeover).
enum AxionRunRecovery {

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func recover(
        from tracker: AxionRunTracker,
        persistenceService: AxionRunPersistence,
        eventBroadcaster: OpenAgentSDK.EventBroadcaster
    ) async {
        let persistedRuns = persistenceService.loadAllPersistedRuns()
        guard !persistedRuns.isEmpty else { return }

        print("[Recovery] Found \(persistedRuns.count) persisted run(s), recovering...")

        for var run in persistedRuns {
            let originalStatus = run.status

            switch run.status {
            case .running, .queued, .resuming, .userTakeover:
                run.status = .failed
                run.error = "server interrupted"
                run.completedAt = isoFormatter.string(from: Date())
                run.exitCode = 1
                persistenceService.persistRecordSafely(run)
                print("[Recovery] Run \(run.runId): \(originalStatus.rawValue) → failed")

            case .interventionNeeded:
                print("[Recovery] Run \(run.runId): intervention_needed — preserved")

            case .completed, .failed, .cancelled:
                print("[Recovery] Run \(run.runId): \(run.status.rawValue) — preserved")
            }

            await tracker.restoreRun(run)

            let events = persistenceService.loadEvents(runId: run.runId)
            if !events.isEmpty {
                await eventBroadcaster.restoreReplayBuffer(runId: run.runId, events: events)
            }
        }

        print("[Recovery] Recovery complete.")
    }
}
