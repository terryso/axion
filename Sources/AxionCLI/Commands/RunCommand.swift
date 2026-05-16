import ArgumentParser
import Foundation
import OpenAgentSDK

import AxionCore

/// Main entry point for `axion run` — orchestrates the full agent execution pipeline.
///
/// **Design Decisions:**
/// - **Layered configuration** (defaults → config.json → env vars → CLI args): allows users to
///   configure at different levels of specificity without editing files. See `ConfigManager.loadConfig`.
/// - **Agent-as-SDK approach**: instead of implementing the agent loop natively, Axion delegates to
///   OpenAgentSDK's `createAgent` + `agent.stream()`. This avoids duplicating LLM API handling,
///   tool routing, and message management, while Axion focuses on desktop automation specifics.
/// - **MCP stdio for Helper**: the Helper process communicates via MCP JSON-RPC over stdio pipes,
///   not direct function calls. This process isolation ensures AX crashes don't take down the CLI,
///   and enables the Helper to be replaced or updated independently.
/// - **Memory as optional, non-fatal augmentation**: all memory operations are wrapped in do/catch
///   with warning-level logging. Memory failures never block task execution — users get a degraded
///   experience (no context) rather than a crash.
/// - **Takeover (pause/resume) via SDK's PauseForHumanTool**: instead of implementing custom pause
///   logic, Axion uses the SDK's built-in pause protocol. The agent emits `.paused` system messages,
///   and RunCommand handles the UI interaction (terminal prompt or JSON event).
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "执行桌面自动化任务"
    )

    @Argument(help: "任务描述")
    var task: String

    @Flag(name: .long, help: "干跑模式（仅生成计划不实际执行）")
    var dryrun: Bool = false

    @Option(name: .long, help: "单次运行最大步骤数")
    var maxSteps: Int?

    @Option(name: .long, help: "最大批次")
    var maxBatches: Int?

    @Flag(name: .long, help: "允许前台操作")
    var allowForeground: Bool = false

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    @Flag(name: .long, help: "JSON 格式输出")
    var json: Bool = false

    @Flag(name: .long, help: "禁用 Memory 上下文注入")
    var noMemory: Bool = false

    @Flag(name: .long, help: "快速模式：简化规划，减少 LLM 调用")
    var fast: Bool = false

    mutating func run() async throws {
        // 1. Load configuration (layered: defaults -> config.json -> env -> CLI args)
        let cliOverrides = CLIOverrides(
            maxSteps: maxSteps,
            maxBatches: maxBatches
        )
        let config = try await ConfigManager.loadConfig(cliOverrides: cliOverrides)

        // 2. Resolve API key: config -> environment variable
        let apiKey = config.apiKey
            ?? ProcessInfo.processInfo.environment["AXION_API_KEY"]

        guard let apiKey, !apiKey.isEmpty else {
            throw AxionError.missingApiKey(
                suggestion: "Run 'axion setup' to configure your API key, or set AXION_API_KEY environment variable."
            )
        }

        // 3. Resolve Helper path for MCP stdio server
        guard let helperPath = HelperPathResolver.resolveHelperPath() else {
            throw AxionError.helperNotFound(
                suggestion: "Ensure AxionHelper.app is installed. Run 'axion doctor' to diagnose."
            )
        }

        // 4. Create MemoryStore for cross-run knowledge accumulation (needed before prompt building)
        let memoryDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")
        let memoryStore = FileBasedMemoryStore(memoryDir: memoryDir)

        // 5. Load system prompt from planner-system.md
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let mcpPrefixedToolNames = ToolNames.allToolNames.map { "mcp__axion-helper__\($0)" }
        let baseSystemPrompt = try PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: mcpPrefixedToolNames),
                "max_steps": String(config.maxSteps),
            ],
            fromDirectory: promptDir
        )

        // Build full system prompt with mode-specific instructions
        // Memory context injection (AC1, AC2, AC3, AC4)
        var memoryContext: String? = nil
        if !noMemory {
            do {
                let contextProvider = MemoryContextProvider()
                memoryContext = try await contextProvider.buildMemoryContext(
                    task: task,
                    store: memoryStore
                )
            } catch {
                fputs("[axion] warning: memory context injection failed: \(error.localizedDescription)\n", stderr)
            }
        }

        let systemPrompt = buildFullSystemPrompt(
            basePrompt: baseSystemPrompt,
            fast: fast,
            dryrun: dryrun,
            verbose: verbose,
            memoryContext: memoryContext
        )

        // 6. Configure MCP server for Helper
        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        // 7. Build safety hook registry
        let hookRegistry = await buildSafetyHookRegistry(
            sharedSeatMode: config.sharedSeatMode && !allowForeground
        )

        // 8. Build AgentOptions
        let effectiveMaxSteps = Self.computeEffectiveMaxSteps(fast: fast, maxSteps: maxSteps, configMaxSteps: config.maxSteps)
        let effectiveMaxTokens = Self.computeEffectiveMaxTokens(fast: fast)

        let options = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: effectiveMaxSteps,
            maxTokens: effectiveMaxTokens,
            permissionMode: .bypassPermissions,
            tools: [createPauseForHumanTool()],
            mcpServers: mcpServers,
            memoryStore: memoryStore,
            hookRegistry: hookRegistry,
            logLevel: verbose ? .debug : .info,
            pauseTimeoutMs: 300_000
        )

        // 8. Create Agent
        let agent = createAgent(options: options)

        // 9. Select output handler
        let runMode = fast ? "fast" : (dryrun ? "dryrun" : "standard")
        let outputHandler: any SDKMessageOutputHandler = json
            ? SDKJSONOutputHandler(mode: runMode)
            : SDKTerminalOutputHandler(mode: runMode)

        // 10. Create TakeoverIO for pause interaction
        // JSON mode: prompt to stderr to keep stdout clean for JSON events
        let takeoverIO: TakeoverIO
        if json {
            takeoverIO = TakeoverIO(
                write: { fputs($0 + "\n", stderr); fflush(stderr) },
                readLine: { Swift.readLine() }
            )
        } else {
            takeoverIO = TakeoverIO()
        }

        // 10. Run with cancellation support
        let runId = Self.generateRunId()
        outputHandler.displayRunStart(runId: runId, task: task)

        let tracer = try? TraceRecorder(runId: runId, config: config)
        await tracer?.recordRunStart(runId: runId, task: task, mode: Self.traceMode(fast: fast, dryrun: dryrun))

        // Cleanup expired memory entries at run start
        do {
            let cleanupService = MemoryCleanupService()
            _ = try await cleanupService.cleanupExpired(in: memoryStore)
        } catch {
            fputs("[axion] warning: memory cleanup failed: \(error.localizedDescription)\n", stderr)
        }

        var totalSteps = 0
        let startTime = ContinuousClock.now
        var resumeWatchdog: _Concurrency.Task<Void, Never>? = nil

        // Collect toolUse/toolResult pairs for memory extraction (matched by toolUseId)
        var pendingToolUses: [String: SDKMessage.ToolUseData] = [:]
        var collectedPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = []

        await withTaskCancellationHandler {
            let messageStream = agent.stream(task)
            for await message in messageStream {
                if _Concurrency.Task.isCancelled { break }
                // Cancel resume watchdog on first message after takeover
                if let watchdog = resumeWatchdog {
                    watchdog.cancel()
                    resumeWatchdog = nil
                }
                if case .toolUse = message { totalSteps += 1 }
                outputHandler.handleMessage(message)
                await recordToTrace(message: message, tracer: tracer)

                // Collect tool pairs for memory extraction (match by toolUseId)
                switch message {
                case .toolUse(let data):
                    pendingToolUses[data.toolUseId] = data
                case .toolResult(let data):
                    if let toolUse = pendingToolUses.removeValue(forKey: data.toolUseId) {
                        collectedPairs.append((toolUse: toolUse, toolResult: data))
                    }
                case .system(let data):
                    switch data.subtype {
                    case .paused:
                        guard let pausedData = data.pausedData else { break }
                        await tracer?.record(event: "takeover_paused", payload: [
                            "reason": pausedData.reason
                        ])
                        let result = takeoverIO.displayTakeoverPrompt(
                            reason: pausedData.reason,
                            allowForeground: allowForeground,
                            completedSteps: totalSteps
                        )
                        switch result.action {
                        case .resume:
                            let resumeContext = result.userInput?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                ? "用户输入: \(result.userInput!)"
                                : "用户已完成手动操作"
                            agent.resume(context: resumeContext)
                            takeoverIO.write("[axion] Agent 正在恢复执行，请稍候...")
                            await tracer?.record(event: "takeover_resumed", payload: [
                                "context": resumeContext
                            ])
                            // Guard: if LLM doesn't respond within 90s after resume,
                            // interrupt and suggest running a follow-up task.
                            let capturedTask = task
                            let watchdogWrite: @Sendable (String) -> Void = { msg in fputs(msg + "\n", stdout); fflush(stdout) }
                            resumeWatchdog = _Concurrency.Task { @Sendable in
                                try? await _Concurrency.Task.sleep(nanoseconds: 90_000_000_000)
                                guard !_Concurrency.Task.isCancelled else { return }
                                watchdogWrite("[axion] LLM 响应超时，正在终止当前会话...")
                                watchdogWrite("[axion] 如需继续后续操作，请运行新任务，例如：")
                                watchdogWrite("  .build/debug/axion run \"继续之前的任务：\(capturedTask)\"")
                                agent.interrupt()
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
                default:
                    break
                }
            }
        } onCancel: {
            agent.interrupt()
        }

        let elapsed = ContinuousClock.now - startTime
        let durationMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000)

        // Cleanup — always runs even after cancellation
        try? await agent.close()
        outputHandler.displayCompletion()
        await tracer?.recordRunDone(totalSteps: totalSteps, durationMs: durationMs, replanCount: 0)
        await tracer?.close()

        // Extract and save memory (non-blocking — failures are logged but don't fail the run)
        do {
            let extractor = AppMemoryExtractor()
            let entries = try await extractor.extract(
                from: collectedPairs,
                task: task,
                runId: runId
            )
            var processedDomains: Set<String> = []
            for entry in entries {
                // Determine domain from tags (app:xxx)
                let domain = entry.tags.first(where: { $0.hasPrefix("app:") })?
                    .dropFirst("app:".count).description ?? "unknown"
                try await memoryStore.save(domain: domain, knowledge: entry)
                processedDomains.insert(domain)
            }

            // Story 4.2: Profile analysis and familiarity tracking
            for domain in processedDomains {
                do {
                    // Query history for this domain
                    let history = try await memoryStore.query(domain: domain, filter: nil)

                    // Analyze and generate AppProfile
                    let analyzer = AppProfileAnalyzer()
                    let profile = analyzer.analyze(domain: domain, history: history)

                    // Save profile as a KnowledgeEntry (only if there's meaningful data)
                    if profile.totalRuns > 0 {
                        let profileContent = Self.buildProfileContent(profile: profile)
                        let profileEntry = KnowledgeEntry(
                            id: UUID().uuidString,
                            content: profileContent,
                            tags: ["app:\(domain)", "profile"],
                            createdAt: Date(),
                            sourceRunId: nil
                        )
                        try await memoryStore.save(domain: domain, knowledge: profileEntry)
                    }

                    // Check and update familiarity
                    let tracker = FamiliarityTracker()
                    try await tracker.checkAndUpdateFamiliarity(domain: domain, store: memoryStore)
                } catch {
                    fputs("[axion] warning: profile analysis failed for \(domain): \(error.localizedDescription)\n", stderr)
                }
            }
        } catch {
            fputs("[axion] warning: memory extraction failed: \(error.localizedDescription)\n", stderr)
        }

    }

    // MARK: - Private Helpers

    /// Generates a unique run ID in the format `YYYYMMDD-{6random}`.
    private static func generateRunId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let datePart = formatter.string(from: Date())
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomPart = String((0..<6).map { _ in chars.randomElement()! })
        return "\(datePart)-\(randomPart)"
    }

    /// Computes the effective max steps for the agent loop.
    /// In fast mode, caps at 5 to reduce LLM calls (NFR28).
    internal static func computeEffectiveMaxSteps(fast: Bool, maxSteps: Int?, configMaxSteps: Int) -> Int {
        if fast {
            return min(maxSteps ?? configMaxSteps, 5)
        }
        return maxSteps ?? configMaxSteps
    }

    /// Computes the effective max tokens for the agent loop.
    /// In fast mode, reduces to 2048 to limit output token consumption.
    internal static func computeEffectiveMaxTokens(fast: Bool) -> Int {
        return fast ? 2048 : 4096
    }

    /// Computes the run mode string for trace and output handlers.
    /// Fast takes priority over dryrun when both are set.
    internal static func traceMode(fast: Bool, dryrun: Bool) -> String {
        return fast ? "fast" : (dryrun ? "dryrun" : "standard")
    }

    /// Builds the full system prompt with mode-specific instructions appended.
    internal func buildFullSystemPrompt(basePrompt: String, fast: Bool, dryrun: Bool, verbose: Bool, memoryContext: String? = nil) -> String {
        var prompt = basePrompt

        if fast {
            prompt += """

            IMPORTANT: You are in FAST mode. Generate the MINIMUM steps needed (1-3 steps max).
            - Skip discovery steps (list_apps, list_windows, get_accessibility_tree) when the target app is obvious
            - Do NOT call screenshot for verification — trust tool results
            - Prefer direct actions (launch_app, type_text, hotkey) over exploration
            - If a step fails, do NOT retry with alternative approaches — report failure immediately
            """
        }

        if dryrun {
            prompt += "\n\nIMPORTANT: You are in DRYRUN mode. Generate a plan but do NOT execute any tools. Return a plan JSON with status 'done' and the steps you would execute."
        }

        // Append Memory context if available
        if let memoryContext, !memoryContext.isEmpty {
            prompt += "\n\n\(memoryContext)"
        }

        return prompt
    }

    /// Creates a HookRegistry with preToolUse hook implementing SafetyChecker logic.
    private func buildSafetyHookRegistry(sharedSeatMode: Bool) async -> HookRegistry {
        let registry = HookRegistry()

        if sharedSeatMode {
            let foregroundTools = ToolNames.foregroundToolNames
            let safetyHook = HookDefinition(handler: { input in
                guard let toolName = input.toolName else { return HookOutput(decision: .approve) }

                if foregroundTools.contains(toolName) {
                    return HookOutput(
                        decision: .block,
                        reason: "Tool '\(toolName)' requires foreground interaction and is blocked in shared seat mode for safety. Use --allow-foreground to enable."
                    )
                }
                return HookOutput(decision: .approve)
            })

            await registry.register(.preToolUse, definition: safetyHook)
        }

        return registry
    }

    /// Build a text content string from an AppProfile for storage as KnowledgeEntry.
    /// Internal to allow unit testing (Story 4.3 Planner depends on this format).
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

    /// Records an SDKMessage to the trace file.
    private func recordToTrace(message: SDKMessage, tracer: TraceRecorder?) async {
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
            break  // Skip partial messages for trace brevity
        default:
            break
        }
    }
}

