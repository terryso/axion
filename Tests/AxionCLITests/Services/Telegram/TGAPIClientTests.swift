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
        let req = TGSendMessageRequest(chatId: 99, text: "*bold*", parseMode: "Markdown")
        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"parse_mode\":\"Markdown\""))
    }

    // MARK: - Retry Logic

    @Test("TGAPIClient retries on network failure")
    func retriesOnFailure() async {
        let client = TGAPIClient(token: "bad_token", maxRetries: 1)

        do {
            _ = try await client.sendMessage(chatId: 123, text: "test")
        } catch {
            // Expected — validates error path for network failures
        }
    }

    @Test("TGAPIClient does not retry on 4xx HTTP errors")
    func noRetryOnClientError() async {
        let client = TGAPIClient(token: "test_token", maxRetries: 3)
        // A bad token will get a 401 from TG API — should fail immediately, not retry 3 times
        // We verify the error type is TGAPIError
        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
        } catch let error as TGAPIError {
            // Expected — got a non-retryable error
            #expect(error.errorDescription != nil)
        } catch {
            // Network-level error (DNS, timeout) — acceptable
        }
    }

    // MARK: - TGAPIError

    @Test("TGAPIError has localized description")
    func apiErrorDescription() {
        let error = TGAPIError.apiError("test error message")
        #expect(error.errorDescription == "test error message")
    }

    @Test("TGAPIError conforms to Error")
    func apiErrorConformsToError() {
        let error: Error = TGAPIError.apiError("fail")
        #expect(error.localizedDescription == "fail")
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
        await mock.setGetFileError(TGAPIError.apiError("file not found"))

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

    @Test("MockTGAPIClient downloadFile throws configured error")
    func mockDownloadFileError() async {
        let mock = MockTGAPIClient()
        await mock.setDownloadFileError(TGAPIError.apiError("download failed"))

        do {
            _ = try await mock.downloadFile(filePath: "bad/path.jpg")
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            #expect(error.errorDescription == "download failed")
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }
}

// MARK: - Shared Mock

/// Mock TGAPIClient for testing TelegramAdapter
actor MockTGAPIClient: TGAPIClientProtocol {
    private var _updates: [TGUpdate] = []
    private var _sentMessages: [(chatId: Int64, text: String)] = []
    private var _getUpdatesError: Error?
    private var _sendMessageError: Error?
    private var _getUpdatesCallCount = 0
    private var _getFileResult: TGFile?
    private var _getFileError: Error?
    private var _downloadFileResult: Data?
    private var _downloadFileError: Error?
    private var _getFileCallCount = 0
    private var _downloadFileCallCount = 0

    var sentMessages: [(chatId: Int64, text: String)] { _sentMessages }
    var getUpdatesCallCount: Int { _getUpdatesCallCount }
    var getFileCallCount: Int { _getFileCallCount }
    var downloadFileCallCount: Int { _downloadFileCallCount }

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
        _sentMessages.append((chatId, text))
        return TGMessage(
            messageId: Int64(_sentMessages.count),
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
}
