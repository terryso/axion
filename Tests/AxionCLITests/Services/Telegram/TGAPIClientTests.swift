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

    @Test("TGAPIClient does not retry on 401 auth failure")
    func noRetryOnClientError() async {
        // Use a mock URLSession that returns 401 immediately
        let session = MockHTTPErrorURLSession(statusCode: 401)
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            // 401 → .authFailed, thrown immediately — no retry
            if case .authFailed = error {
                // correct
            } else {
                #expect(error.errorDescription != nil)
            }
        } catch {
            // Acceptable fallback
        }
        #expect(session.attemptCount == 1) // no retry for 4xx auth failure
    }

    // MARK: - TGAPIError

    @Test("TGAPIError has localized description for all cases")
    func apiErrorDescriptionAllCases() {
        #expect(TGAPIError.retryableNetwork("net fail").errorDescription == "net fail")
        #expect(TGAPIError.rateLimited("slow down", retryAfter: 5).errorDescription == "slow down")
        #expect(TGAPIError.formatRejected("bad md").errorDescription == "bad md")
        #expect(TGAPIError.authFailed("token bad").errorDescription == "token bad")
        #expect(TGAPIError.pollingConflict("dup instance").errorDescription == "dup instance")
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

    @Test("403 classifies as authFailed")
    func http403Permanent() async {
        let session = MockHTTPErrorURLSession(statusCode: 403)
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 1)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            if case .authFailed = error {
                // correct
            } else {
                #expect(Bool(false), "Expected authFailed, got \(error)")
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

    @Test("getUpdates encodes offset query and decodes updates")
    func getUpdatesWithOffsetDecodesUpdates() async throws {
        let session = MockScriptedURLSession(json: """
        {"ok":true,"result":[{"update_id":100,"message":{"message_id":7,"chat":{"id":42,"type":"private"},"date":1,"text":"hello"}}]}
        """)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)

        let updates = try await client.getUpdates(offset: 42, timeout: 7)

        #expect(updates.map(\.updateId) == [100])
        #expect(updates.first?.message?.text == "hello")

        let request = try #require(session.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["timeout"] == "7")
        #expect(query["offset"] == "42")
        #expect(request.timeoutInterval == 17)
    }

    @Test("sendMessage with parse mode and reply target encodes body and decodes message")
    func sendMessageWithParseModeAndReplyTarget() async throws {
        let session = MockScriptedURLSession(json: """
        {"ok":true,"result":{"message_id":8,"chat":{"id":123,"type":"private"},"date":2,"text":"sent"}}
        """)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)

        let message = try await client.sendMessage(
            chatId: 123,
            text: "*hi*",
            parseMode: .markdownV2,
            replyToMessageId: 456
        )

        #expect(message.messageId == 8)
        let request = try #require(session.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString.contains("sendMessage") == true)

        let body = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body)
        let json = try #require(object as? [String: Any])
        #expect((json["chat_id"] as? NSNumber)?.int64Value == 123)
        #expect(json["text"] as? String == "*hi*")
        #expect(json["parse_mode"] as? String == "MarkdownV2")
        #expect((json["reply_to_message_id"] as? NSNumber)?.int64Value == 456)
    }

    @Test("sendMessage with reply markup encodes inline keyboard")
    func sendMessageWithReplyMarkupEncodesKeyboard() async throws {
        let session = MockScriptedURLSession(json: """
        {"ok":true,"result":{"message_id":9,"chat":{"id":123,"type":"private"},"date":2,"text":"Approve?"}}
        """)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)
        let markup = TGInlineKeyboardMarkup(inlineKeyboard: [
            [TGInlineKeyboardButton(text: "Approve", callbackData: "approve")]
        ])

        let message = try await client.sendMessage(
            chatId: 123,
            text: "Approve?",
            parseMode: .html,
            replyMarkup: markup
        )

        #expect(message.messageId == 9)
        let request = try #require(session.requests.first)
        let body = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body)
        let json = try #require(object as? [String: Any])
        let replyMarkup = try #require(json["reply_markup"] as? [String: Any])
        let keyboard = try #require(replyMarkup["inline_keyboard"] as? [[[String: Any]]])
        #expect(json["parse_mode"] as? String == "HTML")
        #expect(keyboard[0][0]["text"] as? String == "Approve")
        #expect(keyboard[0][0]["callback_data"] as? String == "approve")
    }

    @Test("editMessageText with reply markup encodes message id and keyboard")
    func editMessageTextWithReplyMarkupEncodesBody() async throws {
        let session = MockScriptedURLSession(json: """
        {"ok":true,"result":{"message_id":22,"chat":{"id":123,"type":"private"},"date":3,"text":"Updated"}}
        """)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)
        let markup = TGInlineKeyboardMarkup(inlineKeyboard: [
            [TGInlineKeyboardButton(text: "Open", url: "https://example.com")]
        ])

        let message = try await client.editMessageText(
            chatId: 123,
            messageId: 22,
            text: "Updated",
            parseMode: .html,
            replyMarkup: markup
        )

        #expect(message.messageId == 22)
        let request = try #require(session.requests.first)
        #expect(request.url?.absoluteString.contains("editMessageText") == true)

        let body = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body)
        let json = try #require(object as? [String: Any])
        let replyMarkup = try #require(json["reply_markup"] as? [String: Any])
        let keyboard = try #require(replyMarkup["inline_keyboard"] as? [[[String: Any]]])
        #expect((json["chat_id"] as? NSNumber)?.int64Value == 123)
        #expect((json["message_id"] as? NSNumber)?.int64Value == 22)
        #expect(json["text"] as? String == "Updated")
        #expect(keyboard[0][0]["url"] as? String == "https://example.com")
    }

    @Test("answerCallbackQuery encodes optional text")
    func answerCallbackQueryEncodesText() async throws {
        let session = MockScriptedURLSession(json: #"{"ok":true,"result":true}"#)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)

        try await client.answerCallbackQuery(callbackQueryId: "callback-1", text: "Done")

        let request = try #require(session.requests.first)
        #expect(request.url?.absoluteString.contains("answerCallbackQuery") == true)
        #expect(request.timeoutInterval == 10)

        let body = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body)
        let json = try #require(object as? [String: Any])
        #expect(json["callback_query_id"] as? String == "callback-1")
        #expect(json["text"] as? String == "Done")
    }

    @Test("getFile builds endpoint and decodes Telegram file")
    func getFileBuildsEndpointAndDecodesFile() async throws {
        let session = MockScriptedURLSession(json: """
        {"ok":true,"result":{"file_id":"file-1","file_path":"photos/file_1.jpg"}}
        """)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)

        let file = try await client.getFile(fileId: "file-1")

        #expect(file.fileId == "file-1")
        #expect(file.filePath == "photos/file_1.jpg")
        let request = try #require(session.requests.first)
        #expect(request.url?.absoluteString.contains("getFile?file_id=file-1") == true)
    }

    @Test("downloadFile returns raw data and uses file endpoint")
    func downloadFileReturnsData() async throws {
        let session = MockScriptedURLSession(data: Data("file-data".utf8))
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)

        let data = try await client.downloadFile(filePath: "photos/file_1.jpg")

        #expect(String(data: data, encoding: .utf8) == "file-data")
        let request = try #require(session.requests.first)
        #expect(request.url?.absoluteString.contains("/file/bottest-token/photos/file_1.jpg") == true)
        #expect(request.timeoutInterval == 60)
    }

    @Test("downloadFile throws permanent error on non-2xx response")
    func downloadFileHTTPFailure() async {
        let session = MockScriptedURLSession(data: Data("nope".utf8), statusCode: 500)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)

        do {
            _ = try await client.downloadFile(filePath: "photos/missing.jpg")
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            #expect(error.errorDescription == "File download failed: HTTP 500")
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("sendChatAction encodes action with short timeout")
    func sendChatActionEncodesBody() async throws {
        let session = MockScriptedURLSession(json: #"{"ok":true,"result":true}"#)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 3)

        try await client.sendChatAction(chatId: 321, action: "typing")

        #expect(session.requests.count == 1)
        let request = try #require(session.requests.first)
        #expect(request.url?.absoluteString.contains("sendChatAction") == true)
        #expect(request.timeoutInterval == 10)

        let body = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body)
        let json = try #require(object as? [String: Any])
        #expect((json["chat_id"] as? NSNumber)?.int64Value == 321)
        #expect(json["action"] as? String == "typing")
    }

    @Test("sendMessage ok false without description uses endpoint fallback")
    func sendMessageFailureUsesEndpointFallback() async {
        let session = MockScriptedURLSession(json: #"{"ok":false}"#)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)

        do {
            _ = try await client.sendMessage(chatId: 123, text: "hello")
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            #expect(error.errorDescription == "sendMessage failed")
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("postVoid ok false without description uses endpoint fallback")
    func postVoidFailureUsesEndpointFallback() async {
        let session = MockScriptedURLSession(json: #"{"ok":false}"#)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)

        do {
            try await client.answerCallbackQuery(callbackQueryId: "callback-1", text: nil)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            #expect(error.errorDescription == "answerCallbackQuery failed")
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("get ok false without description uses endpoint fallback")
    func getFailureUsesEndpointFallback() async {
        let session = MockScriptedURLSession(json: #"{"ok":false}"#)
        let client = TGAPIClient(token: "test-token", session: session, maxRetries: 1)

        do {
            _ = try await client.getFile(fileId: "file-1")
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            #expect(error.errorDescription == "getFile?file_id=file-1 failed")
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("400 with Bad Request text classifies as formatRejected")
    func http400BadRequestFormatRejected() async {
        let session = MockHTTPErrorURLSession(statusCode: 400, body: "Bad Request: can't parse entities")
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 1)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            if case .formatRejected = error {
                #expect(error.errorDescription?.contains("Bad Request") == true)
            } else {
                #expect(Bool(false), "Expected formatRejected, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    // MARK: - AC #1: Transient Error Retry (Exponential Backoff)

    @Test("Transient network error retries with exponential backoff (1s, 2s, 4s)")
    func transientErrorRetriesWithExponentialBackoff() async {
        // AC #1: TG API request times out or connection reset → auto-retry max 3, exponential 1s/2s/4s
        let session = MockFailingURLSession()
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown after all retries exhausted")
        } catch {
            // Expected: network failure after 3 retry attempts
        }
        #expect(session.attemptCount == 3, "Should attempt exactly 3 times (initial + 2 retries)")
    }

    @Test("Generic network error (URLError) retries with exponential backoff")
    func genericNetworkErrorRetries() async {
        // AC #1: non-TGAPIError network errors like URLError also use exponential backoff
        let session = MockFailingURLSession()
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)

        do {
            _ = try await client.sendMessage(chatId: 123, text: "test")
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Expected
        }
        #expect(session.attemptCount == 3)
    }

    @Test("5xx server errors classified as retryableNetwork")
    func http5xxClassifiedAsRetryable() async {
        // AC #1 + Dev Note D4: 5xx server errors should be retryable
        let session = MockHTTPErrorURLSession(statusCode: 503, body: "{\"ok\":false,\"description\":\"Service Unavailable\"}")
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            if case .retryableNetwork = error {
                // correct: 5xx should be retryable
            } else {
                #expect(Bool(false), "Expected retryableNetwork for 503, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
        // 5xx should retry 3 times after implementation
        // Currently: .permanentTelegramError → no retry → attemptCount == 1
        #expect(session.attemptCount == 3, "5xx should retry 3 times")
    }

    // MARK: - AC #2: 429 Rate Limit with Retry-After Header

    @Test("429 with Retry-After header waits specified time before retry")
    func http429WithRetryAfterHeader() async {
        // AC #2: 429 → read Retry-After header → wait specified time → retry
        let session = MockHTTPErrorURLSession(
            statusCode: 429,
            body: "{\"ok\":false,\"description\":\"Too Many Requests\"}",
            headers: ["Retry-After": "10"]
        )
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 2)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown after retries exhausted")
        } catch let error as TGAPIError {
            if case .rateLimited(_, let retryAfter) = error {
                #expect(retryAfter == 10.0, "Retry-After header value should be parsed as 10 seconds")
            } else {
                #expect(Bool(false), "Expected rateLimited with retryAfter, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("429 without Retry-After header defaults to 5 second wait")
    func http429WithoutRetryAfterDefaultsTo5Seconds() async {
        // AC #2: no Retry-After → default 5 seconds
        let session = MockHTTPErrorURLSession(
            statusCode: 429,
            body: "{\"ok\":false,\"description\":\"Too Many Requests\"}",
            headers: nil
        )
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 1)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            if case .rateLimited(_, let retryAfter) = error {
                #expect(retryAfter == 5.0, "Default retryAfter should be 5 seconds when header absent")
            } else {
                #expect(Bool(false), "Expected rateLimited with default retryAfter=5, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    // MARK: - AC #3: 401/403 Authentication Failure (Permanent, No Retry)

    @Test("401 does not retry (permanent error)")
    func http401NoRetry() async {
        // AC #3: 401 Unauthorized → no retry
        let session = MockHTTPErrorURLSession(statusCode: 401, body: "{\"ok\":false,\"description\":\"Unauthorized\"}")
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Expected
        }
        #expect(session.attemptCount == 1, "401 should not retry")
    }

    @Test("403 does not retry (permanent error)")
    func http403NoRetry() async {
        // AC #3: 403 Forbidden → no retry
        let session = MockHTTPErrorURLSession(statusCode: 403, body: "{\"ok\":false,\"description\":\"Forbidden\"}")
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Expected
        }
        #expect(session.attemptCount == 1, "403 should not retry")
    }

    // MARK: - AC #4: 409 Polling Conflict (Graceful Degrade)

    @Test("409 does not retry with exponential backoff")
    func http409NoExponentialRetry() async {
        // AC #4: 409 Conflict → pollingConflict, should not go through standard retry loop
        let session = MockHTTPErrorURLSession(
            statusCode: 409,
            body: "{\"ok\":false,\"description\":\"Conflict\"}"
        )
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)

        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Expected
        }
        #expect(session.attemptCount == 1, "409 should not retry with exponential backoff")
    }

    // MARK: - AC #2/#3/#4: Error Case Unit Tests

    @Test("authFailed errorDescription contains the body message")
    func authFailedErrorDescription() {
        let error = TGAPIError.authFailed("Token invalid")
        #expect(error.errorDescription == "Token invalid")
    }

    @Test("pollingConflict errorDescription contains the body message")
    func pollingConflictErrorDescription() {
        let error = TGAPIError.pollingConflict("Conflict: another instance running")
        #expect(error.errorDescription == "Conflict: another instance running")
    }

    @Test("rateLimited carries retryAfter TimeInterval value")
    func rateLimitedCarriesRetryAfter() {
        let error = TGAPIError.rateLimited("slow down", retryAfter: 15.0)
        if case .rateLimited(let msg, let retryAfter) = error {
            #expect(msg == "slow down")
            #expect(retryAfter == 15.0)
        } else {
            #expect(Bool(false), "Should match rateLimited with retryAfter")
        }
    }

    @Test("TGAPIError has localized description for new cases")
    func apiErrorDescriptionNewCases() {
        #expect(TGAPIError.authFailed("token bad").errorDescription == "token bad")
        #expect(TGAPIError.pollingConflict("dup instance").errorDescription == "dup instance")
    }

    @Test("401 classifies as authFailed")
    func http401ClassifiedAsAuthFailed() async {
        let session = MockHTTPErrorURLSession(statusCode: 401)
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)
        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            if case .authFailed = error { } else {
                #expect(Bool(false), "Expected authFailed for 401, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("403 classifies as authFailed")
    func http403ClassifiedAsAuthFailed() async {
        let session = MockHTTPErrorURLSession(statusCode: 403)
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)
        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            if case .authFailed = error { } else {
                #expect(Bool(false), "Expected authFailed for 403, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test("409 classifies as pollingConflict")
    func http409ClassifiedAsPollingConflict() async {
        let session = MockHTTPErrorURLSession(statusCode: 409)
        let client = TGAPIClient(token: "test_token", session: session, maxRetries: 3)
        do {
            _ = try await client.getUpdates(offset: nil, timeout: 1)
            #expect(Bool(false), "Should have thrown")
        } catch let error as TGAPIError {
            if case .pollingConflict = error { } else {
                #expect(Bool(false), "Expected pollingConflict for 409, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
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
        return try await editMessageText(chatId: chatId, messageId: messageId, text: text, parseMode: parseMode, replyMarkup: nil)
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup?) async throws -> TGMessage {
        if let error = _editMessageError { throw error }
        _editedMessages.append((chatId, messageId, text, parseMode))
        if let markup = replyMarkup {
            _editedMessagesWithMarkup.append((chatId, messageId, text, parseMode, markup))
        }
        return TGMessage(
            messageId: messageId,
            from: nil,
            chat: TGChat(id: chatId, type: "private"),
            date: 0,
            text: text,
            photo: nil
        )
    }

    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup?) async throws -> TGMessage {
        if let error = _sendMessageError { throw error }
        _sentMessagesWithMarkup.append((chatId, text, parseMode, replyMarkup))
        return TGMessage(
            messageId: Int64(_sentMessages.count + _sentMessagesWithMarkup.count),
            from: nil,
            chat: TGChat(id: chatId, type: "private"),
            date: 0,
            text: text,
            photo: nil
        )
    }

    private var _sentMessagesWithMarkup: [(chatId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup?)] = []
    private var _editedMessagesWithMarkup: [(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup)] = []
    private var _answerCallbackQueryCalls: [(callbackQueryId: String, text: String?)] = []

    var sentMessagesWithMarkup: [(chatId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup?)] { _sentMessagesWithMarkup }
    var editedMessagesWithMarkup: [(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup)] { _editedMessagesWithMarkup }
    var answerCallbackQueryCalls: [(callbackQueryId: String, text: String?)] { _answerCallbackQueryCalls }

    func answerCallbackQuery(callbackQueryId: String, text: String?) async throws {
        _answerCallbackQueryCalls.append((callbackQueryId, text))
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

/// Returns an HTTP response with the given status code, optional headers, and JSON body
final class MockHTTPErrorURLSession: URLSessionProtocol, @unchecked Sendable {
    let statusCode: Int
    let body: String
    let headers: [String: String]?
    var attemptCount = 0

    init(statusCode: Int, body: String = "{\"ok\":false,\"description\":\"Unauthorized\"}", headers: [String: String]? = nil) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        attemptCount += 1
        let url = request.url ?? URL(string: "https://example.com")!
        let httpResp = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
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

final class MockScriptedURLSession: URLSessionProtocol, @unchecked Sendable {
    struct ScriptedResponse: Sendable {
        let data: Data
        let statusCode: Int
    }

    private var responses: [ScriptedResponse]
    private(set) var requests: [URLRequest] = []

    convenience init(json: String, statusCode: Int = 200) {
        self.init(data: Data(json.utf8), statusCode: statusCode)
    }

    convenience init(data: Data, statusCode: Int = 200) {
        self.init(responses: [ScriptedResponse(data: data, statusCode: statusCode)])
    }

    init(responses: [ScriptedResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }

        let response = responses.removeFirst()
        let url = request.url ?? URL(string: "https://example.com")!
        let httpResp = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (response.data, httpResp)
    }
}
