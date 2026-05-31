import Testing
import Foundation
@testable import AxionCLI

@Suite("TGAPIClient")
struct TGAPIClientTests {

    // MARK: - Request Body Encoding

    @Test("TGSendMessageRequest encodes with snake_case keys")
    func sendMessageRequestEncoding() throws {
        let req = TGSendMessageRequest(chatId: 12345, text: "test", parseMode: nil)
        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"chat_id\":12345"))
        #expect(json.contains("\"text\":\"test\""))

        let decoded = try JSONDecoder().decode(TGSendMessageRequest.self, from: data)
        #expect(decoded.chatId == 12345)
        #expect(decoded.text == "test")
    }

    @Test("TGSendMessageRequest with parseMode encodes correctly")
    func sendMessageRequestWithParseMode() throws {
        let req = TGSendMessageRequest(chatId: 99, text: "*bold*", parseMode: .markdownV2)
        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"parse_mode\":\"MarkdownV2\""))
    }

    // MARK: - Retry Logic

    @Test("TGAPIClient retries on network failure via mock session")
    func retriesOnFailure() async {
        // Use a mock URLSession that always fails — no real network calls
        let session = MockFailingURLSession()
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 2)

        do {
            _ = try await client.sendMessage(chatId: 123, text: "test")
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Expected — network failure after retries
        }
        #expect(session.attemptCount == 2) // initial + 1 retry
    }

    @Test("TGAPIClient does not retry on 4xx HTTP errors via mock session")
    func noRetryOnClientError() async {
        // Use a mock URLSession that returns 401 immediately
        let session = MockHTTPErrorURLSession(statusCode: 401)
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            // 4xx errors are thrown as TGAPIError immediately — no retry
            #expect(error.errorDescription != nil)
        } catch {
            // Acceptable fallback
        }
        #expect(session.attemptCount == 1) // no retry for 4xx
    }

    // MARK: - TGAPIError

    @Test("TGAPIError has localized description for all cases")
    func apiErrorDescriptionAllCases() {
        #expect(TGAPIError.retryableNetwork("net fail").errorDescription == "net fail")
        #expect(TGAPIError.rateLimited("slow down").errorDescription == "slow down")
        #expect(TGAPIError.formatRejected("bad md").errorDescription == "bad md")
        #expect(TGAPIError.permanentTelegramError("gone").errorDescription == "gone")
    }

    @Test("TGAPIError conforms to Error")
    func apiErrorConformsToError() {
        let error: Error = TGAPIError.permanentTelegramError("fail")
        #expect(error.localizedDescription == "fail")
    }

    // MARK: - Error Classification via HTTP Status

    @Test("429 classifies as rateLimited")
    func http429RateLimited() async {
        let session = MockHTTPErrorURLSession(statusCode: 429)
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 1)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            if case .rateLimited = error {
                // correct
            } else {
                #expect(Bool(false), "Expected rateLimited, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("400 with parse error classifies as formatRejected")
    func http400FormatRejected() async {
        let session = MockHTTPErrorURLSession(statusCode: 400, body: "{\"ok\":false,\"description\":\"can't parse entities\"}")
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 1)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            if case .formatRejected = error {
                // correct
            } else {
                #expect(Bool(false), "Expected formatRejected, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("403 classifies as permanentTelegramError")
    func http403Permanent() async {
        let session = MockHTTPErrorURLSession(statusCode: 403)
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 1)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            if case .permanentTelegramError = error {
                // correct
            } else {
                #expect(Bool(false), "Expected permanentTelegramError, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    // MARK: - TGParseMode

    @Test("TGParseMode raw values")
    func parseModeRawValues() {
        #expect(TGParseMode.markdownV2.rawValue == "MarkdownV2")
        #expect(TGParseMode.html.rawValue == "HTML")
        #expect(TGParseMode.plain.rawValue == "")
    }

    @Test("TGSendMessageRequest with replyToMessageId encodes correctly")
    func sendMessageRequestWithReply() throws {
        let req = TGSendMessageRequest(chatId: 123, text: "reply", parseMode: .markdownV2, replyToMessageId: 456)
        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"reply_to_message_id\":456"))
        #expect(json.contains("\"parse_mode\":\"MarkdownV2\""))
    }

    @Test("TGSendMessageRequest plain mode omits parse_mode")
    func plainModeOmitsParseMode() throws {
        let req = TGSendMessageRequest(chatId: 123, text: "plain", parseMode: .plain)
        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("parse_mode"))
    }

    // MARK: - Protocol Mock for Integration Tests

    @Test("MockTGAPIClient can be used via protocol")
    func mockClientViaProtocol() async throws {
        let mock = MockTGAPIClient()
        let client: any TGAPIClientProtocol = mock

        let updates = try await client.getUpdates(offset: nil, timeout: 10)
        #expect(updates.isEmpty)

        let message = try await client.sendMessage(chatId: 123, text: "hi")
        #expect(message.messageId == 1)
    }

    // MARK: - getFile Protocol Mock

    @Test("MockTGAPIClient getFile returns default result")
    func mockGetFileDefault() async throws {
        let mock = MockTGAPIClient()
        let client: any TGAPIClientProtocol = mock

        let file = try await client.getFile(fileId: "test123")
        #expect(file.fileId == "test123")
        #expect(file.filePath == "photos/file_0.jpg")
    }

    @Test("MockTGAPIClient getFile returns custom result")
    func mockGetFileCustom() async throws {
        let mock = MockTGAPIClient()
        await mock.setGetFileResult(TGFile(fileId: "custom", filePath: "photos/custom.png"))

        let file = try await mock.getFile(fileId: "custom")
        #expect(file.filePath == "photos/custom.png")
    }

    @Test("MockTGAPIClient getFile throws configured error")
    func mockGetFileError() async {
        let mock = MockTGAPIClient()
        await mock.setGetFileError(TGAPIError.permanentTelegramError("file not found"))

        do {
            _ = try await mock.getFile(fileId: "bad")
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            #expect(error.errorDescription == "file not found")
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("MockTGAPIClient downloadFile returns default data")
    func mockDownloadFileDefault() async throws {
        let mock = MockTGAPIClient()
        let client: any TGAPIClientProtocol = mock

        let data = try await client.downloadFile(filePath: "photos/test.jpg")
        #expect(!data.isEmpty)
    }

    // MARK: - sendChatAction Mock

    @Test("MockTGAPIClient sendChatAction records action")
    func mockSendChatActionRecords() async throws {
        let mock = MockTGAPIClient()
        let client: any TGAPIClientProtocol = mock

        try await client.sendChatAction(chatId: 123, action: "typing")
        try await client.sendChatAction(chatId: 456, action: "upload_photo")

        let actions = await mock.chatActions
        #expect(actions.count == 2)
        #expect(actions[0] == (123, "typing"))
        #expect(actions[1] == (456, "upload_photo"))
    }

    @Test("MockTGAPIClient sendChatAction throws configured error")
    func mockSendChatActionError() async {
        let mock = MockTGAPIClient()
        await mock.setSendChatActionError(TGAPIError.permanentTelegramError("forbidden"))

        do {
            try await mock.sendChatAction(chatId: 123, action: "typing")
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            #expect(error.errorDescription == "forbidden")
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("MockTGAPIClient downloadFile throws configured error")
    func mockDownloadFileError() async {
        let mock = MockTGAPIClient()
        await mock.setDownloadFileError(TGAPIError.permanentTelegramError("download failed"))

        do {
            _ = try await mock.downloadFile(filePath: "bad/path.jpg")
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            #expect(error.errorDescription == "download failed")
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    // MARK: - setMyCommands

    @Test("MockTGAPIClient setMyCommands records commands")
    func mockSetMyCommands() async throws {
        let mock = MockTGAPIClient()
        let commands: [(name: String, description: String)] = [
            (name: "help", description: "入门指南"),
            (name: "status", description: "查看状态"),
        ]
        try await mock.setMyCommands(commands: commands)

        let calls = await mock.setMyCommandsCalls
        #expect(calls.count == 1)
        #expect(calls[0].count == 2)
        #expect(calls[0][0].name == "help")
        #expect(calls[0][1].name == "status")
    }

    @Test("setMyCommands API encodes request body correctly")
    func setMyCommandsEncodesBody() async throws {
        let session = MockRecordingURLSession()
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)

        try await client.setMyCommands(commands: [
            (name: "help", description: "guide"),
            (name: "status", description: "status"),
        ])

        let request = try #require(session.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString.contains("setMyCommands") == true)

        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let commands = try #require(json?["commands"] as? [[String: String]])
        #expect(commands.count == 2)
        #expect(commands[0]["command"] == "help")
        #expect(commands[0]["description"] == "guide")
    }
}

/// Mock TGAPIClient for testing TelegramAdapter
actor MockTGAPIClient: TGAPIClientProtocol {
    private var _updates: [TGUpdate] = []
    private var _sentMessages: [(chatId: Int64, text: String, parseMode: TGParseMode?, replyToMessageId: Int64?)] = []
    private var _editedMessages: [(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode)] = []
    private var _getUpdatesError: Error?
    private var _sendMessageError: Error?
    private var _getUpdatesCallCount = 0
    private var _getFileResult: TGFile?
    private var _getFileError: Error?
    private var _downloadFileResult: Data?
    private var _downloadFileError: Error?
    private var _getFileCallCount = 0
    private var _downloadFileCallCount = 0
    private var _editMessageError: Error?
    private var _chatActions: [(chatId: Int64, action: String)] = []
    private var _sendChatActionError: Error?

    var sentMessages: [(chatId: Int64, text: String, parseMode: TGParseMode?, replyToMessageId: Int64?)] { _sentMessages }
    var editedMessages: [(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode)] { _editedMessages }
    var getUpdatesCallCount: Int { _getUpdatesCallCount }
    var getFileCallCount: Int { _getFileCallCount }
    var downloadFileCallCount: Int { _downloadFileCallCount }
    var chatActions: [(chatId: Int64, action: String)] { _chatActions }

    func setUpdates(_ updates: [TGUpdate]) {
        _updates = updates
    }

    func setGetUpdatesError(_ error: Error?) {
        _getUpdatesError = error
    }

    func setSendMessageError(_ error: Error?) {
        _sendMessageError = error
    }

    func setGetFileResult(_ result: TGFile?) {
        _getFileResult = result
    }

    func setGetFileError(_ error: Error?) {
        _getFileError = error
    }

    func setDownloadFileResult(_ data: Data?) {
        _downloadFileResult = data
    }

    func setDownloadFileError(_ error: Error?) {
        _downloadFileError = error
    }

    func setEditMessageError(_ error: Error?) {
        _editMessageError = error
    }

    func setSendChatActionError(_ error: Error?) {
        _sendChatActionError = error
    }

    func getUpdates(offset: Int64?, timeout: Int) async throws -> [TGUpdate] {
        _getUpdatesCallCount += 1
        if let error = _getUpdatesError { throw error }
        // Yield to prevent busy-loop in pollLoop; tests drive state via setUpdates
        try? await _Concurrency.Task.sleep(nanoseconds: 10_000_000) // 10ms
        let result = _updates
        _updates = []
        return result
    }

    func sendMessage(chatId: Int64, text: String) async throws -> TGMessage {
        if let error = _sendMessageError { throw error }
        _sentMessages.append((chatId, text, nil, nil))
        return TGMessage(
            messageId: Int64(_sentMessages.count),
            from: nil,
            chat: TGChat(id: chatId, type: "private"),
            date: 0,
            text: text,
            photo: nil
        )
    }

    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyToMessageId: Int64?) async throws -> TGMessage {
        if let error = _sendMessageError { throw error }
        _sentMessages.append((chatId, text, parseMode, replyToMessageId))
        return TGMessage(
            messageId: Int64(_sentMessages.count),
            from: nil,
            chat: TGChat(id: chatId, type: "private"),
            date: 0,
            text: text,
            photo: nil
        )
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode) async throws -> TGMessage {
        if let error = _editMessageError { throw error }
        _editedMessages.append((chatId, messageId, text, parseMode))
        return TGMessage(
            messageId: messageId,
            from: nil,
            chat: TGChat(id: chatId, type: "private"),
            date: 0,
            text: text,
            photo: nil
        )
    }

    func getFile(fileId: String) async throws -> TGFile {
        _getFileCallCount += 1
        if let error = _getFileError { throw error }
        return _getFileResult ?? TGFile(fileId: fileId, filePath: "photos/file_0.jpg")
    }

    func downloadFile(filePath: String) async throws -> Data {
        _downloadFileCallCount += 1
        if let error = _downloadFileError { throw error }
        return _downloadFileResult ?? Data("fake-image-data".utf8)
    }

    func sendChatAction(chatId: Int64, action: String) async throws {
        if let error = _sendChatActionError { throw error }
        _chatActions.append((chatId, action))
    }

    private var _setMyCommandsCalls: [[(name: String, description: String)]] = []

    var setMyCommandsCalls: [[(name: String, description: String)]] { _setMyCommandsCalls }

    func setMyCommands(commands: [(name: String, description: String)]) async throws {
        _setMyCommandsCalls.append(commands)
    }
}

// MARK: - Mock URLSession (no real network)

/// Always throws a network-level error (URLError.notConnectedToInternet)
final class MockFailingURLSession: URLSessionProtocol, @unchecked Sendable {
    var attemptCount = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        attemptCount += 1
        throw URLError(.notConnectedToInternet)
    }
}

/// Returns an HTTP response with the given status code and empty JSON body
final class MockHTTPErrorURLSession: URLSessionProtocol, @unchecked Sendable {
    let statusCode: Int
    let body: String
    var attemptCount = 0

    init(statusCode: Int, body: String = "{\"ok\":false,\"description\":\"Unauthorized\"}") {
        self.statusCode = statusCode
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        attemptCount += 1
        let url = request.url ?? URL(string: "https://example.com")!
        let httpResp = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        let bodyData = Data(body.utf8)
        return (bodyData, httpResp)
    }
}

/// Records the last request and returns a successful setMyCommands response
final class MockRecordingURLSession: URLSessionProtocol, @unchecked Sendable {
    private(set) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let url = request.url ?? URL(string: "https://example.com")!
        let httpResp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        let body = Data("{\"ok\":true,\"result\":true}".utf8)
        return (body, httpResp)
    }
}
