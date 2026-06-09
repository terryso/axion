import OpenAgentSDK

extension TelegramAdapter {

    // MARK: - Callback Query Processing

    func processCallback(_ query: TGCallbackQuery) async {
        let userId = query.from.id
        guard isAuthorized(userId: userId) else {
            _ = try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "未授权")
            return
        }

        guard let rawData = query.data,
              let callbackData = TGCallbackData(rawValue: rawData),
              let store = sessionStore
        else {
            _ = try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "无效操作")
            return
        }

        let pendingId = callbackData.pendingId

        switch callbackData.action {
        case .approve, .confirm:
            let context = callbackData.action == .approve ? "approved" : "confirmed"
            await resumeAndConfirm(query: query, store: store, pendingId: pendingId, context: context, replyText: "已批准", editText: "✅ 已批准")

        case .deny, .cancel:
            let context = callbackData.action == .deny ? "denied" : "cancelled"
            await resumeAndConfirm(query: query, store: store, pendingId: pendingId, context: context, replyText: "已拒绝", editText: "❌ 已拒绝")

        case .skillsPage:
            guard let provider = skillsProvider else {
                _ = try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "不可用")
                return
            }
            let page = Int(callbackData.detail) ?? 0
            let skills = provider().sorted { $0.name < $1.name }
            let pageSize = 20
            let totalPages = max(1, (skills.count + pageSize - 1) / pageSize)
            let safePage = max(0, min(page, totalPages - 1))

            let keyboard = Self.buildSkillsKeyboard(skills: skills, page: safePage, pageSize: pageSize)
            let text = "📋 技能列表 (\(safePage + 1)/\(totalPages))"

            if let messageId = query.message?.messageId, let chatId = query.message?.chat.id {
                let (formatted, mode) = TGMessageFormatter.format(text)
                _ = try? await apiClient.editMessageText(chatId: chatId, messageId: messageId, text: formatted, parseMode: mode, replyMarkup: keyboard)
            }
            _ = try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: nil)

        case .triggerSkill:
            let skillName = callbackData.detail
            guard !skillName.isEmpty else {
                _ = try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "无效技能")
                return
            }
            _ = try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: nil)

            if let messageId = query.message?.messageId, let chatId = query.message?.chat.id {
                _ = await editMessage(chatId: chatId, messageId: messageId, text: "▶ /\(skillName)")
            }

            let taskText = "/\(skillName)"
            log("[axion] Telegram skill triggered: \"\(taskText)\"")
            if let queue = taskQueue, let chatId = query.message?.chat.id {
                await queue.enqueue(task: taskText, chatId: chatId, userId: query.from.id)
            }

        case .skip:
            await resumeAndConfirm(query: query, store: store, pendingId: pendingId, context: "skip", replyText: "已跳过", editText: "⏭️ 已跳过")

        case .respond, .clarify:
            // Switch to text capture mode (for respond) or resolve clarify option
            let session = await store.get(pendingId: pendingId)
            if let session, !session.isExpired {
                if callbackData.action == .clarify {
                    let optionIndex = Int(callbackData.detail) ?? -1
                    let options = session.clarifyOptions
                    let selectedText: String
                    if optionIndex >= 0 && optionIndex < options.count {
                        selectedText = options[optionIndex]
                    } else {
                        selectedText = callbackData.detail
                    }
                    await resumeAndConfirm(query: query, store: store, pendingId: pendingId, context: selectedText, replyText: "已选择: \(selectedText)", editText: "✅ 已选择: \(selectedText)")
                } else {
                    // respond → text capture mode
                    _ = await store.remove(pendingId: pendingId)
                    await store.register(
                        pendingId: pendingId,
                        chatId: session.chatId,
                        messageId: session.messageId,
                        mode: .textCapture,
                        allowedUserId: session.allowedUserId,
                        onResume: { _ in }
                    )
                    try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "请输入您的回复")
                    if let messageId = query.message?.messageId, let chatId = query.message?.chat.id {
                        _ = await editMessage(chatId: chatId, messageId: messageId, text: "⌨️ 等待文本输入...")
                    }
                }
            } else {
                try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "已过期")
            }
        }
    }

    // MARK: - Shared Resume Helper

    /// Shared pattern: resume a pending session, acknowledge the callback, forward to queue, and edit the message.
    private func resumeAndConfirm(
        query: TGCallbackQuery,
        store: TGInteractiveSessionStore,
        pendingId: String,
        context: String,
        replyText: String,
        editText: String
    ) async {
        let resumed = try? await store.resume(pendingId: pendingId, response: context)
        if resumed == true {
            try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: replyText)
            if let queue = taskQueue {
                _ = await queue.resumeInteraction(pendingId: pendingId, context: context)
            }
            if let messageId = query.message?.messageId, let chatId = query.message?.chat.id {
                _ = await editMessage(chatId: chatId, messageId: messageId, text: editText)
            }
        } else {
            try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "已过期")
        }
    }
}
