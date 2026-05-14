import AxionCore
import Foundation

/// Runs a skill through the RunTracker + EventBroadcaster pipeline.
/// Used by the POST /v1/skills/{name}/run endpoint so AxionBar can
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
        skill: Skill,
        paramValues: [String: String],
        runId: String,
        eventBroadcaster: EventBroadcaster
    ) async -> RunResult {
        let startTime = ContinuousClock.now

        // Start Helper process
        let helperManager = HelperProcessManager()
        do {
            try await helperManager.start()
        } catch {
            let event = SSEEvent.runCompleted(RunCompletedData(
                runId: runId,
                finalStatus: "failed",
                totalSteps: 0,
                durationMs: nil,
                replanCount: 0
            ))
            await eventBroadcaster.emit(runId: runId, event: event)
            await eventBroadcaster.complete(runId: runId)
            return RunResult(finalStatus: .failed, stepSummaries: [], durationMs: nil, replanCount: 0)
        }

        let client = HelperMCPClientAdapter(manager: helperManager)
        let executor = SkillExecutor(client: client)

        var stepSummaries: [StepSummary] = []

        // Execute each step manually to emit SSE events
        for (index, step) in skill.steps.enumerated() {
            if Task.isCancelled { break }

            // Emit step_started
            let startedEvent = SSEEvent.stepStarted(StepStartedData(
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
                let completedEvent = SSEEvent.stepCompleted(StepCompletedData(
                    stepIndex: index,
                    tool: step.tool,
                    purpose: step.tool,
                    success: false,
                    durationMs: nil
                ))
                await eventBroadcaster.emit(runId: runId, event: completedEvent)

                // Run completed (failed)
                let elapsed = ContinuousClock.now - startTime
                let durationMs = Int(
                    elapsed.components.seconds * 1000 +
                    elapsed.components.attoseconds / 1_000_000_000_000
                )
                let runCompletedEvent = SSEEvent.runCompleted(RunCompletedData(
                    runId: runId,
                    finalStatus: "failed",
                    totalSteps: skill.steps.count,
                    durationMs: durationMs,
                    replanCount: 0
                ))
                await eventBroadcaster.emit(runId: runId, event: runCompletedEvent)
                await eventBroadcaster.complete(runId: runId)
                await helperManager.stop()

                return RunResult(
                    finalStatus: .failed,
                    stepSummaries: stepSummaries,
                    durationMs: durationMs,
                    replanCount: 0
                )
            }

            // Emit step_completed (success)
            let completedEvent = SSEEvent.stepCompleted(StepCompletedData(
                stepIndex: index,
                tool: step.tool,
                purpose: step.tool,
                success: true,
                durationMs: nil
            ))
            await eventBroadcaster.emit(runId: runId, event: completedEvent)

            // Wait if specified
            if step.waitAfterSeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(step.waitAfterSeconds * 1_000_000_000))
            }
        }

        await helperManager.stop()

        let elapsed = ContinuousClock.now - startTime
        let durationMs = Int(
            elapsed.components.seconds * 1000 +
            elapsed.components.attoseconds / 1_000_000_000_000
        )

        let runCompletedEvent = SSEEvent.runCompleted(RunCompletedData(
            runId: runId,
            finalStatus: "done",
            totalSteps: skill.steps.count,
            durationMs: durationMs,
            replanCount: 0
        ))
        await eventBroadcaster.emit(runId: runId, event: runCompletedEvent)
        await eventBroadcaster.complete(runId: runId)

        return RunResult(
            finalStatus: .done,
            stepSummaries: stepSummaries,
            durationMs: durationMs,
            replanCount: 0
        )
    }

    private static func executeStep(
        step: SkillStep,
        executor: SkillExecutor,
        client: HelperMCPClientAdapter,
        paramValues: [String: String],
        skillParameters: [SkillParameter]
    ) async -> Bool {
        do {
            let resolvedArgs = try executor.resolveParams(
                step.arguments,
                paramValues: paramValues,
                parameters: skillParameters
            )
            let mcpArgs = executor.toStringValueDict(resolvedArgs)
            _ = try await client.callTool(name: step.tool, arguments: mcpArgs)
            return true
        } catch {
            // Retry once
            do {
                let resolvedArgs = try executor.resolveParams(
                    step.arguments,
                    paramValues: paramValues,
                    parameters: skillParameters
                )
                let mcpArgs = executor.toStringValueDict(resolvedArgs)
                _ = try await client.callTool(name: step.tool, arguments: mcpArgs)
                return true
            } catch {
                return false
            }
        }
    }
}
