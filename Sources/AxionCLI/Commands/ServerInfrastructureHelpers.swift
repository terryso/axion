import Foundation
import OpenAgentSDK

import AxionCore

// MARK: - Shared Server Infrastructure

/// Holds the shared server components initialized identically by both
/// `ServerCommand` and `GatewayStartCommand`.
struct ServerInfrastructure: Sendable {
    let runCoordinator: RunCoordinator
    let eventBroadcaster: EventBroadcaster
    let skillRegistry: SkillRegistry
}

/// Creates the shared server infrastructure: SDK persistence, event broadcaster,
/// run coordinator, skill registry (with built-in + discovered skills), and
/// recovers any persisted runs.
func createServerInfrastructure() async -> ServerInfrastructure {
    let sdkPersistence = RunPersistenceService(baseDirectory: nil)
    let eventBroadcaster = OpenAgentSDK.EventBroadcaster(persistenceService: sdkPersistence)
    let runCoordinator = RunCoordinator(
        eventBroadcaster: eventBroadcaster,
        persistenceService: sdkPersistence
    )

    let skillRegistry = SkillRegistry()
    AxionBuiltInSkills.registerAll(into: skillRegistry)
    skillRegistry.registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)

    await AxionRunRecovery.recover(
        from: runCoordinator,
        persistenceService: sdkPersistence,
        eventBroadcaster: eventBroadcaster
    )

    return ServerInfrastructure(
        runCoordinator: runCoordinator,
        eventBroadcaster: eventBroadcaster,
        skillRegistry: skillRegistry
    )
}

// MARK: - Server Banner

/// Prints the standard startup banner for server-mode processes.
func printServerBanner(name: String, host: String, port: Int, authEnabled: Bool, extraLines: [String] = []) {
    print("\(name) running on port \(port)")
    print("  Listening on \(host):\(port)")
    print("  Auth: \(authEnabled ? "enabled" : "disabled")")
    for line in extraLines {
        print("  \(line)")
    }
    print("  Press Ctrl+C to stop")
    fflush(stdout)
}

// MARK: - RunHandler Helpers

/// Resolves the SDK-created runId by matching task text + queued status.
///
/// SDK boundary limitation: the runHandler callback does not expose the runId
/// it created, so we find it by matching task text + .queued status. This is
/// ambiguous when identical tasks are queued concurrently — a fix requires an
/// SDK API change to pass runId into the callback.
func resolveSDKRunId(from tracker: RunTracker, task: String) async -> String? {
    let runs = await tracker.listRuns()
    return runs.first(where: { $0.task == task && $0.status == .queued })?.runId
}

/// Handles the error path for a failed run: stops the bridge, updates coordinator
/// and tracker to failed status, completes the broadcast stream, and releases the limiter.
func handleRunFailure(
    bridge: EventBusBridge,
    runCoordinator: RunCoordinator,
    tracker: RunTracker,
    broadcaster: EventBroadcaster,
    limiter: ConcurrencyLimiter,
    runId: String
) async {
    await bridge.stop()
    await runCoordinator.updateRun(runId: runId, status: .failed, steps: [], durationMs: 0, replanCount: 0, costTelemetry: nil)
    await tracker.updateRun(runId: runId, status: .failed)
    await broadcaster.complete(runId: runId)
    await limiter.release()
}

/// Handles the success path for a completed run: maps result state to API status,
/// updates both the Axion RunCoordinator and SDK tracker, and releases the limiter.
func handleRunSuccess(
    result: AxionRunResult,
    runCoordinator: RunCoordinator,
    tracker: RunTracker,
    limiter: ConcurrencyLimiter,
    runId: String
) async {
    let apiStatus: APIRunStatus = result.state == .completed ? .completed : .failed
    await runCoordinator.updateRun(
        runId: runId,
        status: apiStatus,
        steps: [],
        totalSteps: result.totalSteps,
        durationMs: result.durationMs,
        replanCount: 0,
        costTelemetry: nil
    )

    let sdkStatus = OpenAgentSDK.APIRunStatus(rawValue: apiStatus.rawValue) ?? .failed
    await tracker.updateRun(
        runId: runId,
        status: sdkStatus,
        totalSteps: result.totalSteps,
        durationMs: result.durationMs
    )

    await limiter.release()
}
