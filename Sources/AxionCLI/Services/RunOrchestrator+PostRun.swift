import Foundation
import os
import OpenAgentSDK

import AxionCore

// MARK: - Post-Run Processing

extension RunOrchestrator {

    /// Executes post-run review if conditions are met (non-dryrun, memory enabled, review enabled).
    ///
    /// Called from `execute()` after the stream loop completes and memory processing finishes,
    /// but before the run lock is released.
    static func executePostRunReview(
        buildResult: AgentBuildResult,
        runConfig: RunConfig,
        runId: String,
        collectedMessages: [SDKMessage],
        agent: Agent
    ) async {
        guard let orchestrator = buildResult.reviewOrchestrator,
              !runConfig.dryrun,
              !runConfig.noMemory,
              !runConfig.noReview else { return }

        var reviewConfig = ReviewAgentConfig()
        reviewConfig.allowedTools.append("review_save_universal_memory")
        let (doMemory, doSkill) = orchestrator.shouldReview(
            sessionId: runId,
            messageCount: collectedMessages.count,
            config: reviewConfig
        )
        guard doMemory || doSkill else { return }

        var tunedConfig = ReviewAgentConfig(
            reviewMemory: doMemory,
            reviewSkills: doSkill
        )
        tunedConfig.allowedTools.append("review_save_universal_memory")
        let reviewStart = ContinuousClock.now
        let result = await orchestrator.executeReview(
            parentAgent: agent,
            messages: collectedMessages,
            config: tunedConfig
        )
        let reviewMs = durationToMs(ContinuousClock.now - reviewStart)

        if let result {
            axionReviewOrchestratorLogger.info("Review completed: \(result.summary)")

            // Track skill management usage
            if let usageStore = buildResult.usageStore {
                for skillName in result.skillChanges {
                    do {
                        try await usageStore.bumpManage(skillName: skillName)
                    } catch {
                        axionSkillUsageLogger.warning("Skill manage tracking failed for '\(skillName)': \(error.localizedDescription)")
                    }
                }
            }

            TraceRecorder.recordReviewCompleted(
                runId: runId,
                reviewSummary: result.summary,
                memoryChanges: result.memoryChanges,
                skillChanges: result.skillChanges,
                traceDir: ConfigManager.traceDirectory
            )

            // Terminal output for review result
            if let output = Self.formatReviewSummary(memoryChanges: result.memoryChanges, skillChanges: result.skillChanges, durationMs: reviewMs) {
                fputs("\(output)\n", stderr)
            }

            runConfig.onReviewCompleted?(result.summary)
        } else {
            axionReviewOrchestratorLogger.warning("Review agent returned nil for run \(runId)")
            TraceRecorder.recordReviewFailed(
                runId: runId,
                error: "review agent returned nil",
                traceDir: ConfigManager.traceDirectory
            )
        }
    }

    /// Executes post-run intelligent curator if conditions are met.
    ///
    /// Called from `execute()` after review completes, before lock release.
    static func executePostRunCurator(
        buildResult: AgentBuildResult,
        runConfig: RunConfig,
        runId: String,
        agent: Agent
    ) async {
        guard let curator = buildResult.intelligentCurator,
              !runConfig.dryrun,
              !runConfig.noMemory,
              !runConfig.noReview else { return }

        let curatorDryRun = curator.skillCurator.config.dryRun
        let curatorState = await curator.curatorStore.loadState()
        guard curator.skillCurator.shouldRun(state: curatorState) else { return }

        do {
            let curatorStart = ContinuousClock.now
            let result = try await curator.execute(parentAgent: agent, dryRun: curatorDryRun)
            let report = CuratorRunReport(from: result)
            axionIntelligentCuratorLogger.info("Curator completed in \(result.durationMs)ms")
            axionIntelligentCuratorLogger.debug("Curator report:\n\(report.renderMarkdown())")
            TraceRecorder.recordCuratorCompleted(
                runId: runId,
                consolidations: result.consolidations.count,
                prunings: result.prunings.count,
                transitionsApplied: result.mechanicalResult.transitionsApplied.count,
                traceDir: ConfigManager.traceDirectory
            )

            // Terminal output for curator result
            let curatorMs = durationToMs(ContinuousClock.now - curatorStart)
            if let output = Self.formatCuratorSummary(consolidationCount: result.consolidations.count, pruningCount: result.prunings.count, durationMs: curatorMs) {
                fputs("\(output)\n", stderr)
            }
        } catch {
            axionIntelligentCuratorLogger.warning("Curator failed for run \(runId): \(error.localizedDescription)")
            TraceRecorder.recordCuratorFailed(
                runId: runId,
                error: error.localizedDescription,
                traceDir: ConfigManager.traceDirectory
            )
        }
    }

    // MARK: - Formatting

    /// Formats a review summary string for terminal output.
    /// Returns nil when there are no changes (to avoid noise).
    static func formatReviewSummary(memoryChanges: [String], skillChanges: [String], durationMs: Int = 0) -> String? {
        guard !memoryChanges.isEmpty || !skillChanges.isEmpty else { return nil }
        var parts: [String] = []
        if !memoryChanges.isEmpty {
            parts.append("保存了 \(memoryChanges.count) 条记忆")
        }
        if !skillChanges.isEmpty {
            parts.append("更新了 \(skillChanges.count) 个技能")
        }
        let timing = durationMs > 0 ? " [\(formatDurationMs(durationMs))]" : ""
        return "[axion] Review: \(parts.joined(separator: ", "))\(timing)"
    }

    /// Formats a curator summary string for terminal output.
    /// Returns nil when there are no changes (to avoid noise).
    static func formatCuratorSummary(consolidationCount: Int, pruningCount: Int, durationMs: Int = 0) -> String? {
        guard consolidationCount > 0 || pruningCount > 0 else { return nil }
        var parts: [String] = []
        if consolidationCount > 0 {
            parts.append("合并 \(consolidationCount) 个技能")
        }
        if pruningCount > 0 {
            parts.append("归档 \(pruningCount) 个技能")
        }
        let timing = durationMs > 0 ? " [\(formatDurationMs(durationMs))]" : ""
        return "[axion] Curator: \(parts.joined(separator: ", "))\(timing)"
    }
}
