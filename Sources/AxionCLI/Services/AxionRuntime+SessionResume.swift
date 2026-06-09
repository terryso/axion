import Foundation
import OpenAgentSDK

import AxionCore

extension AxionRuntime {
    // MARK: - Session Resume

    func resumeSession(
        _ sessionId: String,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: RunOverrides = .default
    ) async throws -> AxionRunResult {
        // 1. Validate session exists
        guard let _ = try await sessionStore.load(sessionId: sessionId) else {
            throw AxionError.sessionNotFound(id: sessionId)
        }

        // 2. Validate session is not already running
        if let overlay = loadOverlay(sessionId: sessionId), overlay.status == "running" {
            throw AxionError.sessionAlreadyRunning(id: sessionId)
        }

        // 3. Reset state for this session (run() will set sessionId/createdAt)
        currentState = .created

        // 4. Inject sessionId + sessionStore into BuildConfig for SDK restore
        let resumeBuildConfig = injectSessionIntoBuildConfig(buildConfig, sessionId: sessionId)

        // 5. Build agent
        let buildResult: AgentBuildResult
        do {
            let buildStart = ContinuousClock.now
            buildResult = try await builder.build(resumeBuildConfig, eventBus: eventBus)
            let buildElapsed = ContinuousClock.now - buildStart
            let buildMs = durationToMs(buildElapsed)
            fputs("[axion] 构建完成 [\(formatDurationMs(buildMs))]\n", stderr)
        } catch {
            currentState = .failed
            return .failedRun(
                sessionId: sessionId,
                task: buildConfig.task,
                error: error.localizedDescription,
                createdAt: Date()
            )
        }

        // 6. Execute via existing run() with resumeSessionId
        let runConfig = makeRunConfig(from: buildConfig, overrides: runOverrides)

        return try await run(
            task: buildConfig.task,
            buildResult: buildResult,
            runConfig: runConfig,
            resumeSessionId: sessionId
        )
    }
}
