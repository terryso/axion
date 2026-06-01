import Foundation
import OpenAgentSDK

// MARK: - Types

enum TGStreamSegment {
    case llm
    case tool(name: String)
    case final
}

enum TGStreamingTransport {
    case edit
    case append
    case off
}

struct TGStreamingConfig: Sendable {
    let editInterval: TimeInterval
    let bufferThreshold: Int
    let transport: TGStreamingTransport
    let freshFinalAfter: TimeInterval
    let typingEnabled: Bool
    let typingInterval: TimeInterval

    static let `default` = TGStreamingConfig(
        editInterval: 0.8,
        bufferThreshold: 24,
        transport: .edit,
        freshFinalAfter: 60,
        typingEnabled: true,
        typingInterval: 4.0
    )
}

// MARK: - TGStreamingController

actor TGStreamingController {
    private static let previewPlaceholder = "⏳ 处理中…"

    // MARK: - State

    private let chatId: Int64
    private var previewMessageId: Int64?
    private var previewCreatedAt: Date?
    private var bufferedText: String = ""
    private var renderedPreview: String = ""
    private var currentSegment: TGStreamSegment = .llm
    private var lastEditAt: Date = .distantPast
    private var retryAfterUntil: Date = .distantPast
    private var transport: TGStreamingTransport
    private var toolPreviewMap: [String: String] = [:]
    private var finalized = false
    private var completionReceived = false
    private var completionEventResultText: String?
    private var consecutive429Count = 0
    private var segmentParts: [String] = []
    private var typingTask: _Concurrency.Task<Void, Never>?
    private var hasSentStandaloneStepMessage = false

    private let config: TGStreamingConfig
    private let originalTask: String?
    private let deferFinalDelivery: Bool
    private let sendMessage: @Sendable (String, Int64) async -> Int64?
    private let editMessage: @Sendable (Int64, Int64, String) async -> Bool
    private let sendChatAction: @Sendable (Int64, String) async -> Void

    // MARK: - Tool Preview Helpers

    private static func toolEmoji(_ toolName: String) -> String {
        let lower = toolName.lowercased()
        if lower.contains("search") || lower.contains("websearch") { return "🔍" }
        if lower.contains("bash") || lower.contains("terminal") || lower.contains("shell") { return "💻" }
        if lower.contains("read") { return "📖" }
        if lower.contains("write") { return "✍️" }
        if lower.contains("reader") || lower.contains("fetch") { return "🌐" }
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
        if lower.contains("read") || lower.contains("write") || lower.contains("file") {
            if let path = json["file_path"] as? String { return path }
            if let path = json["path"] as? String { return path }
        }
        if lower.contains("reader") || lower.contains("url") || lower.contains("fetch") {
            if let url = json["url"] as? String { return url }
        }
        if lower.contains("vision") || lower.contains("image") || lower.contains("analyze") {
            if let prompt = json["prompt"] as? String { return String(prompt.prefix(40)) }
        }

        for (_, value) in json.sorted(by: { $0.key < $1.key }) {
            if let str = value as? String, !str.isEmpty {
                return String(str.prefix(40))
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
        if lower.contains("read") || lower.contains("write") || lower.contains("file") {
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
        self.editMessage = editMessage
        self.sendChatAction = sendChatAction
        self.config = config
        self.transport = config.transport

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
        case let e as LLMTokenStreamEvent:
            await handleLLMTokenStream(e)
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

    // MARK: - LLM Token Stream

    private func handleLLMTokenStream(_ event: LLMTokenStreamEvent) async {
        guard !finalized else { return }

        let wasFirstChunk = previewCreatedAt == nil

        // On first chunk, create preview bubble
        if wasFirstChunk {
            stopTypingTimer()
            let previewText = Self.previewPlaceholder
            let msgId = await sendMessage(previewText, chatId)
            if let msgId { previewMessageId = msgId }
            previewCreatedAt = Date()
            lastEditAt = Date()
        }

        bufferedText += event.chunk
        segmentParts.append(event.chunk)

        // Don't flush on the same call as the first chunk — we just sent the preview
        guard !wasFirstChunk else { return }

        let shouldFlush: Bool
        if bufferedText.count >= config.bufferThreshold {
            shouldFlush = true
        } else {
            let now = Date()
            shouldFlush = now.timeIntervalSince(lastEditAt) >= config.editInterval
                && now >= retryAfterUntil
        }

        if shouldFlush {
            await flushBuffer()
        }
    }

    // MARK: - Tool Started

    private func handleToolStarted(_ event: ToolStartedEvent) async {
        guard !finalized else { return }

        if !bufferedText.isEmpty {
            await flushBuffer()
        }

        if let preview = Self.extractToolPreview(toolName: event.toolName, input: event.input) {
            toolPreviewMap[event.toolUseId] = preview
        }

        stopTypingTimer()
        hasSentStandaloneStepMessage = true
        _ = await sendMessage(Self.formatToolStepMessage(toolName: event.toolName, input: event.input), chatId)
    }

    // MARK: - Tool Streaming

    private func handleToolStreaming(_ event: ToolStreamingEvent) {
        // Suppress raw MCP output — tool progress shown via started/completed markers
    }

    // MARK: - Tool Completed

    private func handleToolCompleted(_ event: ToolCompletedEvent) async {
        guard !finalized else { return }
        toolPreviewMap.removeValue(forKey: event.toolUseId)
    }

    // MARK: - Agent Completed

    private func handleAgentCompleted(_ event: AgentCompletedEvent) async {
        guard !finalized, !completionReceived else { return }

        stopTypingTimer()

        // Flush any remaining buffer
        if !bufferedText.isEmpty {
            await flushBuffer()
        }

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

        if !bufferedText.isEmpty {
            await flushBuffer()
        }

        await sendFinal(using: authoritativeResultText ?? completionEventResultText)
    }

    private func sendFinal(using resultText: String?) async {
        finalized = true

        let finalText: String
        if let resultText, !resultText.isEmpty {
            let cleaned = TGEventHandler.cleanResultText(from: resultText)
            let answer = cleaned.isEmpty ? "✅ 已完成" : cleaned
            finalText = Self.formatQuotedFinalAnswer(task: originalTask, answer: answer)
        } else {
            finalText = Self.formatQuotedFinalAnswer(task: originalTask, answer: "✅ 已完成")
        }

        // Check freshFinalAfter — if preview is stale, send new message
        let shouldSendFresh: Bool
        if let createdAt = previewCreatedAt {
            shouldSendFresh = Date().timeIntervalSince(createdAt) > config.freshFinalAfter
        } else {
            shouldSendFresh = true
        }

        if shouldSendFresh || hasSentStandaloneStepMessage || transport != .edit {
            // Adapter handles formatting + splitting
            _ = await sendMessage(finalText, chatId)
            return
        }

        // Try editing the existing preview with final content
        if let msgId = previewMessageId {
            let success = await editMessage(chatId, msgId, finalText)
            if success {
                return
            }
            // Edit failed — fall through to send new message
        }

        // Fallback: send as new message(s)
        _ = await sendMessage(finalText, chatId)
    }

    // MARK: - Cancel

    func cancel() {
        stopTypingTimer()
        finalized = true
        bufferedText = ""
        segmentParts = []
    }

    // MARK: - Set Preview Message ID

    func setPreviewMessageId(_ id: Int64) {
        previewMessageId = id
    }

    // MARK: - Flush Buffer

    private func flushBuffer() async {
        guard !bufferedText.isEmpty else { return }
        renderedPreview += bufferedText
        let content = bufferedText
        bufferedText = ""
        segmentParts = []

        await performEditWithContent(content)
    }

    private func performEdit() async {
        guard !renderedPreview.isEmpty else { return }
        await performEditWithContent(renderedPreview)
    }

    private func performEditWithContent(_ content: String) async {
        let now = Date()
        guard now >= retryAfterUntil else { return }
        guard now.timeIntervalSince(lastEditAt) >= config.editInterval else { return }

        // Build the full preview text
        let displayText: String
        if previewMessageId == nil {
            displayText = "\(Self.previewPlaceholder)\n\(content)"
        } else {
            displayText = content
        }

        if transport == .edit, let msgId = previewMessageId {
            let success = await editMessage(chatId, msgId, displayText)
            if success {
                consecutive429Count = 0
                lastEditAt = Date()
                reFireTyping()
                return
            }

            handlePermanentFailure()
        }

        // Append mode: send as new message
        let msgId = await sendMessage(displayText, chatId)
        if previewMessageId == nil { previewMessageId = msgId }
        reFireTyping()
        if transport == .append {
            lastEditAt = Date()
        }
    }

    // MARK: - Typing Timer

    private func stopTypingTimer() {
        typingTask?.cancel()
        typingTask = nil
    }

    private func reFireTyping() {
        guard config.typingEnabled else { return }
        let action = sendChatAction
        let id = chatId
        _Concurrency.Task { await action(id, "typing") }
    }

    /// Handle a 429 error from editMessage.
    func handle429(retryAfter: TimeInterval?) {
        consecutive429Count += 1
        if let retryAfter {
            retryAfterUntil = Date().addingTimeInterval(retryAfter)
        } else {
            retryAfterUntil = Date().addingTimeInterval(1.0)
        }

        if consecutive429Count >= 3 {
            transport = .append
        }
    }

    /// Handle permanent edit failure — degrade to append-only.
    func handlePermanentFailure() {
        transport = .append
    }
}
