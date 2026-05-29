import Foundation

actor TelegramAdapter {
    private let apiClient: any TGAPIClientProtocol
    private let allowedUsers: Set<String>
    private var taskQueue: (any TaskSerialQueueProtocol)?
    private var lastUpdateId: Int64 = 0
    private var isRunning = false

    nonisolated(unsafe) private(set) var statusValue: String = "disabled"

    init(apiClient: any TGAPIClientProtocol, allowedUsers: Set<String>, taskQueue: (any TaskSerialQueueProtocol)? = nil) {
        self.apiClient = apiClient
        self.allowedUsers = allowedUsers
        self.taskQueue = taskQueue
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        statusValue = "connected"
        fputs("[axion] Telegram adapter connected\n", stderr)
        await pollLoop()
    }

    func stop() {
        isRunning = false
        statusValue = "disabled"
    }

    func statusInfo() -> String? {
        return statusValue
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
                fputs("[axion] Telegram getUpdates failed: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    // MARK: - Message Processing

    private func processMessage(_ message: TGMessage) async {
        guard let userId = message.from?.id else { return }
        guard isAuthorized(userId: userId) else { return }
        guard let text = message.text, !text.isEmpty else { return }

        fputs("[axion] Telegram task submitted: \"\(text.prefix(50))\"\n", stderr)

        if let queue = taskQueue {
            await queue.enqueue(task: text, chatId: message.chat.id)
        } else {
            await sendReply("任务已收到", to: message.chat.id)
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
                fputs("[axion] Telegram sendMessage failed: \(error.localizedDescription)\n", stderr)
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
