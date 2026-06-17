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
        return try await sendMessageRequest(chatId: chatId, text: text, parseMode: nil, replyToMessageId: nil, replyMarkup: nil)
    }

    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyToMessageId: Int64? = nil) async throws -> TGMessage {
        return try await sendMessageRequest(chatId: chatId, text: text, parseMode: parseMode, replyToMessageId: replyToMessageId, replyMarkup: nil)
    }

    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup? = nil) async throws -> TGMessage {
        return try await sendMessageRequest(chatId: chatId, text: text, parseMode: parseMode, replyToMessageId: nil, replyMarkup: replyMarkup)
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode) async throws -> TGMessage {
        return try await editMessageText(chatId: chatId, messageId: messageId, text: text, parseMode: parseMode, replyMarkup: nil)
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup? = nil) async throws -> TGMessage {
        let body = TGEditMessageTextRequest(chatId: chatId, messageId: messageId, text: text, parseMode: parseMode, replyMarkup: replyMarkup)
        return try await postForMessage(endpoint: "editMessageText", body: body)
    }

    func answerCallbackQuery(callbackQueryId: String, text: String? = nil) async throws {
        let body = TGAnswerCallbackQueryRequest(callbackQueryId: callbackQueryId, text: text)
        try await postVoid(endpoint: "answerCallbackQuery", body: body, timeout: 10)
    }

    func getFile(fileId: String) async throws -> TGFile {
        return try await get(endpoint: "getFile?file_id=\(fileId)")
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
        struct ChatActionRequest: Codable {
            let chatId: Int64
            let action: String
            enum CodingKeys: String, CodingKey {
                case chatId = "chat_id"
                case action
            }
        }
        let body = ChatActionRequest(chatId: chatId, action: action)
        try await postVoid(endpoint: "sendChatAction", body: body, timeout: 10, retries: 1)
    }

    func setMyCommands(commands: [(name: String, description: String)]) async throws {
        struct BotCommand: Codable {
            let command: String
            let description: String
        }
        struct SetMyCommandsRequest: Codable {
            let commands: [BotCommand]
        }
        let body = SetMyCommandsRequest(commands: commands.map { BotCommand(command: $0.name, description: $0.description) })
        try await postVoid(endpoint: "setMyCommands", body: body)
    }

    // MARK: - Request Helpers

    private func sendMessageRequest(
        chatId: Int64,
        text: String,
        parseMode: TGParseMode?,
        replyToMessageId: Int64?,
        replyMarkup: TGInlineKeyboardMarkup?
    ) async throws -> TGMessage {
        let body = TGSendMessageRequest(chatId: chatId, text: text, parseMode: parseMode, replyToMessageId: replyToMessageId, replyMarkup: replyMarkup)
        return try await postForMessage(endpoint: "sendMessage", body: body)
    }

    private func postForMessage<T: Codable & Sendable>(endpoint: String, body: T) async throws -> TGMessage {
        let request = try buildPostRequest(endpoint: endpoint, body: body)
        let response: TGResponse<TGMessage> = try await performRequest(request, retries: maxRetries)
        guard response.ok, let message = response.result else {
            throw TGAPIError.permanentTelegramError(response.description ?? "\(endpoint) failed")
        }
        return message
    }

    private func postVoid<T: Codable & Sendable>(endpoint: String, body: T, timeout: TimeInterval = 30, retries: Int? = nil) async throws {
        let request = try buildPostRequest(endpoint: endpoint, body: body, timeout: timeout)
        let response: TGResponse<Bool> = try await performRequest(request, retries: retries ?? maxRetries)
        guard response.ok else {
            throw TGAPIError.permanentTelegramError(response.description ?? "\(endpoint) failed")
        }
    }

    private func get<T: Codable & Sendable>(endpoint: String, timeout: TimeInterval = 30) async throws -> T {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(endpoint)") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for \(endpoint)")
        }
        let request = URLRequest(url: url, timeoutInterval: timeout)
        let response: TGResponse<T> = try await performRequest(request, retries: maxRetries)
        guard response.ok, let result = response.result else {
            throw TGAPIError.permanentTelegramError(response.description ?? "\(endpoint) failed")
        }
        return result
    }

    private func buildPostRequest<T: Codable & Sendable>(endpoint: String, body: T, timeout: TimeInterval = 30) throws -> URLRequest {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(endpoint)") else {
            throw TGAPIError.permanentTelegramError("Invalid URL for \(endpoint)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try axionSortedEncoder.encode(body)
        return request
    }

    // MARK: - Retry Logic

    private func performRequest<T: Codable & Sendable>(_ request: URLRequest, retries: Int) async throws -> T {
        var lastError: Error?
        for attempt in 0..<retries {
            do {
                let (data, httpResponse) = try await session.data(for: request)
                if let http = httpResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    throw classifyHTTPError(statusCode: http.statusCode, body: body, httpResponse: http)
                }
                return try JSONDecoder().decode(T.self, from: data)
            } catch let error as TGAPIError {
                switch error {
                case .rateLimited(_, let retryAfter):
                    if attempt < retries - 1 {
                        try? await _Concurrency.Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
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
                case .formatRejected, .permanentTelegramError, .authFailed, .pollingConflict:
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

    private func classifyHTTPError(statusCode: Int, body: String, httpResponse: HTTPURLResponse) -> TGAPIError {
        switch statusCode {
        case 429:
            let retryAfter = TimeInterval(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 5
            return .rateLimited(body, retryAfter: retryAfter)
        case 401, 403:
            return .authFailed(body)
        case 409:
            return .pollingConflict(body)
        case 400:
            if body.contains("can't parse entities") || body.contains("Bad Request") {
                return .formatRejected(body)
            }
            return .permanentTelegramError(body)
        default:
            if (500...599).contains(statusCode) {
                return .retryableNetwork("HTTP \(statusCode): \(body)")
            }
            return .permanentTelegramError(body)
        }
    }
}

// MARK: - Errors

enum TGAPIError: Error, LocalizedError {
    case retryableNetwork(String)
    case rateLimited(String, retryAfter: TimeInterval)
    case formatRejected(String)
    case authFailed(String)
    case pollingConflict(String)
    case permanentTelegramError(String)

    var errorDescription: String? {
        switch self {
        case .retryableNetwork(let msg): return msg
        case .rateLimited(let msg, _): return msg
        case .formatRejected(let msg): return msg
        case .authFailed(let msg): return msg
        case .pollingConflict(let msg): return msg
        case .permanentTelegramError(let msg): return msg
        }
    }
}