// MARK: - SDK Message Output Handlers

/// Protocol for handling SDK stream messages during execution.
protocol SDKMessageOutputHandler {
    func displayRunStart(runId: String, task: String)
    func handleMessage(_ message: SDKMessage)
    func displayCompletion()
}

/// Terminal output handler — displays human-readable progress via TerminalOutput.
/// Buffers streaming text from .partialMessage and flushes it as a single line
/// when a structured event (.assistant, .toolUse, .toolResult, .result) arrives.
/// This prevents streaming text fragments from interleaving with [axion] log lines.
final class SDKTerminalOutputHandler: SDKMessageOutputHandler {
    private let output: TerminalOutput
    private let mode: String
    private var streamBuffer = ""
    private var startTime: ContinuousClock.Instant?
    private var totalSteps = 0

    init(output: TerminalOutput = TerminalOutput(), mode: String = "standard") {
        self.output = output
        self.mode = mode
    }

    func displayRunStart(runId: String, task: String) {
        startTime = ContinuousClock.now
        output.displayRunStart(runId: runId, task: task, mode: mode)
    }

    func handleMessage(_ message: SDKMessage) {
        switch message {
        case .assistant(let data):
            if !streamBuffer.isEmpty {
                flushStreamBuffer()
            } else if !data.text.isEmpty {
                output.write("[axion] \(data.text)")
            }

        case .toolUse(let data):
            flushStreamBuffer()
            totalSteps += 1
            output.write("[axion] 执行: \(data.toolName)")

        case .toolResult(let data):
            flushStreamBuffer()
            if data.isError {
                output.write("[axion] 结果: 错误 — \(String(data.content.prefix(100)))")
            } else {
                let snippet = summarizeResult(data.content)
                output.write("[axion] 结果: \(snippet)")
            }

        case .result(let data):
            flushStreamBuffer()
            let isFast = mode == "fast"
            switch data.subtype {
            case .success:
                if !data.text.isEmpty {
                    output.write("[axion] 完成: \(data.text)")
                }
                if isFast {
                    let elapsed = computeElapsedSeconds()
                    output.write("[axion] Fast mode 完成。\(totalSteps) 步，耗时 \(elapsed) 秒。")
                    output.write("[axion] 如需更精确执行，可去掉 --fast 重试。")
                }
            case .errorMaxTurns:
                output.write("[axion] 达到最大步数限制 (\(data.numTurns) 步)")
                if isFast {
                    output.write("[axion] 建议去掉 --fast 重新尝试，允许更多步骤完成。")
                }
            case .errorMaxBudgetUsd:
                output.write("[axion] 预算超限")
            case .cancelled:
                output.write("[axion] 已取消")
            case .errorDuringExecution:
                output.write("[axion] 执行错误")
                if isFast {
                    output.write("[axion] 建议去掉 --fast 重新尝试。")
                }
            case .errorMaxStructuredOutputRetries:
                output.write("[axion] 结构化输出重试超限")
            }

        case .partialMessage(let data):
            streamBuffer += data.text

        case .system(let data):
            switch data.subtype {
            case .paused:
                flushStreamBuffer()
                if let pausedData = data.pausedData {
                    output.write("[axion] 任务暂停: \(pausedData.reason)")
                }
            case .pausedTimeout:
                flushStreamBuffer()
                output.write("[axion] 接管超时（5 分钟无操作），任务终止。")
            default:
                break
            }

        default:
            break
        }
    }

