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
    /// - Parameter sessionId: When provided, used as the run's sessionId instead of auto-generating one.
    func executeRun(
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides,
        sessionId: String?
    ) async throws -> AxionRunResult

    /// Execute a run with additional event handlers (e.g. TGEventHandler).
    /// - Parameter sessionId: When provided, used as the run's sessionId instead of auto-generating one.
    func executeRun(
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides,
        extraHandlers: [any EventHandler],
        sessionId: String?
    ) async throws -> AxionRunResult

    /// Resume an existing session with additional event handlers.
    func resumeRun(
        sessionId: String,
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides,
        extraHandlers: [any EventHandler]
    ) async throws -> AxionRunResult

    /// Execute a skill through a per-request AxionRuntime with pre-registered API handlers.
    func executeSkill(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult

    /// Returns completed sessions tracked by this manager instance (not currently running).
    func listActiveSessions() async -> [DaemonSessionInfo]

    /// Clear session history. Does NOT cancel in-progress runs — those complete naturally.
    func shutdown() async
}

extension DaemonRuntimeManaging {
    func executeRun(
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult {
        try await executeRun(
            task: task, buildConfig: buildConfig, eventBus: eventBus,
            runOverrides: runOverrides, sessionId: nil
        )
    }
}
