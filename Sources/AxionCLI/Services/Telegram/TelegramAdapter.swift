import Foundation
import OpenAgentSDK

actor TelegramAdapter {
    struct TGFormattedPayload {
        let formattedText: String
        let parseMode: TGParseMode
        let chunks: [String]
    }

    let apiClient: any TGAPIClientProtocol
    private let allowedUsers: Set<String>
    private let commandRouter: TGCommandRouter?
    var taskQueue: (any TaskSerialQueueProtocol)?
    let skillsProvider: (@Sendable () -> [Skill])?
    private var lastUpdateId: Int64 = 0
    private var isRunning = false
    let log: @Sendable (String) -> Void
    let sessionStore: TGInteractiveSessionStore?

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
        var consecutiveConflicts = 0
        while isRunning {
            do {
                let updates = try await apiClient.getUpdates(offset: lastUpdateId + 1, timeout: 30)
                statusValue = "connected"
                consecutiveErrors = 0
                consecutiveConflicts = 0
                await processUpdates(updates)
            } catch let error as TGAPIError {
                switch error {
                case .pollingConflict:
                    consecutiveConflicts += 1
                    if consecutiveConflicts >= 3 {
                        statusValue = "conflict_stopped"
                        log("[axion] Telegram polling stopped: 3 consecutive 409 conflicts (another instance may be running)")
                        isRunning = false
                        break
                    }
                    statusValue = "conflict:\(consecutiveConflicts)"
                    log("[axion] Telegram 409 conflict, waiting 30s before retry (\(consecutiveConflicts)/3)")
                    try? await _Concurrency.Task.sleep(nanoseconds: 30_000_000_000)
                case .authFailed:
                    consecutiveConflicts = 0
                    statusValue = "auth_failed"
                    log("[axion] TG Bot 认证失败，请检查 token 配置 (AXION_TELEGRAM_BOT_TOKEN)")
                    isRunning = false
                default:
                    statusValue = "error:\(error.localizedDescription)"
                    log("[axion] Telegram getUpdates failed: \(error.localizedDescription)")
                    consecutiveErrors += 1
                    let delay = min(5.0 * Double(consecutiveErrors), 30.0)
                    try? await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
            case .rateLimited, .retryableNetwork, .formatRejected, .authFailed, .pollingConflict:
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

    // MARK: - Authorization

    func isAuthorized(userId: Int64) -> Bool {
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
