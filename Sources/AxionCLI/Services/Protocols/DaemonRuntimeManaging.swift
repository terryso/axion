import Foundation
import AxionCore
import OpenAgentSDK

struct DaemonSessionInfo: Sendable {
    let sessionId: String
    let task: String
    let startedAt: Date
}

protocol DaemonRuntimeManaging: Sendable {
    /// Execute a run through a per-request AxionRuntime with pre-registered API handlers.
    func executeRun(
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult

    /// Returns completed sessions tracked by this manager instance (not currently running).
    func listActiveSessions() async -> [DaemonSessionInfo]

    /// Clear session history. Does NOT cancel in-progress runs — those complete naturally.
    func shutdown() async
}
