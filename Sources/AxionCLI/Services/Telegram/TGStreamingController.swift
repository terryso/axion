import Foundation
import OpenAgentSDK

// MARK: - Types

struct TGStreamingConfig: Sendable {
    let typingEnabled: Bool
    let typingInterval: TimeInterval

    static let `default` = TGStreamingConfig(
        typingEnabled: true,
        typingInterval: 4.0
    )
}

// MARK: - TGStreamingController

actor TGStreamingController {

    // MARK: - State

    private let chatId: Int64
    private var finalized = false
    private var completionReceived = false
    private var completionEventResultText: String?
    private var typingTask: _Concurrency.Task<Void, Never>?

    private let config: TGStreamingConfig
    private let originalTask: String?
    private let deferFinalDelivery: Bool
    private let sendMessage: @Sendable (String, Int64) async -> Int64?
    private let sendChatAction: @Sendable (Int64, String) async -> Void

    // MARK: - Tool Preview Helpers

    private static func toolEmoji(_ toolName: String) -> String {
        let lower = toolName.lowercased()
        if lower.contains("search") || lower.contains("websearch") { return "🔍" }
        if lower.contains("bash") || lower.contains("terminal") || lower.contains("shell") { return "💻" }
        if lower.contains("reader") || lower.contains("fetch") { return "🌐" }
        if lower.contains("read") { return "📖" }
        if lower.contains("write") { return "✍️" }
        if lower.contains("vision") || lower.contains("image") { return "👁️" }
        if lower.contains("edit") { return "📝" }
        if lower.contains("screenshot") || lower.contains("screen") { return "📸" }
        return "⚙️"
    }

    private static func extractToolPreview(toolName: String, input: String?) -> String? {
        guard let input, !input.isEmpty else { return nil }

        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(input.prefix(40))
        }

        let lower = toolName.lowercased()

        if lower.contains("search") || lower.contains("websearch") {
            if let query = json["query"] as? String { return query }
            if let q = json["q"] as? String { return q }
        }
        if lower.contains("bash") || lower.contains("terminal") || lower.contains("shell") {
            if let cmd = json["command"] as? String { return cmd }
        }
        if lower.contains("read") || lower.contains("write") || lower.contains("file")
            || lower.contains("edit") || lower.contains("glob") || lower.contains("grep") {
            if let path = json["file_path"] as? String { return path }
            if let path = json["path"] as? String { return path }
            if let pattern = json["pattern"] as? String, let path = json["path"] as? String {
                return "\(path) — \(pattern)"
            }
        }
        if lower.contains("reader") || lower.contains("url") || lower.contains("fetch") {
            if let url = json["url"] as? String { return url }
        }
        if lower.contains("vision") || lower.contains("image") || lower.contains("analyze") {
            if let prompt = json["prompt"] as? String { return String(prompt.prefix(40)) }
        }

        for (_, value) in json.sorted(by: { $0.key < $1.key }) {
            if let str = value as? String, !str.isEmpty {
                return String(str.prefix(80))
            }
        }

        return nil
    }

    private static func formatToolArgument(toolName: String, input: String?) -> String? {
        guard let preview = extractToolPreview(toolName: toolName, input: input)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !preview.isEmpty else {
            return nil
        }

        let lower = toolName.lowercased()
        if lower.contains("bash") || lower.contains("terminal") || lower.contains("shell") {
            return "`\(preview)`"
        }
        if lower.contains("search") || lower.contains("websearch") {
            return "query: \(preview)"
        }
        if lower.contains("reader") || lower.contains("fetch") || lower.contains("url") {
            return "url: \(preview)"
        }
        if lower.contains("read") || lower.contains("write") || lower.contains("file")
            || lower.contains("edit") || lower.contains("glob") || lower.contains("grep") {
            return "path: \(preview)"
        }
        return preview
    }

    private static func formatToolStepMessage(toolName: String, input: String?) -> String {
        let emoji = toolEmoji(toolName)
        if let argument = formatToolArgument(toolName: toolName, input: input) {
            return "\(emoji) \(toolName): \(argument)"
        }
        return "\(emoji) \(toolName)"
    }

    private static func normalizeQuotedTask(_ task: String?) -> String? {
        guard let task else { return nil }

        let filtered = task
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("[附件图片:")
                    && !line.hasPrefix("[用户发送了一张图片")
            }

        guard !filtered.isEmpty else { return nil }

        let joined = filtered.joined(separator: "\n")
        return String(joined.prefix(280))
    }

    private static func formatQuotedFinalAnswer(task: String?, answer: String) -> String {
        guard let normalizedTask = normalizeQuotedTask(task) else {
            return answer
        }

        let quotedTask = normalizedTask
            .components(separatedBy: "\n")
            .map { "> \($0)" }
            .joined(separator: "\n")

        return "\(quotedTask)\n\n\(answer)"
    }

    // MARK: - Init

    init(
        chatId: Int64,
        originalTask: String? = nil,
        deferFinalDelivery: Bool = false,
        sendMessage: @escaping @Sendable (String, Int64) async -> Int64?,
        editMessage: @escaping @Sendable (Int64, Int64, String) async -> Bool,
        sendChatAction: @escaping @Sendable (Int64, String) async -> Void = { _, _ in },
        config: TGStreamingConfig = .default
    ) {
        self.chatId = chatId
        self.originalTask = originalTask
        self.deferFinalDelivery = deferFinalDelivery
        self.sendMessage = sendMessage
        self.sendChatAction = sendChatAction
        self.config = config

        if config.typingEnabled {
            self.typingTask = _Concurrency.Task { [sendChatAction, chatId, interval = config.typingInterval] in
                while !_Concurrency.Task.isCancelled {
                    await sendChatAction(chatId, "typing")
                    try? await _Concurrency.Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            }
        }
    }

    // MARK: - Event Dispatch

    func handle(_ event: any AgentEvent) async {
        switch event {
        case let e as ToolStartedEvent:
            await handleToolStarted(e)
        case let e as ToolStreamingEvent:
            handleToolStreaming(e)
        case let e as ToolCompletedEvent:
            await handleToolCompleted(e)
        case let e as AgentCompletedEvent:
            await handleAgentCompleted(e)
        default:
            break
        }
    }

    // MARK: - LLM Token Stream (typing-only, no preview)

    private func handleLLMTokenStream(_ event: LLMTokenStreamEvent) {
        // Typing indicator is already running from init — nothing to do.
    }

    // MARK: - Tool Started

    private func handleToolStarted(_ event: ToolStartedEvent) async {
        guard !finalized else { return }

        _ = await sendMessage(Self.formatToolStepMessage(toolName: event.toolName, input: event.input), chatId)
    }

    // MARK: - Tool Streaming

    private func handleToolStreaming(_ event: ToolStreamingEvent) {
        // Suppress raw MCP output — tool progress shown via started/completed markers
    }

    // MARK: - Tool Completed

    private func handleToolCompleted(_ event: ToolCompletedEvent) async {
        guard !finalized else { return }

        if event.isError {
            let msg = "❌ \(event.toolName) 失败" + (event.output.map { "：\n" + Self.summarizeOutput($0, maxLines: 3) } ?? "")
            _ = await sendMessage(msg, chatId)
            return
        }

        guard let output = event.output, !output.isEmpty else { return }

        let summary = Self.summarizeOutput(output, maxLines: 4)
        guard !summary.isEmpty else { return }

        let emoji = Self.toolEmoji(event.toolName)
        let header = "\(emoji) \(event.toolName) 结果："
        _ = await sendMessage("\(header)\n\(summary)", chatId)
    }

    /// Summarize tool output for TG display: basic cleanup, truncate to maxLines.
    private static func summarizeOutput(_ output: String, maxLines: Int = 4) -> String {
        // Tool output is raw data, not agent prose — do NOT apply stripMCPRawIO
        // (which would strip everything inside MCP I/O blocks).
        // Just do basic whitespace cleanup.
        var cleaned = output
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        let lines = cleaned.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let truncated = lines.prefix(maxLines)
        let suffix = lines.count > maxLines ? "\n… (\(lines.count - maxLines) 行省略)" : ""
        return truncated.joined(separator: "\n") + suffix
    }

    // MARK: - Agent Completed

    private func handleAgentCompleted(_ event: AgentCompletedEvent) async {
        guard !finalized, !completionReceived else { return }

        stopTypingTimer()

        completionReceived = true
        completionEventResultText = event.resultText

        if deferFinalDelivery {
            return
        }

        await sendFinal(using: event.resultText)
    }

    func finishDeferredRun(authoritativeResultText: String?) async {
        guard deferFinalDelivery, !finalized else { return }
        stopTypingTimer()

        await sendFinal(using: authoritativeResultText ?? completionEventResultText)
    }

    private func sendFinal(using resultText: String?) async {
        finalized = true

        let finalText: String
        if let resultText, !resultText.isEmpty {
            let stripped = TGEventHandler.stripMCPRawIO(from: resultText)
            let answer = stripped.isEmpty ? "✅ 已完成" : stripped
            finalText = Self.formatQuotedFinalAnswer(task: originalTask, answer: answer)
        } else {
            finalText = Self.formatQuotedFinalAnswer(task: originalTask, answer: "✅ 已完成")
        }

        _ = await sendMessage(finalText, chatId)
    }

    // MARK: - Cancel

    func cancel() {
        stopTypingTimer()
        finalized = true
    }

    // MARK: - Typing Timer

    private func stopTypingTimer() {
        typingTask?.cancel()
        typingTask = nil
    }
}
