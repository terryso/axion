import AxionCore
import OpenAgentSDK

/// Runs a skill through the RunTracker + EventBroadcaster pipeline.
/// Used by the POST /v1/skills/{name}/run endpoint so external clients can
/// reuse SSE monitoring and TaskDetailPanel.
enum SkillAPIRunner {

    struct RunResult {
        let finalStatus: APIRunStatus
        let stepSummaries: [StepSummary]
        let durationMs: Int?
        let replanCount: Int
    }

    static func runSkill(
        config: AxionConfig,
        skill: AxionCore.Skill,
        paramValues: [String: String],
        runId: String,
        eventBroadcaster: OpenAgentSDK.EventBroadcaster
    ) async -> RunResult {
        let startTime = ContinuousClock.now

        // Start Helper process
        let helperManager = HelperProcessManager()
        do {
            try await helperManager.start()
        } catch {
            await emitRunCompleted(runId: runId, status: "failed", totalSteps: 0, durationMs: nil, broadcaster: eventBroadcaster)
            return RunResult(finalStatus: .failed, stepSummaries: [], durationMs: nil, replanCount: 0)
        }

        let client = HelperMCPClientAdapter(manager: helperManager)
        let executor = SkillExecutor(client: client)

        var stepSummaries: [StepSummary] = []

        // Execute each step manually to emit SSE events
        for (index, step) in skill.steps.enumerated() {
            if _Concurrency.Task.isCancelled { break }

            // Emit step_started
            let startedEvent = AgentSSEEvent.stepStarted(StepStartedData(
                stepIndex: index,
                tool: step.tool
            ))
            await eventBroadcaster.emit(runId: runId, event: startedEvent)

            let stepSuccess = await executeStep(
                step: step,
                executor: executor,
                client: client,
                paramValues: paramValues,
                skillParameters: skill.parameters
            )

            stepSummaries.append(StepSummary(
                index: index,
                tool: step.tool,
                purpose: step.tool,
                success: stepSuccess
            ))

            if !stepSuccess {
                // Emit step_completed (failed) and stop
                await emitStepCompleted(index: index, tool: step.tool, success: false, runId: runId, broadcaster: eventBroadcaster)

                // Run completed (failed)
                let durationMs = durationToMs(ContinuousClock.now - startTime)
                await emitRunCompleted(runId: runId, status: "failed", totalSteps: skill.steps.count, durationMs: durationMs, broadcaster: eventBroadcaster)
                await helperManager.stop()

                return RunResult(
                    finalStatus: .failed,
                    stepSummaries: stepSummaries,
                    durationMs: durationMs,
                    replanCount: 0
                )
            }

            // Emit step_completed (success)
            await emitStepCompleted(index: index, tool: step.tool, success: true, runId: runId, broadcaster: eventBroadcaster)

            // Wait if specified
            if step.waitAfterSeconds > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(step.waitAfterSeconds * 1_000_000_000))
            }
        }

        await helperManager.stop()

        let durationMs = durationToMs(ContinuousClock.now - startTime)
        await emitRunCompleted(runId: runId, status: "completed", totalSteps: skill.steps.count, durationMs: durationMs, broadcaster: eventBroadcaster)

        // Track skill usage
        await trackSkillUsage(skillName: skill.name)

        return RunResult(
            finalStatus: .completed,
            stepSummaries: stepSummaries,
            durationMs: durationMs,
            replanCount: 0
        )
    }

    // MARK: - Step Execution

    /// Attempts to resolve params and call a tool. Returns true on success.
    private static func tryCallTool(
        step: SkillStep,
        executor: SkillExecutor,
        client: HelperMCPClientAdapter,
        paramValues: [String: String],
        skillParameters: [SkillParameter]
    ) async throws {
        let resolvedArgs = try executor.resolveParams(
            step.arguments,
            paramValues: paramValues,
            parameters: skillParameters
        )
        let mcpArgs = executor.toStringValueDict(resolvedArgs)
        _ = try await client.callTool(name: step.tool, arguments: mcpArgs)
    }

    /// Executes a single step with one retry on failure.
    private static func executeStep(
        step: SkillStep,
        executor: SkillExecutor,
        client: HelperMCPClientAdapter,
        paramValues: [String: String],
        skillParameters: [SkillParameter]
    ) async -> Bool {
        do {
            try await tryCallTool(step: step, executor: executor, client: client, paramValues: paramValues, skillParameters: skillParameters)
            return true
        } catch {
            // Retry once
            do {
                try await tryCallTool(step: step, executor: executor, client: client, paramValues: paramValues, skillParameters: skillParameters)
                return true
            } catch {
                return false
            }
        }
    }

    // MARK: - SSE Emission Helpers

    /// Emits a step_completed SSE event for the given step index.
    private static func emitStepCompleted(
        index: Int,
        tool: String,
        success: Bool,
        runId: String,
        broadcaster: OpenAgentSDK.EventBroadcaster
    ) async {
        let event = AgentSSEEvent.stepCompleted(StepCompletedData(
            stepIndex: index,
            tool: tool,
            success: success,
            durationMs: nil
        ))
        await broadcaster.emit(runId: runId, event: event)
    }

    /// Emits a runCompleted SSE event and signals completion.
    private static func emitRunCompleted(
        runId: String,
        status: String,
        totalSteps: Int,
        durationMs: Int?,
        broadcaster: OpenAgentSDK.EventBroadcaster
    ) async {
        let event = AgentSSEEvent.runCompleted(RunCompletedData(
            runId: runId,
            finalStatus: status,
            totalSteps: totalSteps,
            durationMs: durationMs
        ))
        await broadcaster.emit(runId: runId, event: event)
        await broadcaster.complete(runId: runId)
    }
}
