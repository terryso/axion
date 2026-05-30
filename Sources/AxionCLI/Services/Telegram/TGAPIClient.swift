import Foundation

// MARK: - Protocol

protocol TGAPIClientProtocol: Sendable {
    func getUpdates(offset: Int64?, timeout: Int) async throws -> [TGUpdate]
    func sendMessage(chatId: Int64, text: String) async throws -> TGMessage
    func getFile(fileId: String) async throws -> TGFile
    func downloadFile(filePath: String) async throws -> Data
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
            throw TGAPIError.apiError("Invalid URL for getUpdates")
        }
        let request = URLRequest(url: url, timeoutInterval: Double(timeout + 10))

        let response: TGResponse<[TGUpdate]> = try await performRequest(request, retries: maxRetries)
        guard response.ok else {
            throw TGAPIError.apiError(response.description ?? "Unknown error")
        }
        return response.result ?? []
    }

    func sendMessage(chatId: Int64, text: String) async throws -> TGMessage {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw TGAPIError.apiError("Invalid URL for sendMessage")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = TGSendMessageRequest(chatId: chatId, text: text, parseMode: nil)
        request.httpBody = try JSONEncoder().encode(body)

        let response: TGResponse<TGMessage> = try await performRequest(request, retries: maxRetries)
        guard response.ok, let message = response.result else {
            throw TGAPIError.apiError(response.description ?? "sendMessage failed")
        }
        return message
    }

    func getFile(fileId: String) async throws -> TGFile {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/getFile?file_id=\(fileId)") else {
            throw TGAPIError.apiError("Invalid URL for getFile")
        }
        let request = URLRequest(url: url, timeoutInterval: 30)
        let response: TGResponse<TGFile> = try await performRequest(request, retries: maxRetries)
        guard response.ok, let file = response.result else {
            throw TGAPIError.apiError(response.description ?? "getFile failed")
        }
        return file
    }

    func downloadFile(filePath: String) async throws -> Data {
        guard let url = URL(string: "https://api.telegram.org/file/bot\(token)/\(filePath)") else {
            throw TGAPIError.apiError("Invalid URL for file download")
        }
        let request = URLRequest(url: url, timeoutInterval: 60)
        let (data, httpResponse) = try await session.data(for: request)
        if let http = httpResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TGAPIError.apiError("File download failed: HTTP \(http.statusCode)")
        }
        return data
    }

    // MARK: - Retry Logic

    private func performRequest<T: Codable & Sendable>(_ request: URLRequest, retries: Int) async throws -> T {
        var lastError: Error?
        for attempt in 0..<retries {
            do {
                let (data, httpResponse) = try await session.data(for: request)
                if let http = httpResponse as? HTTPURLResponse, (400...499).contains(http.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    throw TGAPIError.apiError(body)
                }
                return try JSONDecoder().decode(T.self, from: data)
            } catch let error as TGAPIError {
                throw error
            } catch {
                lastError = error
                if attempt < retries - 1 {
                    let delay = pow(2.0, Double(attempt)) // 1s → 2s → 4s
                    try? await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError!
    }
}

// MARK: - Errors

enum TGAPIError: Error, LocalizedError {
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let message): return message
        }
    }
}
