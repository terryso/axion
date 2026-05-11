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

        // 4. Load system prompt from planner-system.md
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
        let systemPrompt = buildFullSystemPrompt(
            basePrompt: baseSystemPrompt,
            dryrun: dryrun,
            verbose: verbose
        )

        // 5. Configure MCP server for Helper
        let mcpServers: [String: McpServerConfig] = [
            "axion-helper": .stdio(McpStdioConfig(command: helperPath))
        ]

        // 6. Build safety hook registry
        let hookRegistry = await buildSafetyHookRegistry(
            sharedSeatMode: config.sharedSeatMode && !allowForeground
        )

        // 7. Build AgentOptions
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

        var totalSteps = 0
        let startTime = ContinuousClock.now

        await withTaskCancellationHandler {
            let messageStream = agent.stream(task)
            for await message in messageStream {
                if _Concurrency.Task.isCancelled { break }
                if case .toolUse = message { totalSteps += 1 }
                outputHandler.handleMessage(message)
                await recordToTrace(message: message, tracer: tracer)
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
    private func buildFullSystemPrompt(basePrompt: String, dryrun: Bool, verbose: Bool) -> String {
        var prompt = basePrompt

        if dryrun {
            prompt += "\n\nIMPORTANT: You are in DRYRUN mode. Generate a plan but do NOT execute any tools. Return a plan JSON with status 'done' and the steps you would execute."
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
