import Foundation
import OpenAgentSDK

/// Pushes task execution progress and results to Telegram.
///
/// One instance per TG task — `chatId` is injected at init time.
/// Non-TG tasks (HTTP API / CLI) do not create this handler.
///
/// Streaming events (LLMTokenStream, ToolStarted, ToolStreaming, ToolCompleted,
/// AgentCompleted) are delegated to a `TGStreamingController` for edit-based
/// live updates. Non-streaming events (AgentFailed, ReviewResult) still send
/// independent messages directly.
actor TGEventHandler: EventHandler {
    let identifier = "telegram-push"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        LLMTokenStreamEvent.self,
        ToolStartedEvent.self,
        ToolStreamingEvent.self,
        ToolCompletedEvent.self,
        AgentCompletedEvent.self,
        AgentFailedEvent.self,
        ReviewResultEvent.self,
    ]

    let chatId: Int64
    private let sendMessage: @Sendable (String, Int64) async -> Int64?
    private let editMessage: @Sendable (Int64, Int64, String) async -> Bool
    private let sendChatAction: @Sendable (Int64, String) async -> Void
    private let streamingConfig: TGStreamingConfig
    private lazy var streamingController: TGStreamingController = {
        TGStreamingController(
            chatId: chatId,
            sendMessage: sendMessage,
            editMessage: editMessage,
            sendChatAction: sendChatAction,
            config: streamingConfig
        )
    }()

    init(
        chatId: Int64,
        sendMessage: @escaping @Sendable (String, Int64) async -> Int64?,
        editMessage: @escaping @Sendable (Int64, Int64, String) async -> Bool = { _, _, _ in false },
        sendChatAction: @escaping @Sendable (Int64, String) async -> Void = { _, _ in },
        streamingConfig: TGStreamingConfig = .default
    ) {
        self.chatId = chatId
        self.sendMessage = sendMessage
        self.editMessage = editMessage
        self.sendChatAction = sendChatAction
        self.streamingConfig = streamingConfig
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        switch event {
        case let failedEvent as AgentFailedEvent:
            await handleFailed(failedEvent)
        case let reviewEvent as ReviewResultEvent:
            await handleReviewResult(reviewEvent)
        default:
            // All other events go to streaming controller
            await streamingController.handle(event)
        }
    }

    private func handleFailed(_ event: AgentFailedEvent) async {
        let sanitizedError = TGErrorSanitizer.sanitizeForTelegramError(event.error)
        let message = "❌ 任务失败: \(sanitizedError)"
        _ = await sendMessage(message, chatId)
    }

    private func handleReviewResult(_ event: ReviewResultEvent) async {
        guard event.success else {
            _ = await sendMessage("⚠️ 后台审查失败", chatId)
            return
        }
        guard !event.memoryChanges.isEmpty || !event.skillChanges.isEmpty else { return }

        var parts: [String] = []
        if !event.memoryChanges.isEmpty {
            parts.append("新增 \(event.memoryChanges.count) 条记忆")
        }
        if !event.skillChanges.isEmpty {
            parts.append("更新 \(event.skillChanges.count) 个技能")
        }
        let message = "📊 审查完成: \(parts.joined(separator: ", "))"
        _ = await sendMessage(message, chatId)
    }

    /// Returns the section after the second-to-last `[结果]` line,
    /// which corresponds to the current task's outcome in a resumed session.
    /// Falls back to the full text when fewer than 2 `[结果]` markers are found.
    static func extractLastResultSection(from text: String) -> String {
        let marker = "[结果]"
        var markerPositions: [String.Index] = []
        var searchStart = text.startIndex
        while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
            markerPositions.append(range.lowerBound)
            searchStart = range.upperBound
        }

        guard markerPositions.count >= 2 else { return text }

        // Find the end of the line containing the second-to-last marker
        let secondLastPos = markerPositions[markerPositions.count - 2]
        let afterMarker = text[secondLastPos...]
        let lineEnd = afterMarker.firstIndex(of: "\n") ?? text.endIndex

        // Start from the character after the newline
        let start = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        guard start < text.endIndex else { return text }

        return String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
