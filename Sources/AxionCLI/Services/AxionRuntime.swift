import Foundation
import OpenAgentSDK

import AxionCore

public actor AxionRuntime {
    let eventBus: EventBus?
    private(set) var currentState: AxionRunState = .created
    private(set) var sessionId: String?
    private(set) var createdAt: Date?

    public init(eventBus: EventBus? = nil) {
        self.eventBus = eventBus
    }

    public nonisolated var state: AxionRunState {
        get async { await currentState }
    }

    func run(
        task: String,
        buildResult: AgentBuildResult,
        runConfig: RunOrchestrator.RunConfig
    ) async throws -> AxionRunResult {
        let sid = RunOrchestrator.generateRunId()
        let startedAt = Date()
        sessionId = sid
        createdAt = startedAt

        guard currentState.isValidTransition(to: .running) else {
            assertionFailure("Invalid state transition from \(currentState) to running")
            currentState = .failed
            return AxionRunResult(
                sessionId: sid, task: task, state: .failed,
                totalSteps: 0, durationMs: 0, runSucceeded: false,
                errorMessage: "Invalid state transition from \(currentState) to running",
                createdAt: startedAt
            )
        }
        currentState = .running

        let modifiedConfig = RunOrchestrator.RunConfig(
            task: runConfig.task,
            fast: runConfig.fast,
            dryrun: runConfig.dryrun,
            json: runConfig.json,
            noMemory: runConfig.noMemory,
            noVisualDelta: runConfig.noVisualDelta,
            allowForeground: runConfig.allowForeground,
            maxSteps: runConfig.maxSteps,
            config: runConfig.config,
            noReview: runConfig.noReview,
            onReviewCompleted: runConfig.onReviewCompleted,
            eventBus: eventBus
        )

        do {
            let result = try await RunOrchestrator.execute(
                buildResult: buildResult,
                runConfig: modifiedConfig
            )
            currentState = .completed
            return AxionRunResult(
                sessionId: sid,
                task: task,
                state: .completed,
                totalSteps: result.totalSteps,
                durationMs: result.durationMs,
                runSucceeded: result.runSucceeded,
                createdAt: startedAt
            )
        } catch {
            currentState = .failed
            return AxionRunResult(
                sessionId: sid,
                task: task,
                state: .failed,
                totalSteps: 0,
                durationMs: 0,
                runSucceeded: false,
                errorMessage: error.localizedDescription,
                createdAt: startedAt
            )
        }
    }
}
