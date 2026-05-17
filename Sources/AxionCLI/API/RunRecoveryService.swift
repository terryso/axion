import Foundation

// MARK: - RunRecoveryService

/// Recovers persisted run state on server restart.
/// Marks interrupted runs as failed and restores intervention_needed runs.
enum RunRecoveryService {

    /// Recover all persisted runs from disk into the tracker.
    /// - Parameters:
    ///   - tracker: The active RunTracker to inject recovered runs into.
    ///   - persistenceService: The persistence service to load records from.
    ///   - eventBroadcaster: The broadcaster to restore replay buffers into.
    static func recover(
        from tracker: RunTracker,
        persistenceService: RunPersistenceService,
        eventBroadcaster: EventBroadcaster
    ) async {
        let persistedRuns = persistenceService.loadAllPersistedRuns()
        guard !persistedRuns.isEmpty else { return }

        print("[Recovery] Found \(persistedRuns.count) persisted run(s), recovering...")

        for var run in persistedRuns {
            let originalStatus = run.status

            switch run.status {
            // AC4: Active states → mark as failed
            case .running, .queued, .resuming, .userTakeover:
                run.status = .failed
                run.error = "server interrupted"
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                run.completedAt = formatter.string(from: Date())
                run.exitCode = 1
                persistenceService.persistRecordSafely(run)
                print("[Recovery] Run \(run.runId): \(originalStatus.rawValue) → failed")

            // AC5: intervention_needed → keep unchanged
            case .interventionNeeded:
                print("[Recovery] Run \(run.runId): intervention_needed — preserved")

            // AC4: Terminal states → keep unchanged
            case .completed, .failed, .cancelled:
                print("[Recovery] Run \(run.runId): \(run.status.rawValue) — preserved")
            }

            await tracker.restoreRun(run)

            // AC6: Restore SSE history events to replay buffer
            let events = persistenceService.loadEvents(runId: run.runId)
            if !events.isEmpty {
                await eventBroadcaster.restoreReplayBuffer(runId: run.runId, events: events)
            }
        }

        print("[Recovery] Recovery complete.")
    }
}
