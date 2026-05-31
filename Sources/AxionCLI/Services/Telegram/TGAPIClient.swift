import Foundation

// MARK: - Protocol

protocol TGAPIClientProtocol: Sendable {
    func getUpdates(offset: Int64?, timeout: Int) async throws -> [TGUpdate]
    func sendMessage(chatId: Int64, text: String) async throws -> TGMessage
    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyToMessageId: Int64?) async throws -> TGMessage
    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup?) async throws -> TGMessage
    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode) async throws -> TGMessage
    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup?) async throws -> TGMessage
    func answerCallbackQuery(callbackQueryId: String, text: String?) async throws
    func getFile(fileId: String) async throws -> TGFile
    func downloadFile(filePath: String) async throws -> Data
    func sendChatAction(chatId: Int64, action: String) async throws
    func setMyCommands(commands: [(name: String, description: String)]) async throws
}

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - Implementation

struct TGAPIClient: TGAPIClientProtocol {
    private let token: String
    private let session: any URLSessionProtocol
    private let maxRetries: Int

    init(token: String, session: any URLSessionProtocol = URLSession.shared, maxRetries: Int = 3) {
        self.token = token
        self.session = session
        self.maxRetries = maxRetries
    }

    func getUpdates(offset: Int64?, timeout: Int = 30) async throws -> [TGUpdate] {
        var components = URLComponents(string: "https://api.telegram.org/bot\(token)/getUpdates")!
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "timeout", value: String(timeout))]
        if let offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw TGAPIError.permanentTelegramError("Invalid URL for getUpdates")
        }
        let request = URLRequest(url: url, timeoutInterval: Double(timeout + 10))

        let response: TGResponse<[TGUpdate]> = try await performRequest(request, retries: maxRetries)
        guard response.ok else {
            throw TGAPIError.permanentTelegramError(response.description ?? "Unknown error")
        }
        return response.result ?? []
    }

    func sendMessage(chatId: Int64, text: String) async throws -> TGMessage {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for sendMessage")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = TGSendMessageRequest(chatId: chatId, text: text, parseMode: nil)
        request.httpBody = try JSONEncoder().encode(body)

        let response: TGResponse<TGMessage> = try await performRequest(request, retries: maxRetries)
        guard response.ok, let message = response.result else {
            throw TGAPIError.permanentTelegramError(response.description ?? "sendMessage failed")
        }
        return message
    }

    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyToMessageId: Int64? = nil) async throws -> TGMessage {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for sendMessage")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = TGSendMessageRequest(chatId: chatId, text: text, parseMode: parseMode, replyToMessageId: replyToMessageId)
        request.httpBody = try JSONEncoder().encode(body)

        let response: TGResponse<TGMessage> = try await performRequest(request, retries: maxRetries)
        guard response.ok, let message = response.result else {
            throw TGAPIError.permanentTelegramError(response.description ?? "sendMessage failed")
        }
        return message
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode) async throws -> TGMessage {
        return try await editMessageText(chatId: chatId, messageId: messageId, text: text, parseMode: parseMode, replyMarkup: nil)
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup? = nil) async throws -> TGMessage {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/editMessageText") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for editMessageText")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = TGEditMessageTextRequest(
            chatId: chatId,
            messageId: messageId,
            text: text,
            parseMode: parseMode,
            replyMarkup: replyMarkup
        )
        request.httpBody = try JSONEncoder().encode(body)

        let response: TGResponse<TGMessage> = try await performRequest(request, retries: maxRetries)
        guard response.ok, let message = response.result else {
            throw TGAPIError.permanentTelegramError(response.description ?? "editMessageText failed")
        }
        return message
    }

    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup? = nil) async throws -> TGMessage {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for sendMessage")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = TGSendMessageRequest(chatId: chatId, text: text, parseMode: parseMode, replyMarkup: replyMarkup)
        request.httpBody = try JSONEncoder().encode(body)

        let response: TGResponse<TGMessage> = try await performRequest(request, retries: maxRetries)
        guard response.ok, let message = response.result else {
            throw TGAPIError.permanentTelegramError(response.description ?? "sendMessage failed")
        }
        return message
    }

    func answerCallbackQuery(callbackQueryId: String, text: String? = nil) async throws {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/answerCallbackQuery") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for answerCallbackQuery")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body = TGAnswerCallbackQueryRequest(callbackQueryId: callbackQueryId, text: text)
        request.httpBody = try JSONEncoder().encode(body)

        let response: TGResponse<Bool> = try await performRequest(request, retries: maxRetries)
        guard response.ok else {
            throw TGAPIError.permanentTelegramError(response.description ?? "answerCallbackQuery failed")
        }
    }

    func getFile(fileId: String) async throws -> TGFile {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/getFile?file_id=\(fileId)") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for getFile")
        }
        let request = URLRequest(url: url, timeoutInterval: 30)
        let response: TGResponse<TGFile> = try await performRequest(request, retries: maxRetries)
        guard response.ok, let file = response.result else {
            throw TGAPIError.permanentTelegramError(response.description ?? "getFile failed")
        }
        return file
    }

    func downloadFile(filePath: String) async throws -> Data {
        guard let url = URL(string: "https://api.telegram.org/file/bot\(token)/\(filePath)") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for file download")
        }
        let request = URLRequest(url: url, timeoutInterval: 60)
        let (data, httpResponse) = try await session.data(for: request)
        if let http = httpResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TGAPIError.permanentTelegramError("File download failed: HTTP \(http.statusCode)")
        }
        return data
    }

    func sendChatAction(chatId: Int64, action: String) async throws {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendChatAction") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for sendChatAction")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        struct ChatActionRequest: Codable {
            let chatId: Int64
            let action: String
            enum CodingKeys: String, CodingKey {
                case chatId = "chat_id"
                case action
            }
        }
        request.httpBody = try JSONEncoder().encode(ChatActionRequest(chatId: chatId, action: action))

        let response: TGResponse<Bool> = try await performRequest(request, retries: 1)
        guard response.ok else {
            throw TGAPIError.permanentTelegramError(response.description ?? "sendChatAction failed")
        }
    }

    func setMyCommands(commands: [(name: String, description: String)]) async throws {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/setMyCommands") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for setMyCommands")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        struct BotCommand: Codable {
            let command: String
            let description: String
        }
        struct SetMyCommandsRequest: Codable {
            let commands: [BotCommand]
        }
        let body = SetMyCommandsRequest(commands: commands.map { BotCommand(command: $0.name, description: $0.description) })
        request.httpBody = try JSONEncoder().encode(body)

        let response: TGResponse<Bool> = try await performRequest(request, retries: maxRetries)
        guard response.ok else {
            throw TGAPIError.permanentTelegramError(response.description ?? "setMyCommands failed")
        }
    }

    // MARK: - Retry Logic

    private func performRequest<T: Codable & Sendable>(_ request: URLRequest, retries: Int) async throws -> T {
        var lastError: Error?
        for attempt in 0..<retries {
            do {
                let (data, httpResponse) = try await session.data(for: request)
                if let http = httpResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    throw classifyHTTPError(statusCode: http.statusCode, body: body)
                }
                return try JSONDecoder().decode(T.self, from: data)
            } catch let error as TGAPIError {
                switch error {
                case .rateLimited:
                    if attempt < retries - 1 {
                        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    }
                    throw error
                case .retryableNetwork:
                    if attempt < retries - 1 {
                        let delay = pow(2.0, Double(attempt))
                        try? await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    throw error
                case .formatRejected, .permanentTelegramError:
                    throw error
                }
            } catch {
                lastError = error
                if attempt < retries - 1 {
                    let delay = pow(2.0, Double(attempt))
                    try? await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError!
    }

    private func classifyHTTPError(statusCode: Int, body: String) -> TGAPIError {
        switch statusCode {
        case 429:
            return .rateLimited(body)
        case 400:
            if body.contains("can't parse entities") || body.contains("Bad Request") {
                return .formatRejected(body)
            }
            return .permanentTelegramError(body)
        default:
            return .permanentTelegramError(body)
        }
    }
}

// MARK: - Errors

enum TGAPIError: Error, LocalizedError {
    case retryableNetwork(String)
    case rateLimited(String)
    case formatRejected(String)
    case permanentTelegramError(String)

    var errorDescription: String? {
        switch self {
        case .retryableNetwork(let msg): return msg
        case .rateLimited(let msg): return msg
        case .formatRejected(let msg): return msg
        case .permanentTelegramError(let msg): return msg
        }
    }
}
