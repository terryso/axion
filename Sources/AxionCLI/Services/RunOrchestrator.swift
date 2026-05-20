import Foundation
import OpenAgentSDK

import AxionCore

/// Encapsulates the full agent execution pipeline: stream loop with all concerns
/// (visual delta, cost tracking, seat monitoring, takeover, trace recording),
/// lock management, SIGINT handling, and post-run processing.
///
/// Called by RunCommand (CLI) and could be reused by other execution contexts.
/// All configuration is passed via parameters — no mutable state.
enum RunOrchestrator {

    // MARK: - Types

    struct RunConfig: Sendable {
        let task: String
        let fast: Bool
        let dryrun: Bool
        let json: Bool
        let noMemory: Bool
        let noVisualDelta: Bool
        let allowForeground: Bool
        let maxSteps: Int?
        let config: AxionConfig
    }

    struct RunResult: Sendable {
        let totalSteps: Int
        let durationMs: Int
        let runSucceeded: Bool
    }

    // MARK: - Main Execution

    /// Executes the full agent pipeline: lock → trace → stream loop → cleanup → post-run.
    static func execute(
        buildResult: AgentBuildResult,
        runConfig: RunConfig
    ) async throws -> RunResult {
        let agent = buildResult.agent
        let memoryDir = buildResult.memoryDir
        let memoryStore = buildResult.agentOptions.memoryStore as! FileBasedMemoryStore
        let config = runConfig.config

        // Output handler
        let runMode = traceMode(fast: runConfig.fast, dryrun: runConfig.dryrun)
        let outputHandler: any SDKMessageOutputHandler = runConfig.json
            ? SDKJSONOutputHandler(mode: runMode)
            : SDKTerminalOutputHandler(mode: runMode)

        // TakeoverIO
        let takeoverIO: TakeoverIO
        if runConfig.json {
            takeoverIO = TakeoverIO(
                write: { fputs($0 + "\n", stderr); fflush(stderr) },
                readLine: { Swift.readLine() }
            )
        } else {
            takeoverIO = TakeoverIO()
        }

        let runId = generateRunId()
        outputHandler.displayRunStart(runId: runId, task: runConfig.task)

        // Desktop-level run lock
        let runLockService = RunLockService()
        if !runConfig.dryrun {
            let acquired = await runLockService.acquire(runId: runId)
            if !acquired {
                if let existingLock = await runLockService.readExistingLock() {
                    throw AxionError.runLocked(runId: existingLock.runId, pid: existingLock.pid)
                } else {
                    throw AxionError.runLocked(runId: "unknown", pid: 0)
                }
            }
        }

        // Trace recorder
        let tracer = try? TraceRecorder(runId: runId, config: config)
        await tracer?.recordRunStart(runId: runId, task: runConfig.task, mode: runMode)

        if !runConfig.dryrun {
            await tracer?.record(event: TraceRecorder.TraceEventType.lockAcquired, payload: [
                "runId": runId,
                "pid": ProcessInfo.processInfo.processIdentifier
            ])
        }

        // Pre-run memory cleanup
        if !runConfig.noMemory {
            await RunMemoryProcessor.preRunCleanup(memoryStore: memoryStore, memoryDir: memoryDir)
        }

        // SIGINT handler
        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        sigintSource.setEventHandler {
            agent.interrupt()
        }
        sigintSource.resume()

        // Stream loop state
        var totalSteps = 0
        var resultToolPairs: [SDKMessage.ToolExecutionPair] = []
        var pendingScreenshotToolUseIds: Set<String> = []
        var visualDeltaSkipped = 0
        var visualDeltaChecked = 0
        var externallyModified = false
        var takeoverEvent: (issue: String, summary: String, feedback: String?, reason: String, duration: TimeInterval?)? = nil
        var runSucceeded = false
        var runCompleted = false

        let visualDeltaTracker = runConfig.noVisualDelta ? nil : VisualDeltaTracker()
        let costTracker = CostTracker(maxScreenshots: config.maxScreenshots)
        let seatMonitor = (config.sharedSeatMode && !runConfig.allowForeground && !runConfig.dryrun)
            ? await SeatActivityMonitor.create() : nil
        if let monitor = seatMonitor {
            await tracer?.recordSeatBaseline(baseline: await monitor.describeBaseline())
        }

        let startTime = ContinuousClock.now

        // Stream loop
        await withTaskCancellationHandler {
            let messageStream = agent.stream(runConfig.task)
            for await message in messageStream {
                if _Concurrency.Task.isCancelled { break }
                if case .toolUse = message { totalSteps += 1 }
                outputHandler.handleMessage(message)
                await recordToTrace(message: message, tracer: tracer)

                switch message {
                case .assistant:
                    break
                case .toolUse(let data):
                    if data.toolName.contains("screenshot") {
                        pendingScreenshotToolUseIds.insert(data.toolUseId)
                        let budgetResult = await costTracker.recordScreenshot()
                        if case .screenshotsExceeded(let limit) = budgetResult {
                            let current = await costTracker.currentScreenshotCount
                            await tracer?.recordBudgetExceeded(budgetType: "screenshots", current: current, limit: limit)
                        }
                    }
                case .toolResult(let data):
                    if pendingScreenshotToolUseIds.remove(data.toolUseId) != nil,
                       let tracker = visualDeltaTracker {
                        let base64 = extractBase64FromToolResult(data.content)
                        if let base64 {
                            let vdResult = await tracker.processScreenshot(base64: base64)
                            visualDeltaChecked += 1
                            if vdResult.shouldSkipVerifier {
                                visualDeltaSkipped += 1
                                if case .unchanged(let pct) = vdResult {
                                    await tracer?.recordVerifierSkipped(
                                        deltaPercentage: pct,
                                        reason: "visual_delta_low"
                                    )
                                }
                            }
                        }
                    }
                case .system(let data):
                    switch data.subtype {
                    case .paused:
                        guard let pausedData = data.pausedData else { break }
                        let takeoverStartTime = ContinuousClock.now
                        await tracer?.record(event: "takeover_paused", payload: [
                            "reason": pausedData.reason
                        ])
                        let result = takeoverIO.displayTakeoverPrompt(
                            reason: pausedData.reason,
                            allowForeground: runConfig.allowForeground,
                            completedSteps: totalSteps
                        )
                        switch result.action {
                        case .resume:
                            let userAction = result.userInput?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                ? result.userInput! : "用户已完成手动操作"
                            takeoverIO.write("[axion] 正在恢复执行...")
                            let elapsed = ContinuousClock.now - takeoverStartTime
                            let durationSeconds = TakeoverMarker.durationToSeconds(elapsed)
                            takeoverEvent = (issue: pausedData.reason, summary: userAction, feedback: result.feedback, reason: pausedData.reason, duration: durationSeconds)
                            agent.resume(context: userAction)
                            if let feedback = result.feedback {
                                await tracer?.record(event: "takeover_resumed", payload: [
                                    "context": userAction,
                                    "method": "resume",
                                    "feedback": feedback
                                ])
                            } else {
                                await tracer?.record(event: "takeover_resumed", payload: [
                                    "context": userAction,
                                    "method": "resume"
                                ])
                            }
                        case .skip:
                            agent.resume(context: "skip")
                            await tracer?.record(event: "takeover_resumed", payload: [
                                "context": "skip"
                            ])
                        case .abort:
                            agent.interrupt()
                            await tracer?.record(event: "takeover_aborted", payload: [
                                "completedSteps": totalSteps
                            ])
                        }
                    case .pausedTimeout:
                        takeoverIO.displayTimeoutPrompt()
                        await tracer?.record(event: "takeover_timeout", payload: [:])
                    default:
                        break
                    }
                case .result(let data):
                    resultToolPairs = data.toolPairs
                    switch data.subtype {
                    case .success:
                        runSucceeded = true
                        runCompleted = true
                    case .errorMaxTurns, .errorMaxBudgetUsd, .errorDuringExecution, .errorMaxStructuredOutputRetries, .errorMaxModelCalls:
                        runCompleted = true
                    default:
                        break
                    }
                    await costTracker.finalizeWithSDKData(
                        usage: data.usage,
                        totalCostUsd: data.totalCostUsd,
                        costBreakdown: data.costBreakdown
                    )
                default:
                    break
                }
            }
        } onCancel: {
            agent.interrupt()
        }

        // Post-stream: external desktop activity check
        if let activity = await seatMonitor?.check() {
            externallyModified = true
            await tracer?.recordExternalActivityDetected(
                description: activity, phase: "post_stream")
            fputs("[axion] 检测到外部桌面操作，本次运行的经验不会被记忆\n", stderr)
        }

        let elapsed = ContinuousClock.now - startTime
        let durationMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000)