    func displayCompletion() {
        flushStreamBuffer()
        output.write("[axion] 运行结束。")
    }

    /// Flush any buffered streaming text as a single [axion] line.
    private func flushStreamBuffer() {
        if !streamBuffer.isEmpty {
            output.write("[axion] \(streamBuffer)")
            streamBuffer = ""
        }
    }

    private func summarizeResult(_ content: String) -> String {
        if content.hasPrefix("{\"action\":\"screenshot\"") || content.contains("image_data") || content.contains("[微压缩]") {
            return "[screenshot captured]"
        }
        if content.contains("Base64") || content.contains("base64") {
            return "[screenshot captured]"
        }
        return String(content.prefix(120))
    }

    private func computeElapsedSeconds() -> Int {
        guard let startTime else { return 0 }
        let elapsed = ContinuousClock.now - startTime
        return Int(elapsed.components.seconds)
    }
}

/// JSON output handler — accumulates data and produces structured JSON at completion.
/// Also outputs streaming paused events as JSON lines for JSON mode consumers.
final class SDKJSONOutputHandler: SDKMessageOutputHandler {
    private let write: (String) -> Void
    private let writeEvent: (String) -> Void
    private let mode: String
    private var runId: String = ""
    private var task: String = ""
    private var steps: [[String: Any]] = []
    private var errors: [[String: String]] = []
    private var resultData: SDKMessage.ResultData?

