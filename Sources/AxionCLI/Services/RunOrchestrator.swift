import Foundation
import os
import OpenAgentSDK

import AxionCore

/// Encapsulates the full agent execution pipeline: stream loop with all concerns
/// (visual delta, cost tracking, seat monitoring, takeover, trace recording),
/// lock management, SIGINT handling, and post-run processing.
///
/// Called by RunCommand (CLI) and could be reused by other execution contexts.
/// All configuration is passed via parameters — no mutable state.
enum RunOrchestrator {

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
        let noReview: Bool
        let onReviewCompleted: (@Sendable (String) -> Void)?
    }

    struct RunResult: Sendable {
        let totalSteps: Int
        let durationMs: Int
        let runSucceeded: Bool
    }

    /// Executes the full agent pipeline: lock → trace → stream loop → cleanup → post-run.
    static func execute(
        buildResult: AgentBuildResult,
        runConfig: RunConfig
    ) async throws -> RunResult {
        let agent = buildResult.agent
        let memoryDir = buildResult.memoryDir
        let runCompleteBox = buildResult.runCompleteBox
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

        // Trace recorder — SDK handles trace via AgentOptions.traceEnabled/traceBaseURL

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
        var pendingScreenshotToolUseIds: Set<String> = []
        var pendingLaunchAppToolUseIds: Set<String> = []
        var visualDeltaSkipped = 0
        var visualDeltaChecked = 0
        var externallyModified = false
        var takeoverEvent: (issue: String, summary: String, feedback: String?, reason: String, duration: TimeInterval?)? = nil
        var collectedMessages: [SDKMessage] = []

        let visualDeltaTracker = runConfig.noVisualDelta ? nil : VisualDeltaTracker()
        var resultText: String?
        var screenshotCount = 0
        var seatMonitor: SeatActivityMonitor? = nil
        let shouldMonitorSeat = config.sharedSeatMode && !runConfig.allowForeground && !runConfig.dryrun

        let startTime = ContinuousClock.now

        // Stream loop
        await withTaskCancellationHandler {
            let messageStream = agent.stream(runConfig.task)
            for await message in messageStream {
                if _Concurrency.Task.isCancelled { break }
                if case .toolUse = message { totalSteps += 1 }
                outputHandler.handle(message)

                // Collect messages for post-run review
                switch message {
                case .userMessage, .assistant, .toolResult, .toolUse:
                    collectedMessages.append(message)
                default:
                    break
                }

                switch message {
                case .assistant:
                    break
                case .toolUse(let data):
                    // Lazy-init seat monitor on first Helper tool call
                    if seatMonitor == nil, shouldMonitorSeat, data.toolName.hasPrefix("mcp__axion-helper__") {
                        seatMonitor = SeatActivityMonitor.create()
                    }
                    if data.toolName.contains("screenshot") {
                        pendingScreenshotToolUseIds.insert(data.toolUseId)
                        screenshotCount += 1
                    }
                    if data.toolName.contains("launch_app") {
                        pendingLaunchAppToolUseIds.insert(data.toolUseId)
                    }
                    // Track Skill tool usage
                    if data.toolName == "Skill", let store = buildResult.usageStore {
                        let skillName = extractSkillName(from: data.input)
                        if let skillName {
                            do {
                                try await store.bumpView(skillName: skillName)
                            } catch {
                                let logger = Logger(subsystem: "com.axion.cli", category: "SkillUsage")
                                logger.warning("Skill usage tracking failed for '\(skillName)': \(error.localizedDescription)")
                            }
                        }
                    }
                case .toolResult(let data):
                    // Activate app after launch_app (must run from CLI process, not AxionHelper)
                    if pendingLaunchAppToolUseIds.remove(data.toolUseId) != nil {
                        if let bundleId = extractBundleIdFromLaunchResult(data.content) {
                            activateAppFromCLI(bundleId: bundleId)
                        }
                    }
                    if pendingScreenshotToolUseIds.remove(data.toolUseId) != nil,
                       let tracker = visualDeltaTracker {
                        let base64 = extractBase64FromToolResult(data.content)
                        if let base64 {
                            let vdResult = await tracker.processScreenshot(base64: base64)
                            visualDeltaChecked += 1
                            if vdResult.shouldSkipVerifier {
                                visualDeltaSkipped += 1
                            }
                        }
                    }
                case .system(let data):
                    switch data.subtype {
                    case .paused:
                        guard let pausedData = data.pausedData else { break }
                        let takeoverStartTime = ContinuousClock.now
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
                        case .skip:
                            agent.resume(context: "skip")
                        case .abort:
                            agent.interrupt()
                        }
                    case .pausedTimeout:
                        takeoverIO.displayTimeoutPrompt()
                    default:
                        break
                    }
                case .result(let data):
                    resultText = data.text
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

        // Cost summary — from SDK's onRunComplete context
        let runCtx = runCompleteBox.context
        let costBreakdown = runCtx?.costBreakdown ?? []
        let modelCalls = costBreakdown.filter { $0.inputTokens > 0 || $0.outputTokens > 0 }.count
        let totalTokens = (runCtx?.usage.inputTokens ?? 0) + (runCtx?.usage.outputTokens ?? 0)
        let totalCost = runCtx?.totalCostUsd ?? 0
        fputs("[axion] LLM 调用: \(modelCalls)次, Tokens: \(totalTokens), 预估成本: $\(String(format: "%.2f", totalCost)), 截图: \(screenshotCount)次\n", stderr)

        // Post-run memory processing — using onRunComplete data
        let runSucceeded = runCtx?.status == .success
        let runCompleted = runCtx != nil
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
            toolPairs: runCtx?.toolPairs ?? [],
            task: runConfig.task,
            runId: runId,
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            noMemory: runConfig.noMemory,
            externallyModified: externallyModified,
            takeoverEvent: takeoverContext,
            runSucceeded: runSucceeded,
            runCompleted: runCompleted
        )

        // Post-run review — after memory processing, before lock release
        if let orchestrator = buildResult.reviewOrchestrator, !runConfig.dryrun, !runConfig.noMemory, !runConfig.noReview {
            let reviewConfig = ReviewAgentConfig()
            let (doMemory, doSkill) = orchestrator.shouldReview(
                sessionId: runId,
                messageCount: collectedMessages.count,
                config: reviewConfig
            )
            if doMemory || doSkill {
                let tunedConfig = ReviewAgentConfig(
                    reviewMemory: doMemory,
                    reviewSkills: doSkill
                )
                let result = await orchestrator.executeReview(
                    parentAgent: agent,
                    messages: collectedMessages,
                    config: tunedConfig
                )
                if let result {
                    let logger = Logger(subsystem: "com.axion.cli", category: "ReviewOrchestrator")
                    logger.info("Review completed: \(result.summary)")

                    // Track skill management usage
                    if let usageStore = buildResult.usageStore {
                        for skillName in result.skillChanges {
                            do {
                                try await usageStore.bumpManage(skillName: skillName)
                            } catch {
                                logger.warning("Skill manage tracking failed for '\(skillName)': \(error.localizedDescription)")
                            }
                        }
                    }

                    TraceRecorder.recordReviewCompleted(
                        runId: runId,
                        reviewSummary: result.summary,
                        memoryChanges: result.memoryChanges,
                        skillChanges: result.skillChanges,
                        traceDir: (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("runs")
                    )

                    // Terminal output for review result
                    if let output = Self.formatReviewSummary(memoryChanges: result.memoryChanges, skillChanges: result.skillChanges) {
                        fputs("\(output)\n", stderr)
                    }

                    runConfig.onReviewCompleted?(result.summary)
                } else {
                    let logger = Logger(subsystem: "com.axion.cli", category: "ReviewOrchestrator")
                    logger.warning("Review agent returned nil for run \(runId)")
                    TraceRecorder.recordReviewFailed(
                        runId: runId,
                        error: "review agent returned nil",
                        traceDir: (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("runs")
                    )
                }
            }
        }

        // Post-run curator — after review, before lock release
        if let curator = buildResult.intelligentCurator, !runConfig.dryrun, !runConfig.noMemory, !runConfig.noReview {
            let curatorDryRun = curator.skillCurator.config.dryRun
            let curatorState = await curator.curatorStore.loadState()
            if curator.skillCurator.shouldRun(state: curatorState) {
                do {
                    let result = try await curator.execute(parentAgent: agent, dryRun: curatorDryRun)
                    let report = CuratorRunReport(from: result)
                    let logger = Logger(subsystem: "com.axion.cli", category: "IntelligentCurator")
                    logger.info("Curator completed in \(result.durationMs)ms")
                    logger.debug("Curator report:\n\(report.renderMarkdown())")
                    TraceRecorder.recordCuratorCompleted(
                        runId: runId,
                        consolidations: result.consolidations.count,
                        prunings: result.prunings.count,
                        transitionsApplied: result.mechanicalResult.transitionsApplied.count,
                        traceDir: (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("runs")
                    )

                    // Terminal output for curator result
                    if let output = Self.formatCuratorSummary(consolidationCount: result.consolidations.count, pruningCount: result.prunings.count) {
                        fputs("\(output)\n", stderr)
                    }
                } catch {
                    let logger = Logger(subsystem: "com.axion.cli", category: "IntelligentCurator")
                    logger.warning("Curator failed for run \(runId): \(error.localizedDescription)")
                    TraceRecorder.recordCuratorFailed(
                        runId: runId,
                        error: error.localizedDescription,
                        traceDir: (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("runs")
                    )
                }
            }
        }

        // Lock release
        if !runConfig.dryrun {
            await runLockService.release()
        }

        // macOS desktop notification — user can't see terminal when AI operates a fullscreen app
        // Skip in JSON mode (programmatic use doesn't need desktop notifications)
        if !runConfig.json {
            let statusText = runSucceeded ? "完成" : (runCompleted ? "失败" : "已取消")
            let elapsedSec = Int(elapsed.components.seconds)
            let stats = "耗时 \(elapsedSec)s · LLM \(modelCalls)次 · $\(String(format: "%.2f", totalCost))"
            let summary = extractSummary(from: resultText) ?? "无结果摘要"
            sendDesktopNotification(title: "Axion \(statusText)", subtitle: stats, message: summary)

            // Bring terminal back to foreground after UI operations
            if totalSteps > 0 {
                activateTerminal()
            }
        }

        return RunResult(totalSteps: totalSteps, durationMs: durationMs, runSucceeded: runSucceeded)
    }

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
        var skillResultText: String?

        let skillStream = agent.executeSkillStream(skill.name, args: args)

        for await message in skillStream {
            if _Concurrency.Task.isCancelled { break }
            if case .toolUse = message { totalSteps += 1 }
            if case .result(let data) = message { skillResultText = data.text }
            outputHandler.handle(message)
        }

        let elapsed = ContinuousClock.now - startTime
        let durationMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000)
        fputs("[axion] 运行结束。步数: \(totalSteps), 耗时: \(String(format: "%.1f", Double(durationMs) / 1000))s\n", stderr)

        try? await agent.close()

        // Track skill usage
        let skillsDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
        let usageStore = SkillUsageStore(skillsDir: skillsDir)
        do {
            try await usageStore.bumpView(skillName: skill.name)
        } catch {
            let logger = Logger(subsystem: "com.axion.cli", category: "SkillUsage")
            logger.warning("Skill usage tracking failed for '\(skill.name)': \(error.localizedDescription)")
        }

        let elapsedSec = Int(elapsed.components.seconds)
        let summary = extractSummary(from: skillResultText) ?? "无结果摘要"
        sendDesktopNotification(title: "Axion 完成", subtitle: "耗时 \(elapsedSec)s", message: summary)
    }

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

    /// Extracts bundle_id from a launch_app tool result JSON (used for app activation).
    static func extractBundleIdFromLaunchResult(_ content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["bundle_id"] as? String
    }

    /// Activates an app using osascript with bundle id — runs from the CLI process (terminal) where it has permission.
    static func activateAppFromCLI(bundleId: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(bundleId)\" to activate"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[RunOrchestrator] osascript activate failed for \(bundleId): \(error)")
        }
    }

    /// Extracts the summary from AI result text by finding the [结果] marker.
    /// Returns nil if no marker found or text is empty.
    static func extractSummary(from text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let marker = "[结果]"
        // Find the last occurrence — AI may reference earlier content with the marker
        if let range = text.range(of: marker, options: .backwards) {
            let after = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty {
                return String(after.prefix(100))
            }
        }
        return nil
    }

    /// Brings the terminal app back to the foreground after UI automation.
    /// Uses TERM_PROGRAM env var to identify the terminal and activate it by bundle ID.
    static func activateTerminal() {
        let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? ""
        let bundleId: String
        switch termProgram {
        case "Apple_Terminal":
            bundleId = "com.apple.Terminal"
        case "iTerm.app":
            bundleId = "com.googlecode.iterm2"
        case "WarpTerminal":
            bundleId = "dev.warp.Warp-Stable"
        case "vscode":
            bundleId = "com.microsoft.VSCode"
        default:
            return
        }
        activateAppFromCLI(bundleId: bundleId)
    }

    /// Sends a macOS desktop notification via osascript.
    /// Uses `display notification` which works without any entitlements or bundle ID.
    /// Blocks briefly (~50ms) to ensure the notification fires before process exit.
    static func sendDesktopNotification(title: String, subtitle: String? = nil, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMessage = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var script = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\""
        if let subtitle {
            let escapedSubtitle = subtitle.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            script += " subtitle \"\(escapedSubtitle)\""
        }
        process.arguments = ["-e", script]
        if let pipe = try? Pipe() {
            process.standardOutput = pipe
            process.standardError = pipe
        }
        do {
            try process.run()
            process.waitUntilExit()
        } catch {}
    }

    /// Formats a review summary string for terminal output.
    /// Returns nil when there are no changes (to avoid noise).
    static func formatReviewSummary(memoryChanges: [String], skillChanges: [String]) -> String? {
        guard !memoryChanges.isEmpty || !skillChanges.isEmpty else { return nil }
        var parts: [String] = []
        if !memoryChanges.isEmpty {
            parts.append("保存了 \(memoryChanges.count) 条记忆")
        }
        if !skillChanges.isEmpty {
            parts.append("更新了 \(skillChanges.count) 个技能")
        }
        return "[axion] Review: \(parts.joined(separator: ", "))"
    }

    /// Formats a curator summary string for terminal output.
    /// Returns nil when there are no changes (to avoid noise).
    static func formatCuratorSummary(consolidationCount: Int, pruningCount: Int) -> String? {
        guard consolidationCount > 0 || pruningCount > 0 else { return nil }
        var parts: [String] = []
        if consolidationCount > 0 {
            parts.append("合并 \(consolidationCount) 个技能")
        }
        if pruningCount > 0 {
            parts.append("归档 \(pruningCount) 个技能")
        }
        return "[axion] Curator: \(parts.joined(separator: ", "))"
    }

    /// Extracts the skill name from a Skill tool's JSON input.
    static func extractSkillName(from input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["skill"] as? String
    }

}