        // Cleanup
        try? await agent.close()
        sigintSource.cancel()
        signal(SIGINT, SIG_DFL)
        outputHandler.displayCompletion()

        // Visual delta statistics
        if visualDeltaChecked > 0 {
            fputs("[axion] 视觉增量: 跳过 \(visualDeltaSkipped)/\(visualDeltaChecked) 次验证\n", stderr)
        }

        // Cost summary
        let costSummary = await costTracker.getSummary()
        fputs("[axion] LLM 调用: \(costSummary.modelCalls)次, Tokens: \(costSummary.totalTokens), 预估成本: $\(String(format: "%.2f", costSummary.estimatedCostUsd)), 截图: \(costSummary.screenshotCount)次\n", stderr)

        await tracer?.recordRunDone(totalSteps: totalSteps, durationMs: durationMs, replanCount: 0)
        await tracer?.close()

        // Post-run memory processing
        let takeoverContext: RunMemoryProcessor.TakeoverEventContext? = takeoverEvent.map { event in
            RunMemoryProcessor.TakeoverEventContext(
                issue: event.issue,
                summary: event.summary,
                feedback: event.feedback,
                reason: event.reason,
                duration: event.duration
            )
        }
        await RunMemoryProcessor.processRunResult(
            toolPairs: resultToolPairs,
            task: runConfig.task,
            runId: runId,
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            noMemory: runConfig.noMemory,
            externallyModified: externallyModified,
            takeoverEvent: takeoverContext,
            runSucceeded: runSucceeded,
            runCompleted: runCompleted,
            tracer: tracer
        )

