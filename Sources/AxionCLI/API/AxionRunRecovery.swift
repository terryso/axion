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
                run.completedAt = isoFormatter.string(from: Date())
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
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path))
            else { return nil }
            return try? JSONDecoder().decode(TrackedRun.self, from: data)
        }
    }

    private static func persistRecordSafely(_ run: TrackedRun, persistenceService: RunPersistenceService) {
        do {
            let dir = persistenceService.runDirectory(runId: run.runId)
            let path = (dir as NSString).appendingPathComponent("api-output.json")
            let data = try JSONEncoder().encode(run)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            print("[Recovery] Warning: failed to persist record for run \(run.runId): \(error)")
        }
    }
}
