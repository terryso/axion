import Foundation
import Testing

import AxionCore
@testable import AxionCLI
import OpenAgentSDK
import enum OpenAgentSDK.SDKMessage

// MARK: - Capturing Chat Output

/// Thread-safe stdout/stderr capture pair for ChatOutputFormatter.
/// Self-contained — does not depend on E2ETestHelpers' private LinesBuffer.
final class CapturingChatOutput: @unchecked Sendable {
    private var stdoutLines: [String] = []
    private var stderrLines: [String] = []
    private let lock = NSLock()

    var stdoutWrite: (String) -> Void {
        { [self] text in
            lock.lock()
            stdoutLines.append(text)
            lock.unlock()
        }
    }

    var stderrWrite: (String) -> Void {
        { [self] text in
            lock.lock()
            stderrLines.append(text)
            lock.unlock()
        }
    }

    var allStdout: String {
        lock.lock()
        defer { lock.unlock() }
        return stdoutLines.joined(separator: "")
    }

    var allStderr: String {
        lock.lock()
        defer { lock.unlock() }
        return stderrLines.joined(separator: "")
    }

    func containsStdout(_ substring: String) -> Bool {
        allStdout.contains(substring)
    }

    func containsStderr(_ substring: String) -> Bool {
        allStderr.contains(substring)
    }

    /// Create a ChatOutputFormatter that writes into this capture.
    func makeFormatter(theme: ChatTheme? = nil) -> ChatOutputFormatter {
        ChatOutputFormatter(
            writeStdout: stdoutWrite,
            writeStderr: stderrWrite,
            spinner: SpinnerRenderer(isTTY: false),  // non-TTY → no animation timer
            theme: theme
        )
    }
}

// MARK: - Chat E2E Messages

/// Factory for SDKMessage instances used in interactive mode tests.
/// Extends E2EMessages with system messages (compactBoundary, paused, etc.)
enum ChatE2EMessages {
    static func assistant(_ text: String) -> SDKMessage {
        .assistant(.init(text: text, model: "mock-model", stopReason: "end_turn"))
    }

    static func partial(_ text: String) -> SDKMessage {
        .partialMessage(.init(text: text))
    }

    static func toolUse(_ tool: String, id: String = "tu-1", input: String = "{}") -> SDKMessage {
        .toolUse(.init(toolName: tool, toolUseId: id, input: input))
    }

    static func toolResult(id: String = "tu-1", content: String, isError: Bool = false) -> SDKMessage {
        .toolResult(.init(toolUseId: id, content: content, isError: isError))
    }

    static func successResult(text: String = "Done", turns: Int = 1, durationMs: Int = 500) -> SDKMessage {
        .result(.init(
            subtype: .success,
            text: text,
            usage: nil,
            numTurns: turns,
            durationMs: durationMs
        ))
    }

    static func errorResult(text: String = "Max turns exceeded", turns: Int = 3) -> SDKMessage {
        .result(.init(
            subtype: .errorMaxTurns,
            text: text,
            usage: nil,
            numTurns: turns,
            durationMs: 3000
        ))
    }

    static func cancelledResult() -> SDKMessage {
        .result(.init(
            subtype: .cancelled,
            text: "Cancelled",
            usage: nil,
            numTurns: 1,
            durationMs: 100
        ))
    }

    static func executionErrorResult() -> SDKMessage {
        .result(.init(
            subtype: .errorDuringExecution,
            text: "Error",
            usage: nil,
            numTurns: 1,
            durationMs: 200
        ))
    }

    /// System message with compactBoundary subtype.
    static func compactBoundary(preTokens: Int, postTokens: Int, success: Bool = true) -> SDKMessage {
        .system(.init(
            subtype: .compactBoundary,
            message: "",
            compactMetadata: .init(preTokens: preTokens, postTokens: postTokens),
            compactResult: success ? "success" : "failed"
        ))
    }

    /// System message with paused subtype.
    static func paused(reason: String = "User requested") -> SDKMessage {
        .system(.init(
            subtype: .paused,
            message: reason,
            pausedData: .init(reason: reason)
        ))
    }
}

// MARK: - Real Agent Builder

/// Build a real Chat-mode agent using ~/.axion/config.json.
/// Returns nil if API key is not configured (caller should skip).
func buildRealChatAgent(maxTurns: Int = 3) async throws -> (Agent, AxionCore.AxionConfig)? {
    let config = try await ConfigManager.loadConfig()
    guard let apiKey = config.apiKey, !apiKey.isEmpty else {
        return nil
    }

    let promptDir = PromptBuilder.resolvePromptDirectory()
    let mcpPrefixedToolNames = ToolNames.allToolNames.map { "mcp__axion-helper__\($0)" }

    let systemPrompt = (try? PromptBuilder.load(
        name: "planner-system",
        variables: [
            "tools": PromptBuilder.buildToolListDescription(from: mcpPrefixedToolNames),
            "max_steps": String(maxTurns),
        ],
        fromDirectory: promptDir
    )) ?? ""

    let skillRegistry = SkillRegistry()
    AxionBuiltInSkills.registerAll(into: skillRegistry)
    _ = skillRegistry.registerDiscoveredSkills()

    let skillsPrompt = skillRegistry.formatSkillsForPrompt()
    let fullPrompt = AgentBuilder.buildFullSystemPrompt(
        basePrompt: systemPrompt,
        skillsPrompt: skillsPrompt
    )

    let excludedToolNames: Set<String> = ["ToolSearch", "AskUser"]
    var agentTools: [ToolProtocol] = (getAllBaseTools(tier: .core) + getAllBaseTools(tier: .specialist))
        .filter { !excludedToolNames.contains($0.name) }
    agentTools.append(createSkillTool(registry: skillRegistry))

    let options = AgentOptions(
        apiKey: apiKey,
        model: config.model,
        baseURL: config.baseURL,
        systemPrompt: fullPrompt,
        maxTurns: maxTurns,
        maxTokens: 4096,
        permissionMode: .bypassPermissions,
        tools: agentTools,
        mcpServers: nil,
        skillRegistry: skillRegistry,
        logLevel: .error
    )

    let agent = createAgent(options: options)
    return (agent, config)
}

// MARK: - Streaming Collector

/// Stream an agent and collect all messages + output.
struct StreamResult {
    var toolCalls: [String] = []
    var assistantTexts: [String] = []
    var resultText: String = ""
    var resultSubtype: SDKMessage.ResultData.Subtype?
}

func collectStreamResult(agent: Agent, task: String, handler: ChatOutputFormatter) async -> StreamResult {
    var result = StreamResult()
    let stream = agent.stream(task)
    for await message in stream {
        handler.handle(message)
        switch message {
        case .toolUse(let data):
            result.toolCalls.append(data.toolName)
        case .assistant(let data):
            result.assistantTexts.append(data.text)
        case .result(let data):
            result.resultText = data.text
            result.resultSubtype = data.subtype
        default:
            break
        }
    }
    return result
}
