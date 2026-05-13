import ArgumentParser
import Foundation
import OpenAgentSDK

import AxionCore

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
        let effectiveMaxSteps = maxSteps ?? config.maxSteps

        let options = AgentOptions(
            apiKey: apiKey,
            model: config.model,
            baseURL: config.baseURL,
            systemPrompt: systemPrompt,
            maxTurns: effectiveMaxSteps,
            maxTokens: 4096,
            permissionMode: .bypassPermissions,
            mcpServers: mcpServers,
            memoryStore: memoryStore,
            hookRegistry: hookRegistry,
            logLevel: verbose ? .debug : .info
        )

        // 8. Create Agent
        let agent = createAgent(options: options)

        // 9. Select output handler
        let outputHandler: any SDKMessageOutputHandler = json
            ? SDKJSONOutputHandler()
            : SDKTerminalOutputHandler()

        // 10. Run with cancellation support
        let runId = Self.generateRunId()
        outputHandler.displayRunStart(runId: runId, task: task)

        let tracer = try? TraceRecorder(runId: runId, config: config)
        await tracer?.recordRunStart(runId: runId, task: task, mode: dryrun ? "dryrun" : "standard")

        // Cleanup expired memory entries at run start
        do {
            let cleanupService = MemoryCleanupService()
            _ = try await cleanupService.cleanupExpired(in: memoryStore)
        } catch {
            fputs("[axion] warning: memory cleanup failed: \(error.localizedDescription)\n", stderr)
        }

        var totalSteps = 0
        let startTime = ContinuousClock.now

        // Collect toolUse/toolResult pairs for memory extraction (matched by toolUseId)
        var pendingToolUses: [String: SDKMessage.ToolUseData] = [:]
        var collectedPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = []

        await withTaskCancellationHandler {
            let messageStream = agent.stream(task)
            for await message in messageStream {
                if _Concurrency.Task.isCancelled { break }
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
                        let profileContent = buildProfileContent(profile: profile)
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

    /// Builds the full system prompt with mode-specific instructions appended.
    private func buildFullSystemPrompt(basePrompt: String, dryrun: Bool, verbose: Bool, memoryContext: String? = nil) -> String {
        var prompt = basePrompt

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
    private func buildProfileContent(profile: AppProfile) -> String {
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
            await tracer.record(event: "tool_use", payload: [
                "tool": data.toolName,
                "toolUseId": data.toolUseId
            ])
        case .toolResult(let data):
            await tracer.record(event: "tool_result", payload: [
                "toolUseId": data.toolUseId,
                "isError": data.isError,
                "content": String(data.content.prefix(200))
            ])
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
    private var streamBuffer = ""

    init(output: TerminalOutput = TerminalOutput()) {
        self.output = output
    }

    func displayRunStart(runId: String, task: String) {
        output.displayRunStart(runId: runId, task: task, mode: "standard")
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
            switch data.subtype {
            case .success:
                if !data.text.isEmpty {
                    output.write("[axion] 完成: \(data.text)")
                }
            case .errorMaxTurns:
                output.write("[axion] 达到最大步数限制 (\(data.numTurns) 步)")
            case .errorMaxBudgetUsd:
                output.write("[axion] 预算超限")
            case .cancelled:
                output.write("[axion] 已取消")
            case .errorDuringExecution:
                output.write("[axion] 执行错误")
            case .errorMaxStructuredOutputRetries:
                output.write("[axion] 结构化输出重试超限")
            }

        case .partialMessage(let data):
            streamBuffer += data.text

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
}

/// JSON output handler — accumulates data and produces structured JSON at completion.
final class SDKJSONOutputHandler: SDKMessageOutputHandler {
    private let write: (String) -> Void
    private var runId: String = ""
    private var task: String = ""
    private var steps: [[String: Any]] = []
    private var errors: [[String: String]] = []
    private var resultData: SDKMessage.ResultData?

    init(write: @escaping (String) -> Void = { print($0) }) {
        self.write = write
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

        let jsonData = (try? JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys, .prettyPrinted]
        )) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        write(jsonString)
    }
}