    init(
        mode: String = "standard",
        write: @escaping (String) -> Void = { print($0) },
        writeEvent: @escaping (String) -> Void = { print($0) }
    ) {
        self.mode = mode
        self.write = write
        self.writeEvent = writeEvent
    }

    func displayRunStart(runId: String, task: String) {
        self.runId = runId
        self.task = task
    }

    func handleMessage(_ message: SDKMessage) {
        switch message {
        case .toolUse(let data):
            steps.append([
                "tool": data.toolName,
                "toolUseId": data.toolUseId
            ])
        case .toolResult(let data):
            if data.isError {
                errors.append([
                    "toolUseId": data.toolUseId,
                    "message": String(data.content.prefix(200))
                ])
            }
        case .result(let data):
            resultData = data
        case .system(let data):
            switch data.subtype {
            case .paused:
                if let pausedData = data.pausedData {
                    let event: [String: Any] = [
                        "type": "paused",
                        "reason": pausedData.reason,
                        "canResume": pausedData.canResume,
                        "sessionId": data.sessionId ?? ""
                    ]
                    if let jsonData = try? JSONSerialization.data(
                        withJSONObject: event,
                        options: [.sortedKeys]
                    ) {
                        writeEvent(String(data: jsonData, encoding: .utf8) ?? "{}")
                    }
                }
            case .pausedTimeout:
                var event: [String: Any] = [
                    "type": "pausedTimeout",
                    "canResume": false,
                    "sessionId": data.sessionId ?? ""
                ]
                if let reason = data.pausedData?.reason {
                    event["reason"] = reason
                }
                if let jsonData = try? JSONSerialization.data(
                    withJSONObject: event,
                    options: [.sortedKeys]
                ) {
                    writeEvent(String(data: jsonData, encoding: .utf8) ?? "{}")
                }
            default:
                break
            }
        default:
            break
        }
    }

    func displayCompletion() {
        var result: [String: Any] = [:]
        result["runId"] = runId
        result["task"] = task

        if let data = resultData {
            result["status"] = data.subtype.rawValue
            result["text"] = data.text
            result["numTurns"] = data.numTurns
            result["durationMs"] = data.durationMs
        } else {
            result["status"] = "unknown"
        }

        result["steps"] = steps
        result["errors"] = errors
        result["mode"] = mode

        let jsonData = (try? JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys, .prettyPrinted]
        )) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        write(jsonString)
    }
}
