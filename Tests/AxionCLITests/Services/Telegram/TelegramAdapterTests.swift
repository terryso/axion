import Testing
import Foundation
@testable import AxionCLI

// MARK: - Mock TaskSerialQueue

actor MockTaskSerialQueue: TaskSerialQueueProtocol {
    private var enqueuedTasks: [(task: String, chatId: Int64)] = []
    private var _startProcessingCalled = false
    private var _cancelAllCalled = false
    private var _pendingCount = 0
    private var _isProcessing = false

    var startProcessingCalled: Bool { _startProcessingCalled }
    var cancelAllCalled: Bool { _cancelAllCalled }
    var tasks: [(task: String, chatId: Int64)] { enqueuedTasks }

    func enqueue(task: String, chatId: Int64) async {
        enqueuedTasks.append((task, chatId))
    }

    func startProcessing() async {
        _startProcessingCalled = true
    }

    func cancelAll() async {
        _cancelAllCalled = true
        enqueuedTasks.removeAll()
    }

    var pendingCount: Int { _pendingCount }
    var isProcessing: Bool { _isProcessing }
}

@Suite("TelegramAdapter")
struct TelegramAdapterTests {

    // MARK: - Authorization (AC #3)

    @Test("Authorized user passes whitelist check")
    func authorizedUserPasses() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123", "456"])

        // Send a message from authorized user
        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 123, type: "private"),
            date: 0,
            text: "hello"
        ))
        await mock.setUpdates([update])

        // Start adapter briefly to process one update
        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        await adapter.stop()

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].chatId == 123)
    }

    @Test("Unauthorized user is silently discarded")
    func unauthorizedUserDiscarded() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"])

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 999, firstName: "Stranger", lastName: nil, username: nil),
            chat: TGChat(id: 999, type: "private"),
            date: 0,
            text: "hello"
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        await adapter.stop()

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    @Test("Message without user is discarded")
    func messageWithoutUserDiscarded() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"])

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: nil,
            chat: TGChat(id: 123, type: "private"),
            date: 0,
            text: "hello"
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        await adapter.stop()

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    @Test("Message without text is discarded")
    func messageWithoutTextDiscarded() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"])

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 123, type: "private"),
            date: 0,
            text: nil
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        await adapter.stop()

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    // MARK: - Message Splitting (AC #4)

    @Test("Short message is not split")
    func shortMessageNotSplit() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"])

        await adapter.sendReply("short message", to: 123)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "short message")
    }

    @Test("Message over 4096 chars is split")
    func longMessageSplit() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"])

        let longText = String(repeating: "A", count: 5000)
        await adapter.sendReply(longText, to: 123)

        let sent = await mock.sentMessages
        #expect(sent.count == 2)
        #expect(sent[0].text.count <= 4096)
        #expect(sent[1].text.count <= 4096)
        // Total content preserved
        let total = sent.map(\.text).joined()
        #expect(total == longText)
    }

    @Test("Long message splits at newline boundaries")
    func splitAtNewlines() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"])

        // 4090 chars + newline + 10 chars + newline + 10 chars = 4112
        let line1 = String(repeating: "A", count: 4090)
        let line2 = String(repeating: "B", count: 10)
        let line3 = String(repeating: "C", count: 10)
        let text = "\(line1)\n\(line2)\n\(line3)"

        await adapter.sendReply(text, to: 123)

        let sent = await mock.sentMessages
        #expect(sent.count == 2)
        #expect(sent[0].text == "\(line1)\n")
        #expect(sent[1].text == "\(line2)\n\(line3)")
    }

    @Test("Exactly 4096 chars is not split")
    func exactlyMaxLengthNotSplit() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"])

        let text = String(repeating: "X", count: 4096)
        await adapter.sendReply(text, to: 123)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
    }

    // MARK: - Status Info (AC #7)

    @Test("Initial status is disabled")
    func initialStatusDisabled() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: [])

        #expect(adapter.statusValue == "disabled")
    }

    @Test("Status becomes connected after start")
    func statusConnectedAfterStart() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: [])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        #expect(adapter.statusValue == "connected")

        await adapter.stop()
    }

    @Test("Status becomes error when getUpdates fails")
    func statusErrorOnFailure() async {
        let mock = MockTGAPIClient()
        await mock.setGetUpdatesError(TGAPIError.apiError("network failure"))
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: [])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        #expect(adapter.statusValue.hasPrefix("error:"))

        await adapter.stop()
    }

    // MARK: - Stop (AC #1)

    @Test("Stop prevents further polling")
    func stopPreventsPolling() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: [])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        await adapter.stop()
        let countBefore = await mock.getUpdatesCallCount

        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        let countAfter = await mock.getUpdatesCallCount

        #expect(countAfter == countBefore)
    }

    // MARK: - Token Missing (AC #5)

    @Test("sendReply handles sendMessage failure gracefully")
    func sendReplyHandlesFailure() async {
        let mock = MockTGAPIClient()
        await mock.setSendMessageError(TGAPIError.apiError("rate limited"))
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"])

        // Should not throw - errors are caught internally
        await adapter.sendReply("test", to: 123)

        let sent = await mock.sentMessages
        #expect(sent.isEmpty) // Failed, so no successful sends
    }

    // MARK: - Task Queue Integration (AC #1, #2, #8)

    @Test("Text message submits to task queue")
    func textMessageSubmitsToQueue() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue)

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "do something"
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
        #expect(tasks[0].task == "do something")
        #expect(tasks[0].chatId == 456)

        // No direct reply sent — queue handles notifications
        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    @Test("Empty text message is silently ignored")
    func emptyTextMessageIgnored() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue)

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: ""
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)
    }

    @Test("Non-text message is silently ignored")
    func nonTextMessageIgnored() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue)

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: nil
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)
    }

    @Test("Without queue falls back to MVP reply")
    func withoutQueueFallsBackToMVP() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"])

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "hello"
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "任务已收到")
    }
}
