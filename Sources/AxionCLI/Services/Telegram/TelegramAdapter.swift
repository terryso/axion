import Foundation
import OpenAgentSDK

actor TelegramAdapter {
    private struct TGFormattedPayload {
        let formattedText: String
        let parseMode: TGParseMode
        let chunks: [String]
    }

    private let apiClient: any TGAPIClientProtocol
    private let allowedUsers: Set<String>
    private let commandRouter: TGCommandRouter?
    private var taskQueue: (any TaskSerialQueueProtocol)?
    private let skillsProvider: (@Sendable () -> [Skill])?
    private var lastUpdateId: Int64 = 0
    private var isRunning = false
    private let log: @Sendable (String) -> Void
    private let sessionStore: TGInteractiveSessionStore?

    nonisolated(unsafe) private(set) var statusValue: String = "disabled"

    init(apiClient: any TGAPIClientProtocol, allowedUsers: Set<String>, taskQueue: (any TaskSerialQueueProtocol)? = nil, commandRouter: TGCommandRouter? = nil, sessionStore: TGInteractiveSessionStore? = nil, skillsProvider: (@Sendable () -> [Skill])? = nil, log: @Sendable @escaping (String) -> Void = { fputs($0 + "\n", stderr) }) {
        self.apiClient = apiClient
        self.allowedUsers = allowedUsers
        self.taskQueue = taskQueue
        self.commandRouter = commandRouter
        self.sessionStore = sessionStore
        self.skillsProvider = skillsProvider
        self.log = log
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        statusValue = "connected"
        log("[axion] Telegram adapter connected")
        await pollLoop()
    }

    func stop() {
        isRunning = false
        statusValue = "disabled"
    }

    func statusInfo() -> String? {
        return statusValue
    }

    // MARK: - Direct Update Processing

    func processUpdates(_ updates: [TGUpdate]) async {
        for update in updates {
            lastUpdateId = update.updateId
            if let callbackQuery = update.callbackQuery {
                await processCallback(callbackQuery)
            } else if let message = update.message {
                await processMessage(message)
            }
        }
    }

    // MARK: - Poll Loop

    private func pollLoop() async {
        var consecutiveErrors = 0
        while isRunning {
            do {
                let updates = try await apiClient.getUpdates(offset: lastUpdateId + 1, timeout: 30)
                statusValue = "connected"
                consecutiveErrors = 0
                for update in updates {
                    lastUpdateId = update.updateId
                    if let callbackQuery = update.callbackQuery {
                        await processCallback(callbackQuery)
                    } else if let message = update.message {
                        await processMessage(message)
                    }
                }
            } catch {
                statusValue = "error:\(error.localizedDescription)"
                log("[axion] Telegram getUpdates failed: \(error.localizedDescription)")
                consecutiveErrors += 1
                let delay = min(5.0 * Double(consecutiveErrors), 30.0)
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    // MARK: - Message Processing

    private func processMessage(_ message: TGMessage) async {
        guard let userId = message.from?.id else { return }
        guard isAuthorized(userId: userId) else { return }

        // Text capture mode: intercept text for pending clarify sessions
        if let text = message.text, !text.isEmpty, let store = sessionStore {
            if let session = await store.session(for: message.chat.id), session.mode == .textCapture {
                let result = try? await store.resume(pendingId: session.pendingId, response: text)
                if result == true {
                    // Also resume the agent via TaskSerialQueue
                    if let queue = taskQueue {
                        _ = await queue.resumeInteraction(pendingId: session.pendingId, context: text)
                    }
                    return
                }
            }
        }

        // Handle photo messages
        if let photo = message.photo, !photo.isEmpty {
            await processPhoto(photo, caption: message.text, chatId: message.chat.id, userId: userId)
            return
        }

        guard let text = message.text, !text.isEmpty else { return }

        if let result = await commandRouter?.handle(text, chatId: message.chat.id) {
            if let markup = result.markup {
                _ = await sendWithMarkup(result.text, to: message.chat.id, replyMarkup: markup)
            } else {
                await sendReply(result.text, to: message.chat.id)
            }
            return
        }

        log("[axion] Telegram task submitted: \"\(text.prefix(50))\"")

        if let queue = taskQueue {
            await queue.enqueue(task: text, chatId: message.chat.id, userId: userId)
        } else {
            await sendReply("任务已收到", to: message.chat.id)
        }
    }

    private func processPhoto(_ sizes: [TGPhotoSize], caption: String?, chatId: Int64, userId: Int64) async {
        let largest = sizes.max(by: { (a, b) in (a.fileSize ?? 0) < (b.fileSize ?? 0) }) ?? sizes.last!
        var tmpPath: String?

        do {
            let file = try await apiClient.getFile(fileId: largest.fileId)
            guard let filePath = file.filePath else {
                await sendReply("图片下载失败，请重试", to: chatId)
                return
            }
            let data = try await apiClient.downloadFile(filePath: filePath)

            let ext = filePath.hasSuffix(".jpg") || filePath.hasSuffix(".jpeg") ? "jpg" : "png"
            let tmpFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("tg_\(largest.fileId.suffix(8)).\(ext)")
            try data.write(to: tmpFile)
            tmpPath = tmpFile.path

            let taskText: String
            if let caption, !caption.isEmpty {
                taskText = "\(caption)\n\n[附件图片: \(tmpFile.path)]"
            } else {
                taskText = "[用户发送了一张图片，保存在 \(tmpFile.path)]"
            }

            log("[axion] Telegram photo task submitted: \"\(taskText.prefix(50))\"")

            if let queue = taskQueue {
                await queue.enqueue(task: taskText, chatId: chatId, userId: userId)
            } else {
                await sendReply("图片已收到", to: chatId)
            }
        } catch {
            if let path = tmpPath {
                try? FileManager.default.removeItem(atPath: path)
            }
            log("[axion] Telegram photo download failed: \(error.localizedDescription)")
            await sendReply("图片下载失败，请重试", to: chatId)
        }
    }

    // MARK: - Callback Query Processing

    private func processCallback(_ query: TGCallbackQuery) async {
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
            let resumed = try? await store.resume(pendingId: pendingId, response: context)
            if resumed == true {
                try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "已批准")
                if let queue = taskQueue {
                    _ = await queue.resumeInteraction(pendingId: pendingId, context: context)
                }
                if let messageId = query.message?.messageId, let chatId = query.message?.chat.id {
                    _ = await editMessage(chatId: chatId, messageId: messageId, text: "✅ 已批准")
                }
            } else {
                try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "已过期")
            }

        case .deny, .cancel:
            let context = callbackData.action == .deny ? "denied" : "cancelled"
            let resumed = try? await store.resume(pendingId: pendingId, response: context)
            if resumed == true {
                try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "已拒绝")
                if let queue = taskQueue {
                    _ = await queue.resumeInteraction(pendingId: pendingId, context: context)
                }
                if let messageId = query.message?.messageId, let chatId = query.message?.chat.id {
                    _ = await editMessage(chatId: chatId, messageId: messageId, text: "❌ 已拒绝")
                }
            } else {
                try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "已过期")
            }

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
            let resumed = try? await store.resume(pendingId: pendingId, response: "skip")
            if resumed == true {
                try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "已跳过")
                if let queue = taskQueue {
                    _ = await queue.resumeInteraction(pendingId: pendingId, context: "skip")
                }
                if let messageId = query.message?.messageId, let chatId = query.message?.chat.id {
                    _ = await editMessage(chatId: chatId, messageId: messageId, text: "⏭️ 已跳过")
                }
            } else {
                try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "已过期")
            }

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
                    let resumed = try? await store.resume(pendingId: pendingId, response: selectedText)
                    if resumed == true {
                        try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "已选择: \(selectedText)")
                        if let queue = taskQueue {
                            _ = await queue.resumeInteraction(pendingId: pendingId, context: selectedText)
                        }
                        if let messageId = query.message?.messageId, let chatId = query.message?.chat.id {
                            _ = await editMessage(chatId: chatId, messageId: messageId, text: "✅ 已选择: \(selectedText)")
                        }
                    } else {
                        try? await apiClient.answerCallbackQuery(callbackQueryId: query.id, text: "已过期")
                    }
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

    func setTaskQueue(_ queue: any TaskSerialQueueProtocol) {
        self.taskQueue = queue
    }

    func sendReply(_ text: String, to chatId: Int64) async {
        let chunks = splitMessage(text)
        for chunk in chunks {
            do {
                _ = try await apiClient.sendMessage(chatId: chatId, text: chunk)
            } catch {
                log("[axion] Telegram sendMessage failed: \(error.localizedDescription)")
            }
        }
    }

    func editMessage(chatId: Int64, messageId: Int64, text: String) async -> Bool {
        let (formatted, mode) = TGMessageFormatter.format(text)
        do {
            _ = try await apiClient.editMessageText(chatId: chatId, messageId: messageId, text: formatted, parseMode: mode)
            return true
        } catch let error as TGAPIError {
            switch error {
            case .permanentTelegramError:
                return false
            case .rateLimited, .retryableNetwork, .formatRejected:
                return false
            }
        } catch {
            return false
        }
    }

    func sendChatAction(chatId: Int64, action: String = "typing") async {
        do {
            try await apiClient.sendChatAction(chatId: chatId, action: action)
        } catch {
            log("[axion] Telegram sendChatAction failed: \(error.localizedDescription)")
        }
    }

    static func buildSkillsKeyboard(skills: [Skill], page: Int, pageSize: Int = 20) -> TGInlineKeyboardMarkup {
        let start = page * pageSize
        let end = min(start + pageSize, skills.count)
        let pageSkills = Array(skills[start..<end])
        let totalPages = (skills.count + pageSize - 1) / pageSize

        var rows: [[TGInlineKeyboardButton]] = []

        for index in stride(from: 0, to: pageSkills.count, by: 2) {
            var row: [TGInlineKeyboardButton] = []
            row.append(TGInlineKeyboardButton(text: pageSkills[index].name, callbackData: TGCallbackData(action: .triggerSkill, detail: pageSkills[index].name, pendingId: "0").encoded))
            if index + 1 < pageSkills.count {
                row.append(TGInlineKeyboardButton(text: pageSkills[index + 1].name, callbackData: TGCallbackData(action: .triggerSkill, detail: pageSkills[index + 1].name, pendingId: "0").encoded))
            }
            rows.append(row)
        }

        if totalPages > 1 {
            var navRow: [TGInlineKeyboardButton] = []
            if page > 0 {
                navRow.append(TGInlineKeyboardButton(text: "◀ Prev", callbackData: TGCallbackData(action: .skillsPage, detail: String(page - 1), pendingId: "0").encoded))
            }
            if page < totalPages - 1 {
                navRow.append(TGInlineKeyboardButton(text: "Next ▶", callbackData: TGCallbackData(action: .skillsPage, detail: String(page + 1), pendingId: "0").encoded))
            }
            rows.append(navRow)
        }

        return TGInlineKeyboardMarkup(inlineKeyboard: rows)
    }

    func sendWithMarkup(_ text: String, to chatId: Int64, replyMarkup: TGInlineKeyboardMarkup?) async -> Int64? {
        let (formatted, mode) = TGMessageFormatter.format(text)
        do {
            let msg = try await apiClient.sendMessage(chatId: chatId, text: formatted, parseMode: mode, replyMarkup: replyMarkup)
            return msg.messageId
        } catch {
            log("[axion] Telegram sendWithMarkup failed: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func sendFormatted(_ text: String, to chatId: Int64, replyToMessageId: Int64? = nil) async -> Int64? {
        let preferredPayload = preferredFormattedPayload(for: text)
        let formatted = preferredPayload.formattedText
        let mode = preferredPayload.parseMode
        let chunks = preferredPayload.chunks

        var sentCount = 0
        var firstMessageId: Int64?
        for (index, chunk) in chunks.enumerated() {
            let replyId = index == 0 ? replyToMessageId : nil

            do {
                let msg = try await apiClient.sendMessage(chatId: chatId, text: chunk, parseMode: mode, replyToMessageId: replyId)
                if firstMessageId == nil { firstMessageId = msg.messageId }
                sentCount += 1
            } catch let error as TGAPIError {
                switch error {
                case .formatRejected:
                    await sendFallbackChunks(
                        text: text,
                        to: chatId,
                        replyToMessageId: replyToMessageId,
                        startIndex: sentCount,
                        failedMode: mode
                    )
                    return firstMessageId
                default:
                    log("[axion] Telegram sendFormatted failed: \(error.localizedDescription)")
                }
            } catch {
                log("[axion] Telegram sendFormatted failed: \(error.localizedDescription)")
            }
        }
        return firstMessageId
    }

    private func preferredFormattedPayload(for text: String) -> TGFormattedPayload {
        let (markdownText, markdownMode) = TGMessageFormatter.format(text)
        let markdownChunks = TGMessageFormatter.split(formattedText: markdownText, parseMode: markdownMode)
        let markdownPayload = TGFormattedPayload(
            formattedText: markdownText,
            parseMode: markdownMode,
            chunks: markdownChunks
        )

        let (htmlText, htmlMode) = TGMessageFormatter.formatAsHTML(text)
        let htmlChunks = TGMessageFormatter.split(formattedText: htmlText, parseMode: htmlMode)
        let htmlPayload = TGFormattedPayload(
            formattedText: htmlText,
            parseMode: htmlMode,
            chunks: htmlChunks
        )

        if htmlPayload.chunks.count < markdownPayload.chunks.count {
            return htmlPayload
        }

        return markdownPayload
    }

    private func sendFallbackChunks(
        text: String,
        to chatId: Int64,
        replyToMessageId: Int64?,
        startIndex: Int,
        failedMode: TGParseMode
    ) async {
        if failedMode == .markdownV2 {
            await sendHTMLFallbackChunks(text: text, to: chatId, replyToMessageId: replyToMessageId, startIndex: startIndex)
            return
        }

        await sendPlainFallbackChunks(text: text, to: chatId, replyToMessageId: replyToMessageId, startIndex: startIndex)
    }

    private func sendHTMLFallbackChunks(text: String, to chatId: Int64, replyToMessageId: Int64?, startIndex: Int) async {
        let (htmlFormatted, htmlMode) = TGMessageFormatter.formatAsHTML(text)
        let htmlChunks = TGMessageFormatter.split(formattedText: htmlFormatted, parseMode: htmlMode)

        for (hIndex, htmlChunk) in htmlChunks.enumerated() {
            guard hIndex >= startIndex else { continue }
            let hReplyId = hIndex == 0 ? replyToMessageId : nil
            do {
                _ = try await apiClient.sendMessage(chatId: chatId, text: htmlChunk, parseMode: htmlMode, replyToMessageId: hReplyId)
            } catch {
                await sendPlainFallbackChunks(text: text, to: chatId, replyToMessageId: replyToMessageId, startIndex: startIndex)
                return
            }
        }
    }

    private func sendPlainFallbackChunks(text: String, to chatId: Int64, replyToMessageId: Int64?, startIndex: Int) async {
        let (plainFormatted, plainMode) = TGMessageFormatter.formatAsPlain(text)
        let plainChunks = TGMessageFormatter.split(formattedText: plainFormatted, parseMode: plainMode)

        for (pIndex, plainChunk) in plainChunks.enumerated() {
            guard pIndex >= startIndex else { continue }
            let pReplyId = pIndex == 0 ? replyToMessageId : nil
            do {
                _ = try await apiClient.sendMessage(chatId: chatId, text: plainChunk, parseMode: plainMode, replyToMessageId: pReplyId)
            } catch {
                log("[axion] Telegram sendFormatted plain fallback failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Authorization

    private func isAuthorized(userId: Int64) -> Bool {
        allowedUsers.contains(String(userId))
    }

    // MARK: - Message Splitting

    private func splitMessage(_ text: String) -> [String] {
        let maxLen = 4096
        guard text.count > maxLen else { return [text] }

        var chunks: [String] = []
        var remaining = text[...]

        while remaining.count > 0 {
            if remaining.count <= maxLen {
                chunks.append(String(remaining))
                break
            }

            let endIndex = remaining.index(remaining.startIndex, offsetBy: maxLen)
            let chunk = remaining[..<endIndex]

            if let newline = chunk.lastIndex(of: "\n") {
                let splitPoint = remaining.index(after: newline)
                chunks.append(String(remaining[..<splitPoint]))
                remaining = remaining[splitPoint...]
            } else {
                chunks.append(String(chunk))
                remaining = remaining[endIndex...]
            }
        }

        return chunks
    }
}