        // Lock release
        if !runConfig.dryrun {
            await tracer?.record(event: TraceRecorder.TraceEventType.lockReleased, payload: [
                "runId": runId
            ])
            await runLockService.release()
        }

        return RunResult(totalSteps: totalSteps, durationMs: durationMs, runSucceeded: runSucceeded)
    }

    // MARK: - Skill Direct Execution

    /// Executes a prompt skill directly via `executeSkillStream`, bypassing the full agent build.
    static func executeSkillDirectly(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        json: Bool,
        fast: Bool,
        verbose: Bool
    ) async throws {
        let agent = try await AgentBuilder.buildSkillAgent(
            config: config,
            skill: skill,
            verbose: verbose
        )

        let args = parseSkillName(from: task).flatMap { skillName in
            let prefix = "/\(skillName) "
            return task.hasPrefix(prefix) ? String(task.dropFirst(prefix.count)) : nil
        }

        let runId = generateRunId()
        let runMode = fast ? "fast" : "standard"
        let outputHandler: any SDKMessageOutputHandler = json
            ? SDKJSONOutputHandler(mode: runMode)
            : SDKTerminalOutputHandler(mode: runMode)
        outputHandler.displayRunStart(runId: runId, task: task)
        fputs("[axion] 模式: \(runMode)\n", stderr)
        fputs("[axion] 运行 ID: \(runId)\n", stderr)
        fputs("[axion] 任务: \(task)\n", stderr)
        fputs("[axion] 执行: Skill (direct)\n", stderr)

        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        sigintSource.setEventHandler { agent.interrupt() }
        sigintSource.resume()

        let startTime = ContinuousClock.now
        var totalSteps = 0
        let costTracker = CostTracker(maxScreenshots: config.maxScreenshots)

        let skillStream = agent.executeSkillStream(skill.name, args: args)

        for await message in skillStream {
            if _Concurrency.Task.isCancelled { break }
            if case .toolUse = message { totalSteps += 1 }
            outputHandler.handleMessage(message)

            if case .toolUse(let data) = message {
                if data.toolName.contains("screenshot") {
                    _ = await costTracker.recordScreenshot()
                }
            }
        }

        let elapsed = ContinuousClock.now - startTime
        let durationMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000)
        fputs("[axion] 运行结束。步数: \(totalSteps), 耗时: \(String(format: "%.1f", Double(durationMs) / 1000))s\n", stderr)

        try? await agent.close()
    }

    // MARK: - Shared Helpers

    /// Parses a skill name from a task that starts with `/`.
    static func parseSkillName(from task: String) -> String? {
        guard task.hasPrefix("/") else { return nil }
        let afterSlash = task.dropFirst()
        let name = afterSlash.split(separator: " ", maxSplits: 1).first.map(String.init) ?? String(afterSlash)
        return name.isEmpty ? nil : name
    }

    /// Generates a unique run ID in the format `YYYYMMDD-{6random}`.
    static func generateRunId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let datePart = formatter.string(from: Date())
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomPart = String((0..<6).map { _ in chars.randomElement()! })
        return "\(datePart)-\(randomPart)"
    }

    /// Computes the effective max steps for the agent loop.
    /// In fast mode, caps at 5 to reduce LLM calls (NFR28).
    static func computeEffectiveMaxSteps(fast: Bool, maxSteps: Int?, configMaxSteps: Int) -> Int {
        if fast {
            return min(maxSteps ?? configMaxSteps, 5)
        }
        return maxSteps ?? configMaxSteps
    }

    /// Computes the effective max tokens for the agent loop.
    /// In fast mode, reduces to 2048 to limit output token consumption.
    static func computeEffectiveMaxTokens(fast: Bool) -> Int {
        return fast ? 2048 : 4096
    }

    /// Computes the run mode string for trace and output handlers.
    /// Fast takes priority over dryrun when both are set.
    static func traceMode(fast: Bool, dryrun: Bool) -> String {
        return fast ? "fast" : (dryrun ? "dryrun" : "standard")
    }

    /// Build a text content string from an AppProfile for storage as KnowledgeEntry.
    static func buildProfileContent(profile: AppProfile) -> String {
        var lines: [String] = []
        lines.append("App Profile: \(profile.domain)")
        lines.append("总运行次数: \(profile.totalRuns)")
        lines.append("成功次数: \(profile.successfulRuns)")
        lines.append("失败次数: \(profile.failedRuns)")
        lines.append("已熟悉: \(profile.isFamiliar ? "是" : "否")")

        if !profile.axCharacteristics.isEmpty {
            lines.append("AX特征: \(profile.axCharacteristics.joined(separator: ", "))")
        }

        if !profile.commonPatterns.isEmpty {
            let patternDescs = profile.commonPatterns.map { pattern in
                "\(pattern.sequence.joined(separator: " → ")) (频率:\(pattern.frequency), 成功率:\(Int(round(pattern.successRate * 100)))%)"
            }
            lines.append("高频路径: \(patternDescs.joined(separator: "; "))")
        }

        if !profile.knownFailures.isEmpty {
            let failureDescs = profile.knownFailures.map { failure in
                if let workaround = failure.workaround {
                    return "\(failure.failedAction) — \(failure.reason) (修正: \(workaround))"
                } else {
                    return "\(failure.failedAction) — \(failure.reason)"
                }
            }
            lines.append("已知失败: \(failureDescs.joined(separator: "; "))")
        }

        return lines.joined(separator: "\n")
    }

    /// Extracts base64 image data from a screenshot tool result's content string.
    static func extractBase64FromToolResult(_ content: String) -> String? {
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let imageData = json["image_data"] as? String {
                return imageData
            }
            if let base64 = json["base64"] as? String {
                return base64
            }
            if let imageData = json["image"] as? String {
                return imageData
            }
        }
        let stripped = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.count > 100 && Data(base64Encoded: stripped) != nil {
            return stripped
        }
        return nil
    }

    /// Static wrapper for test backward compatibility.
    static func extractBase64FromToolResultForTest(_ content: String) -> String? {
        return extractBase64FromToolResult(content)
    }

    // MARK: - Trace Recording

    /// Records an SDKMessage to the trace file.
    private static func recordToTrace(message: SDKMessage, tracer: TraceRecorder?) async {
        guard let tracer else { return }
        switch message {
        case .assistant(let data):
            await tracer.record(event: "assistant_message", payload: [
                "text": String(data.text.prefix(200)),
                "model": data.model,
                "stopReason": data.stopReason
            ])
        case .toolUse(let data):
            var payload: [String: Any] = [
                "tool": data.toolName,
                "toolUseId": data.toolUseId
            ]
            if let inputObj = try? JSONSerialization.jsonObject(with: Data(data.input.utf8)) as? [String: Any] {
                if let windowId = inputObj["window_id"] {
                    payload["window_id"] = windowId
                }
                if let pid = inputObj["pid"] {
                    payload["pid"] = pid
                }
            }
            await tracer.record(event: "tool_use", payload: payload)
        case .toolResult(let data):
            var payload: [String: Any] = [
                "toolUseId": data.toolUseId,
                "isError": data.isError,
                "content": String(data.content.prefix(200))
            ]
            if let resultObj = try? JSONSerialization.jsonObject(with: Data(data.content.utf8)) as? [String: Any] {
                if let appName = resultObj["app_name"] as? String {
                    payload["app_name"] = appName
                }
                if let windowId = resultObj["window_id"] as? Int {
                    payload["window_id"] = windowId
                }
            }
            await tracer.record(event: "tool_result", payload: payload)
        case .result(let data):
            await tracer.record(event: "result", payload: [
                "subtype": data.subtype.rawValue,
                "numTurns": data.numTurns,
                "durationMs": data.durationMs
            ])
        case .partialMessage:
            break
        default:
            break
        }
    }
}
