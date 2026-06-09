import Foundation
import OpenAgentSDK

import AxionCore

extension AxionRuntime {
    // MARK: - Skill Execution

    func executeSkill(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: RunOverrides = .default
    ) async throws -> AxionRunResult {
        let sid = executor.generateRunId()
        let startedAt = Date()

        if let failure = beginRun(sid: sid, task: task, startedAt: startedAt) {
            return failure
        }

        do {
            let (agent, skillRunCompleteBox) = try await builder.buildSkillAgent(
                config: config,
                skill: skill,
                maxSteps: buildConfig.maxSteps,
                verbose: buildConfig.verbose,
                eventBus: eventBus
            )
            runCompleteBox = skillRunCompleteBox

            let args = RunOrchestrator.parseSkillName(from: task).flatMap { skillName in
                let prefix = "/\(skillName) "
                return task.hasPrefix(prefix) ? String(task.dropFirst(prefix.count)) : nil
            }

            let startTime = ContinuousClock.now
            var totalSteps = 0

            let runMode = runOverrides.json ? "json" : (buildConfig.fast ? "fast" : "standard")
            let outputHandler: any SDKMessageOutputHandler = runOverrides.json
                ? SDKJSONOutputHandler(mode: runMode)
                : SDKTerminalOutputHandler(mode: runMode)
            outputHandler.displayRunStart(runId: sid, task: task)
            fputs("[axion] 执行: Skill (via AxionRuntime)\n", stderr)

            let skillStream = agent.executeSkillStream(skill.name, args: args)
            var streamedMessages: [SDKMessage] = []
            for await message in skillStream {
                if _Concurrency.Task.isCancelled { break }
                if case .toolUse = message { totalSteps += 1 }
                streamedMessages.append(message)
                outputHandler.handle(message)
            }

            let durationMs = durationToMs(ContinuousClock.now - startTime)

            try? await agent.close()
            currentState = .completed
            try? writeAxionState(
                sessionId: sid, status: AxionRunState.completed.rawValue,
                totalSteps: totalSteps, durationMs: durationMs
            )

            // Track skill usage
            await trackSkillUsage(skillName: skill.name)

            fputs("[axion] 运行结束。步数: \(totalSteps), 耗时: \(String(format: "%.1f", Double(durationMs) / 1000))s\n", stderr)

            let ctxWrapper = skillRunCompleteBox.context.map { ctx in
                RunCompleteContextWrapper(
                    task: ctx.task,
                    status: ctx.status.rawValue,
                    totalCostUsd: ctx.totalCostUsd,
                    durationMs: ctx.durationMs,
                    numTurns: ctx.numTurns,
                    inputTokens: ctx.usage.inputTokens,
                    outputTokens: ctx.usage.outputTokens
                )
            }

            return AxionRunResult(
                sessionId: sid, task: task, state: .completed,
                totalSteps: totalSteps, durationMs: durationMs,
                runSucceeded: true, runCompleteContext: ctxWrapper,
                responseText: Self.collectSkillResponseText(from: streamedMessages), createdAt: startedAt
            )
        } catch {
            return failRun(sid: sid, task: task, error: error.localizedDescription, startedAt: startedAt)
        }
    }
}
