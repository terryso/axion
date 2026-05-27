import Foundation
import os
import OpenAgentSDK

import AxionCore

/// ApiRunner — independent Agent execution for HTTP API endpoints.
/// Uses shared AgentBuilder for agent construction (same builder as RunCommand).
///
/// **Design Decisions:**
/// - **Shared builder, separate orchestration**: ApiRunner uses `AgentBuilder.build()` (the same
///   builder as RunCommand) but handles its own SSE broadcasting, cost tracking, and result
///   persistence — concerns unique to the HTTP API path.
/// - **Completion callback pattern**: uses a traditional callback (`completion: @escaping`) alongside
///   the modern async return value. This bridges the gap with the HTTP API's Task.detached execution
///   model where the caller needs both immediate return (HTTP 202) and eventual notification.
/// - **Optional SSE broadcasting**: the `eventBroadcaster` parameter is nil in CLI mode and non-nil
///   in HTTP API mode. This avoids any runtime cost for CLI users while enabling real-time progress
///   streaming for API consumers. Events are emitted per tool invocation (step_started/step_completed).
/// - **Status mapping**: internal SDK `ResultData.Subtype` is mapped to `APIRunStatus` enum, providing
///   a clean API boundary that abstracts SDK internals. Only `success`/`none` → `.done`; everything
///   else → `.failed`. Detailed error information lives in `stepSummaries`, not the status field.
/// - **Cost data from SDK**: Cost telemetry is built directly from `SDKMessage.ResultData` fields
///   (totalCostUsd, usage, costBreakdown).
enum ApiRunner {

    /// Run a prompt skill as an agent task through AxionRuntime.
    static func runSkillAgent(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        runId: String = "",
        eventBroadcaster: OpenAgentSDK.EventBroadcaster? = nil,
        runTracker: RunCoordinator? = nil,
        verbose: Bool = false,
        completion: @escaping (String, APIRunStatus, [StepSummary], Int?, Int, CostTelemetry?, Bool) -> Void
    ) async -> (totalSteps: Int, durationMs: Int, replanCount: Int, finalStatus: APIRunStatus, stepSummaries: [StepSummary], costTelemetry: CostTelemetry?, externallyModified: Bool) {
        // Execute skill through AxionRuntime
        let eventBus = EventBus()
        let runtime = AxionRuntime(eventBus: eventBus)

        await runtime.registerHandler(CostEventHandler())
        let traceDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("runs")
        await runtime.registerHandler(TraceEventHandler(traceDir: traceDir))

        let eventLoopTask = _Concurrency.Task { await runtime.startEventLoop() }

        let buildConfig = AgentBuilder.BuildConfig.forSkillExecution(
            config: config,
            skill: skill,
            verbose: verbose
        )

        let overrides = AxionRuntime.RunOverrides(
            json: false,
            noVisualDelta: true,
            noReview: true,
            onReviewCompleted: nil
        )

        let runResult: AxionRunResult
        do {
            runResult = try await runtime.executeSkill(
                skill: skill,
                task: task,
                config: config,
                buildConfig: buildConfig,
                runOverrides: overrides
            )
        } catch {
            eventLoopTask.cancel()
            await runtime.stopEventLoop()
            completion("", .failed, [], nil, 0, nil, false)
            return (0, 0, 0, .failed, [], nil, false)
        }
        eventLoopTask.cancel()
        await runtime.stopEventLoop()

        let finalStatus: APIRunStatus = runResult.runSucceeded ? .completed : .failed
        completion("", finalStatus, [], nil, 0, nil, false)

        return (runResult.totalSteps, runResult.durationMs, 0, finalStatus, [], nil, false)
    }

    /// Heuristic to classify task result as answer (informational) or confirmation (action performed).
    static func inferResultKind(task: String) -> TaskResultKind {
        let answerKeywords = ["读取", "查询", "获取", "列出", "搜索", "告诉我", "显示", "查看", "是什么", "有哪些", "read", "query", "get", "list", "search", "show", "tell", "what", "find"]
        let confirmationKeywords = ["打开", "关闭", "移动", "删除", "创建", "复制", "粘贴", "输入", "填写", "安装", "卸载", "open", "close", "move", "delete", "create", "copy", "paste", "type", "install", "uninstall"]

        let lowerTask = task.lowercased()
        for keyword in answerKeywords {
            if lowerTask.contains(keyword) { return .answer }
        }
        for keyword in confirmationKeywords {
            if lowerTask.contains(keyword) { return .confirmation }
        }
        return .confirmation
    }
}
