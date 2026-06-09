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
        AgentPausedEvent.self,
    ]

    let chatId: Int64
    private let allowedUserId: Int64
    private let sendMessage: @Sendable (String, Int64) async -> Int64?
    private let editMessage: @Sendable (Int64, Int64, String) async -> Bool
    private let sendChatAction: @Sendable (Int64, String) async -> Void
    private let originalTask: String?
    private let deferFinalDelivery: Bool
    private let sendMessageWithMarkup: @Sendable (Int64, String, TGInlineKeyboardMarkup?) async -> Int64?
    private let streamingConfig: TGStreamingConfig
    private let sessionStore: TGInteractiveSessionStore?
    private let registerResumeHandle: (@Sendable (String, @Sendable @escaping (String) async -> Void) -> Void)?
    private let streamingController: TGStreamingController

    init(
        chatId: Int64,
        allowedUserId: Int64 = 0,
        sendMessage: @escaping @Sendable (String, Int64) async -> Int64?,
        editMessage: @escaping @Sendable (Int64, Int64, String) async -> Bool = { _, _, _ in false },
        sendChatAction: @escaping @Sendable (Int64, String) async -> Void = { _, _ in },
        originalTask: String? = nil,
        deferFinalDelivery: Bool = false,
        streamingConfig: TGStreamingConfig = .default,
        sessionStore: TGInteractiveSessionStore? = nil,
        registerResumeHandle: (@Sendable (String, @Sendable @escaping (String) async -> Void) -> Void)? = nil,
        sendMessageWithMarkup: @escaping @Sendable (Int64, String, TGInlineKeyboardMarkup?) async -> Int64? = { _, _, _ in nil }
    ) {
        self.chatId = chatId
        self.allowedUserId = allowedUserId
        self.sendMessage = sendMessage
        self.editMessage = editMessage
        self.sendChatAction = sendChatAction
        self.originalTask = originalTask
        self.deferFinalDelivery = deferFinalDelivery
        self.streamingConfig = streamingConfig
        self.sessionStore = sessionStore
        self.registerResumeHandle = registerResumeHandle
        self.sendMessageWithMarkup = sendMessageWithMarkup
        self.streamingController = TGStreamingController(
            chatId: chatId,
            originalTask: originalTask,
            deferFinalDelivery: deferFinalDelivery,
            sendMessage: sendMessage,
            editMessage: editMessage,
            sendChatAction: sendChatAction,
            config: streamingConfig
        )
    }

    func finishRun(responseText: String?) async {
        await streamingController.finishDeferredRun(authoritativeResultText: responseText)
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        switch event {
        case let failedEvent as AgentFailedEvent:
            await handleFailed(failedEvent)
        case let reviewEvent as ReviewResultEvent:
            await handleReviewResult(reviewEvent)
        case let pausedEvent as AgentPausedEvent:
            await handlePaused(pausedEvent)
        default:
            // All other events go to streaming controller
            await streamingController.handle(event)
        }
    }

    private func handlePaused(_ event: AgentPausedEvent) async {
        guard let store = sessionStore else { return }

        let pendingId = event.pendingId
        let mode: TGInteractionMode = mapPauseReasonToMode(event.reason)

        let keyboard = await store.buildKeyboard(for: mode, pendingId: pendingId)
        let text = "⏸️ Agent 已暂停\n原因: \(event.reason)"

        let msgId = await sendWithReplyMarkup(text: text, replyMarkup: keyboard)
        guard let messageId = msgId else { return }

        await store.register(
            pendingId: pendingId,
            chatId: chatId,
            messageId: messageId,
            mode: mode,
            allowedUserId: allowedUserId,
            onResume: { response in
                // The actual agent.resume() is called via TaskSerialQueue.resumeInteraction.
                // This closure updates the TG message after resume completes.
            }
        )
    }

    private func sendWithReplyMarkup(text: String, replyMarkup: TGInlineKeyboardMarkup) async -> Int64? {
        return await sendMessageWithMarkup(chatId, text, replyMarkup)
    }

    private func mapPauseReasonToMode(_ reason: String) -> TGInteractionMode {
        let lower = reason.lowercased()
        if lower.contains("approve") || lower.contains("approval") || lower.contains("danger") {
            return .approval
        } else if lower.contains("confirm") {
            return .confirm
        } else if lower.contains("clarif") {
            return .clarify
        } else {
            return .approval
        }
    }

    private func handleFailed(_ event: AgentFailedEvent) async {
        await streamingController.cancel()

        let lower = event.error.lowercased()
        if lower.contains("cancelled") || lower.contains("canceled") || lower.contains("cancellation") {
            _ = await sendMessage("⏹ 任务已停止", chatId)
            return
        }

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

}
