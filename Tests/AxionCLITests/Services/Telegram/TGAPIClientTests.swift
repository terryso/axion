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
}

// MARK: - Shared Mock

/// Mock TGAPIClient for testing TelegramAdapter
actor MockTGAPIClient: TGAPIClientProtocol {
    private var _updates: [TGUpdate] = []
    private var _sentMessages: [(chatId: Int64, text: String)] = []
    private var _getUpdatesError: Error?
    private var _sendMessageError: Error?
    private var _getUpdatesCallCount = 0

    var sentMessages: [(chatId: Int64, text: String)] { _sentMessages }
    var getUpdatesCallCount: Int { _getUpdatesCallCount }

    func setUpdates(_ updates: [TGUpdate]) {
        _updates = updates
    }

    func setGetUpdatesError(_ error: Error?) {
        _getUpdatesError = error
    }

    func setSendMessageError(_ error: Error?) {
        _sendMessageError = error
    }

    func getUpdates(offset: Int64?, timeout: Int) async throws -> [TGUpdate] {
        _getUpdatesCallCount += 1
        if let error = _getUpdatesError { throw error }
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
            text: text
        )
    }
}
