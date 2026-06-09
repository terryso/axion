import Foundation
import OpenAgentSDK

/// Recovers persisted run state on server restart.
/// Handles all 8 Axion APIRunStatus values (including resuming, userTakeover).
enum AxionRunRecovery {

    static func recover(
        from coordinator: RunCoordinator,
        persistenceService: RunPersistenceService,
        eventBroadcaster: OpenAgentSDK.EventBroadcaster
    ) async {
        let persistedRuns = loadAllPersistedRuns(from: persistenceService)
        guard !persistedRuns.isEmpty else { return }

        print("[Recovery] Found \(persistedRuns.count) persisted run(s), recovering...")

        for var run in persistedRuns {
            let originalStatus = run.status

            switch run.status {
            case .running, .queued, .resuming, .userTakeover:
                run.status = .failed
                run.error = "server interrupted"
                run.completedAt = axionISO8601Formatter.string(from: Date())
                run.exitCode = 1
                persistRecordSafely(run, persistenceService: persistenceService)
                print("[Recovery] Run \(run.runId): \(originalStatus.rawValue) → failed")

            case .interventionNeeded:
                print("[Recovery] Run \(run.runId): intervention_needed — preserved")

            case .completed, .failed, .cancelled:
                print("[Recovery] Run \(run.runId): \(run.status.rawValue) — preserved")
            }

            await coordinator.restoreRun(run)

            let events = persistenceService.loadEvents(runId: run.runId)
            if !events.isEmpty {
                await eventBroadcaster.restoreReplayBuffer(runId: run.runId, events: events)
            }
        }

        print("[Recovery] Recovery complete.")
    }

    // MARK: - Private Helpers

    private static func loadAllPersistedRuns(from persistenceService: RunPersistenceService) -> [TrackedRun] {
        let baseDir = persistenceService.runsDirectory()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            atPath: baseDir
        ) else { return [] }

        return contents.compactMap { runId -> TrackedRun? in
            let dir = (baseDir as NSString).appendingPathComponent(runId)
            let path = (dir as NSString).appendingPathComponent("api-output.json")
            return loadDecodableFile(path, as: TrackedRun.self)
        }
    }

    private static func persistRecordSafely(_ run: TrackedRun, persistenceService: RunPersistenceService) {
        persistRunRecord(run, toDirectory: persistenceService.runDirectory(runId: run.runId))
    }
}
