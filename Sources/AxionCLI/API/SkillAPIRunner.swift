import AxionCore
import Foundation
import os
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
            let event = AgentSSEEvent.runCompleted(RunCompletedData(
                runId: runId,
                finalStatus: "failed",
                totalSteps: 0,
                durationMs: nil
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
                let completedEvent = AgentSSEEvent.stepCompleted(StepCompletedData(
                    stepIndex: index,
                    tool: step.tool,
                    success: false,
                    durationMs: nil
                ))
                await eventBroadcaster.emit(runId: runId, event: completedEvent)

                // Run completed (failed)
                let elapsed = ContinuousClock.now - startTime
                let durationMs = Int(
                    elapsed.components.seconds * 1000 +
                    elapsed.components.attoseconds / 1_000_000_000_000_000
                )
                let runCompletedEvent = AgentSSEEvent.runCompleted(RunCompletedData(
                    runId: runId,
                    finalStatus: "failed",
                    totalSteps: skill.steps.count,
                    durationMs: durationMs
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
            let completedEvent = AgentSSEEvent.stepCompleted(StepCompletedData(
                stepIndex: index,
                tool: step.tool,
                success: true,
                durationMs: nil
            ))
            await eventBroadcaster.emit(runId: runId, event: completedEvent)

            // Wait if specified
            if step.waitAfterSeconds > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(step.waitAfterSeconds * 1_000_000_000))
            }
        }

        await helperManager.stop()

        let elapsed = ContinuousClock.now - startTime
        let durationMs = Int(
            elapsed.components.seconds * 1000 +
            elapsed.components.attoseconds / 1_000_000_000_000_000
        )

        let runCompletedEvent = AgentSSEEvent.runCompleted(RunCompletedData(
            runId: runId,
            finalStatus: "completed",
            totalSteps: skill.steps.count,
            durationMs: durationMs
        ))
        await eventBroadcaster.emit(runId: runId, event: runCompletedEvent)
        await eventBroadcaster.complete(runId: runId)

        // Track skill usage
        let skillsDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
        let usageStore = SkillUsageStore(skillsDir: skillsDir)
        do {
            try await usageStore.bumpView(skillName: skill.name)
        } catch {
            let logger = Logger(subsystem: "com.axion.cli", category: "SkillUsage")
            logger.warning("Skill usage tracking failed for '\(skill.name)': \(error.localizedDescription)")
        }

        return RunResult(
            finalStatus: .completed,
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
