import Foundation

actor TelegramAdapter {
    private let apiClient: any TGAPIClientProtocol
    private let allowedUsers: Set<String>
    private let commandRouter: TGCommandRouter?
    private var taskQueue: (any TaskSerialQueueProtocol)?
    private var lastUpdateId: Int64 = 0
    private var isRunning = false
    private let log: @Sendable (String) -> Void

    nonisolated(unsafe) private(set) var statusValue: String = "disabled"

    init(apiClient: any TGAPIClientProtocol, allowedUsers: Set<String>, taskQueue: (any TaskSerialQueueProtocol)? = nil, commandRouter: TGCommandRouter? = nil, log: @Sendable @escaping (String) -> Void = { fputs($0 + "\n", stderr) }) {
        self.apiClient = apiClient
        self.allowedUsers = allowedUsers
        self.taskQueue = taskQueue
        self.commandRouter = commandRouter
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
            if let message = update.message {
                await processMessage(message)
            }
        }
    }

    // MARK: - Poll Loop

    private func pollLoop() async {
        while isRunning {
            do {
                let updates = try await apiClient.getUpdates(offset: lastUpdateId + 1, timeout: 30)
                statusValue = "connected"
                for update in updates {
                    lastUpdateId = update.updateId
                    if let message = update.message {
                        await processMessage(message)
                    }
                }
            } catch {
                statusValue = "error:\(error.localizedDescription)"
                log("[axion] Telegram getUpdates failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Message Processing

    private func processMessage(_ message: TGMessage) async {
        guard let userId = message.from?.id else { return }
        guard isAuthorized(userId: userId) else { return }

        // Handle photo messages
        if let photo = message.photo, !photo.isEmpty {
            await processPhoto(photo, caption: message.text, chatId: message.chat.id)
            return
        }

        guard let text = message.text, !text.isEmpty else { return }

        if let reply = await commandRouter?.handle(text, chatId: message.chat.id) {
            await sendReply(reply, to: message.chat.id)
            return
        }

        log("[axion] Telegram task submitted: \"\(text.prefix(50))\"")

        if let queue = taskQueue {
            await queue.enqueue(task: text, chatId: message.chat.id)
        } else {
            await sendReply("任务已收到", to: message.chat.id)
        }
    }

    private func processPhoto(_ sizes: [TGPhotoSize], caption: String?, chatId: Int64) async {
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
                await queue.enqueue(task: taskText, chatId: chatId)
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

    @discardableResult
    func sendFormatted(_ text: String, to chatId: Int64, replyToMessageId: Int64? = nil) async -> Int64? {
        let (formatted, mode) = TGMessageFormatter.format(text)
        let chunks = TGMessageFormatter.split(formattedText: formatted, parseMode: mode)

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
                    // Fallback: re-format and send only unsent chunks
                    await sendFallbackChunks(text: text, to: chatId, replyToMessageId: replyToMessageId, startIndex: sentCount)
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

    private func sendFallbackChunks(text: String, to chatId: Int64, replyToMessageId: Int64?, startIndex: Int) async {
        let (htmlFormatted, htmlMode) = TGMessageFormatter.formatAsHTML(text)
        let htmlChunks = TGMessageFormatter.split(formattedText: htmlFormatted, parseMode: htmlMode)

        for (hIndex, htmlChunk) in htmlChunks.enumerated() {
            guard hIndex >= startIndex else { continue }
            let hReplyId = hIndex == 0 ? replyToMessageId : nil
            do {
                _ = try await apiClient.sendMessage(chatId: chatId, text: htmlChunk, parseMode: htmlMode, replyToMessageId: hReplyId)
            } catch {
                // Final fallback to plain
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
