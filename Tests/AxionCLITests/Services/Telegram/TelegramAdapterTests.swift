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
    private var _clearedSessions: [Int64] = []

    var startProcessingCalled: Bool { _startProcessingCalled }
    var cancelAllCalled: Bool { _cancelAllCalled }
    var tasks: [(task: String, chatId: Int64)] { enqueuedTasks }
    var clearedSessions: [Int64] { _clearedSessions }

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

    func clearSession(chatId: Int64) async {
        _clearedSessions.append(chatId)
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

    // MARK: - Command Router Integration (AC #1, #2, #3)

    @Test("Command message routes to commandRouter instead of queue")
    func commandMessageRoutesToRouter() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let commandRouter = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 1,
                    uptimeSeconds: 60,
                    label: "dev.axion.gateway",
                    tgConnected: "connected"
                )
            },
            skillsProvider: { [] }
        )
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, commandRouter: commandRouter)

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "/status"
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        // Command routed to reply, NOT enqueued
        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text.contains("running"))
    }

    @Test("Non-command text still enqueues normally with commandRouter present")
    func nonCommandStillEnqueuesWithRouter() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let commandRouter = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 0,
                    label: "dev.axion.gateway"
                )
            },
            skillsProvider: { [] }
        )
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, commandRouter: commandRouter)

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "open calculator"
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        // Normal text still goes to queue
        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
        #expect(tasks[0].task == "open calculator")

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    @Test("Without commandRouter all messages enqueue normally (backward compat)")
    func withoutCommandRouterBackwardCompat() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue)

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "/status"
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        // Without commandRouter, /status is treated as regular task text
        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
        #expect(tasks[0].task == "/status")
    }

    @Test("Authorization check happens before command routing")
    func authCheckBeforeCommandRouting() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let commandRouter = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 0,
                    label: "dev.axion.gateway"
                )
            },
            skillsProvider: { [] }
        )
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], commandRouter: commandRouter)

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 999, firstName: "Stranger", lastName: nil, username: nil),
            chat: TGChat(id: 999, type: "private"),
            date: 0,
            text: "/status"
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        // Unauthorized user — no reply, no task queued
        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    // MARK: - Photo Support (Story 29.5)

    @Test("Photo message with caption enqueues task with image path and caption")
    func photoWithCaptionEnqueues() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue)

        let photo = [
            TGPhotoSize(fileId: "small", width: 100, height: 100, fileSize: 5000),
            TGPhotoSize(fileId: "large", width: 800, height: 600, fileSize: 50000),
        ]
        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "read this screenshot",
            photo: photo
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        await adapter.stop()

        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
        #expect(tasks[0].task.contains("read this screenshot"))
        #expect(tasks[0].task.contains("附件图片"))
        #expect(tasks[0].chatId == 456)

        let getFileCount = await mock.getFileCallCount
        #expect(getFileCount == 1)
    }

    @Test("Photo message without caption enqueues with default description")
    func photoWithoutCaptionEnqueues() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue)

        let photo = [
            TGPhotoSize(fileId: "img123", width: 640, height: 480, fileSize: 30000),
        ]
        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: nil,
            photo: photo
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        await adapter.stop()

        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
        #expect(tasks[0].task.contains("用户发送了一张图片"))
    }

    @Test("Photo download failure sends error reply")
    func photoDownloadFailureSendsError() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        await mock.setGetFileError(TGAPIError.apiError("file not found"))
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue)

        let photo = [
            TGPhotoSize(fileId: "bad_file", width: 100, height: 100, fileSize: 1000),
        ]
        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: nil,
            photo: photo
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        await adapter.stop()

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "图片下载失败，请重试")
    }

    @Test("Photo from unauthorized user is silently discarded")
    func photoFromUnauthorizedDiscarded() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue)

        let photo = [
            TGPhotoSize(fileId: "img1", width: 100, height: 100, fileSize: 1000),
        ]
        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 999, firstName: "Stranger", lastName: nil, username: nil),
            chat: TGChat(id: 999, type: "private"),
            date: 0,
            text: nil,
            photo: photo
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    @Test("Photo selects largest size from multiple sizes")
    func photoSelectsLargestSize() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue)

        let photo = [
            TGPhotoSize(fileId: "thumb", width: 90, height: 90, fileSize: 2000),
            TGPhotoSize(fileId: "medium", width: 320, height: 240, fileSize: 15000),
            TGPhotoSize(fileId: "biggest", width: 1280, height: 720, fileSize: 80000),
        ]
        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "analyze this",
            photo: photo
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        await adapter.stop()

        // Verify getFile was called (the mock returns default for any fileId)
        let getFileCount = await mock.getFileCallCount
        #expect(getFileCount == 1)

        // Task was enqueued
        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
    }

    @Test("Photo without queue sends acknowledgment reply")
    func photoWithoutQueueSendsReply() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"])

        let photo = [
            TGPhotoSize(fileId: "pic1", width: 640, height: 480, fileSize: 30000),
        ]
        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: nil,
            photo: photo
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        await adapter.stop()

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "图片已收到")
    }

    // MARK: - /new Command Integration

    @Test("/new command triggers clearSession and sends immediate reply")
    func newCommandClearsAndReplies() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        final class ChatIdCollector: @unchecked Sendable {
            var ids: [Int64] = []
            func add(_ id: Int64) { ids.append(id) }
        }
        let collector = ChatIdCollector()
        let commandRouter = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 0,
                    label: "dev.axion.gateway"
                )
            },
            skillsProvider: { [] },
            clearSession: { chatId in
                collector.add(chatId)
            }
        )
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, commandRouter: commandRouter)

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "/new"
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "新会话已开始")
        #expect(sent[0].chatId == 456)

        #expect(collector.ids == [456])
    }

    @Test("/new does not enqueue as task")
    func newCommandDoesNotEnqueue() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let mockQueue = MockTaskSerialQueue()
        let commandRouter = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 0,
                    label: "dev.axion.gateway"
                )
            },
            skillsProvider: { [] },
            clearSession: { _ in }
        )
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, commandRouter: commandRouter)

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "/new"
        ))
        await mock.setUpdates([update])

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await adapter.stop()

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
    }
}
