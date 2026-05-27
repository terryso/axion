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

    /// Run a prompt skill as an agent task using SDK's executeSkillStream().
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
        // Build minimal skill agent (no MCP, core tools only)
        let agent: Agent
        do {
            agent = try await AgentBuilder.buildSkillAgent(
                config: config,
                skill: skill,
                verbose: verbose
            )
        } catch {
            completion("", .failed, [], nil, 0, nil, false)
            return (0, 0, 0, .failed, [], nil, false)
        }

        // Use executeSkillStream for streaming skill execution
        let skillStream = agent.executeSkillStream(skill.name, args: task)
        let result = await processStreamFromAsyncStream(
            messageStream: skillStream,
            model: skill.modelOverride ?? config.model,
            runId: runId,
            eventBroadcaster: eventBroadcaster,
            runTracker: runTracker
        )

        completion("", result.finalStatus, result.stepSummaries, nil, 0, result.costTelemetry, result.externallyModified)

        // Track skill usage
        let skillsDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
        let usageStore = SkillUsageStore(skillsDir: skillsDir)
        do {
            try await usageStore.bumpView(skillName: skill.name)
        } catch {
            let logger = Logger(subsystem: "com.axion.cli", category: "SkillUsage")
            logger.warning("Skill usage tracking failed for '\(skill.name)': \(error.localizedDescription)")
        }

        return (result.totalSteps, result.durationMs, 0, result.finalStatus, result.stepSummaries, result.costTelemetry, result.externallyModified)
    }

    /// Result of processing an agent's message stream.
    private struct StreamResult {
        let totalSteps: Int
        let durationMs: Int
        let stepSummaries: [StepSummary]
        let costTelemetry: CostTelemetry?
        let externallyModified: Bool
        let finalStatus: APIRunStatus
    }

    /// Process a pre-built `AsyncStream<SDKMessage>` (e.g., from `executeSkillStream()`).
    private static func processStreamFromAsyncStream(
        messageStream: AsyncStream<SDKMessage>,
        task: String = "",
        model: String,
        runId: String,
        eventBroadcaster: OpenAgentSDK.EventBroadcaster?,
        runTracker: RunCoordinator? = nil,
        shouldMonitorSeat: Bool = false,
        maxScreenshots: Int? = nil,
        usageStore: SkillUsageStore? = nil,
        cleanup: @escaping () async -> Void = {}
    ) async -> StreamResult {
        var totalSteps = 0
        var stepSummaries: [StepSummary] = []
        var pendingToolUses: [String: SDKMessage.ToolUseData] = [:]
        var resultSubtype: SDKMessage.ResultData.Subtype? = nil
        var resultCostTelemetry: CostTelemetry? = nil
        var externallyModified = false
        var seatActivityReported = false
        var screenshotCount = 0
        var seatMonitor: SeatActivityMonitor? = nil
        let startTime = ContinuousClock.now

        for await message in messageStream {
            if _Concurrency.Task.isCancelled { break }

            switch message {
            case .assistant:
                // Seat activity check (Story 13.4)
                if let activity = await seatMonitor?.check() {
                    externallyModified = true
                    if !seatActivityReported {
                        fputs("[axion] 检测到外部桌面操作，本次运行的经验不会被记忆\n", stderr)
                        seatActivityReported = true
                    }
                }

            case .toolUse(let data):
                totalSteps += 1
                pendingToolUses[data.toolUseId] = data

                // Lazy-init seat monitor on first Helper tool call
                if seatMonitor == nil, shouldMonitorSeat, data.toolName.hasPrefix("mcp__axion-helper__") {
                    seatMonitor = SeatActivityMonitor.create()
                }

                // Track screenshot calls for cost telemetry
                if data.toolName.contains("screenshot") {
                    screenshotCount += 1
                }

                // Track Skill tool usage
                if data.toolName == "Skill", let store = usageStore {
                    let skillName = RunOrchestrator.extractSkillName(from: data.input)
                    if let skillName {
                        do {
                            try await store.bumpView(skillName: skillName)
                        } catch {
                            let logger = Logger(subsystem: "com.axion.cli", category: "SkillUsage")
                            logger.warning("Skill usage tracking failed for '\(skillName)': \(error.localizedDescription)")
                        }
                    }
                }

                // Emit step_started SSE event (Story 5.2)
                if let broadcaster = eventBroadcaster, !runId.isEmpty {
                    let stepIndex = totalSteps - 1
                    let event = AgentSSEEvent.stepStarted(StepStartedData(
                        stepIndex: stepIndex,
                        tool: data.toolName
                    ))
                    await broadcaster.emit(runId: runId, event: event)
                }

            case .toolResult(let data):
                if let toolUse = pendingToolUses.removeValue(forKey: data.toolUseId) {
                    let stepIndex = stepSummaries.count
                    stepSummaries.append(StepSummary(
                        index: stepIndex,
                        tool: toolUse.toolName,
                        purpose: extractPurpose(from: toolUse),
                        success: !data.isError
                    ))

                    // Emit step_completed SSE event (Story 5.2)
                    if let broadcaster = eventBroadcaster, !runId.isEmpty {
                        let event = AgentSSEEvent.stepCompleted(StepCompletedData(
                            stepIndex: stepIndex,
                            tool: toolUse.toolName,
                            success: !data.isError,
                            durationMs: nil
                        ))
                        await broadcaster.emit(runId: runId, event: event)
                    }
                }

            case .result(let data):
                resultSubtype = data.subtype
                // Build cost telemetry directly from SDK's ResultData
                let modelCalls = data.costBreakdown.filter { $0.inputTokens > 0 || $0.outputTokens > 0 }.count
                let totalTokens = (data.usage?.inputTokens ?? 0) + (data.usage?.outputTokens ?? 0)
                resultCostTelemetry = CostTelemetry(
                    modelCalls: modelCalls,
                    totalTokens: totalTokens,
                    estimatedCostUsd: data.totalCostUsd,
                    screenshotCount: screenshotCount
                )

                // Infer result kind and write ApiTaskResult (Story 14.1)
                if let tracker = runTracker, !runId.isEmpty {
                    let kind = inferResultKind(task: task)
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let taskResult = ApiTaskResult(
                        kind: kind,
                        title: task,
                        body: String(data.text.prefix(500)),
                        createdAt: formatter.string(from: Date())
                    )
                    await tracker.updateRunResult(runId: runId, result: taskResult)
                }

            default:
                break
            }
        }

        let elapsed = ContinuousClock.now - startTime
        let durationMs = Int(
            elapsed.components.seconds * 1000 +
            elapsed.components.attoseconds / 1_000_000_000_000
        )

        // Cleanup
        await cleanup()

        let finalStatus: APIRunStatus
        switch resultSubtype {
        case .success:
            finalStatus = .completed
        case .none:
            finalStatus = .completed
        default:
            finalStatus = .failed
        }

        return StreamResult(
            totalSteps: totalSteps,
            durationMs: durationMs,
            stepSummaries: stepSummaries,
            costTelemetry: resultCostTelemetry,
            externallyModified: externallyModified,
            finalStatus: finalStatus
        )
    }

    /// Extract a purpose description from a toolUse message.
    private static func extractPurpose(from data: SDKMessage.ToolUseData) -> String {
        return data.toolName
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
