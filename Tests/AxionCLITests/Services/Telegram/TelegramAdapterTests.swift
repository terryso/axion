import Testing
import Foundation
@testable import AxionCLI

// MARK: - Mock TaskSerialQueue

actor MockTaskSerialQueue: TaskSerialQueueProtocol {
    private var enqueuedTasks: [(task: String, chatId: Int64, userId: Int64)] = []
    private var _startProcessingCalled = false
    private var _cancelAllCalled = false
    private var _pendingCount = 0
    private var _isProcessing = false
    private var _clearedSessions: [Int64] = []

    var startProcessingCalled: Bool { _startProcessingCalled }
    var cancelAllCalled: Bool { _cancelAllCalled }
    var tasks: [(task: String, chatId: Int64, userId: Int64)] { enqueuedTasks }
    var clearedSessions: [Int64] { _clearedSessions }

    func enqueue(task: String, chatId: Int64, userId: Int64) async {
        enqueuedTasks.append((task, chatId, userId))
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

    func cancelCurrentTask(chatId: Int64) -> Bool { false }

    var pendingCount: Int { _pendingCount }
    var isProcessing: Bool { _isProcessing }

    private var _activeSessions: Set<Int64> = []

    func pendingCount(chatId: Int64) async -> Int { _pendingCount }
    func isProcessing(chatId: Int64) async -> Bool { _isProcessing }
    func hasActiveSession(chatId: Int64) async -> Bool { _activeSessions.contains(chatId) }

    func setActiveSession(_ chatId: Int64) { _activeSessions.insert(chatId) }

    private var _resumeHandles: [String: @Sendable (String) async -> Void] = [:]
    private var _resumeCalls: [(pendingId: String, context: String)] = []

    var resumeCalls: [(pendingId: String, context: String)] { _resumeCalls }

    func registerResumeHandle(pendingId: String, handle: @Sendable @escaping (String) async -> Void) {
        _resumeHandles[pendingId] = handle
    }

    func resumeInteraction(pendingId: String, context: String) async -> Bool {
        guard let handle = _resumeHandles.removeValue(forKey: pendingId) else { return false }
        _resumeCalls.append((pendingId, context))
        await handle(context)
        return true
    }
}

@Suite("TelegramAdapter")
struct TelegramAdapterTests {

    // MARK: - Authorization (AC #3)

    @Test("Authorized user passes whitelist check")
    func authorizedUserPasses() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123", "456"], log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 123, type: "private"),
            date: 0,
            text: "hello"
        ))
        await adapter.processUpdates([update])

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].chatId == 123)
    }

    @Test("Unauthorized user is silently discarded")
    func unauthorizedUserDiscarded() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 999, firstName: "Stranger", lastName: nil, username: nil),
            chat: TGChat(id: 999, type: "private"),
            date: 0,
            text: "hello"
        ))
        await adapter.processUpdates([update])

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    @Test("Message without user is discarded")
    func messageWithoutUserDiscarded() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: nil,
            chat: TGChat(id: 123, type: "private"),
            date: 0,
            text: "hello"
        ))
        await adapter.processUpdates([update])

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    @Test("Message without text is discarded")
    func messageWithoutTextDiscarded() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 123, type: "private"),
            date: 0,
            text: nil
        ))
        await adapter.processUpdates([update])

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    // MARK: - Message Splitting (AC #4)

    @Test("Short message is not split")
    func shortMessageNotSplit() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        await adapter.sendReply("short message", to: 123)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "short message")
    }

    @Test("Message over 4096 chars is split")
    func longMessageSplit() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        let longText = String(repeating: "A", count: 5000)
        await adapter.sendReply(longText, to: 123)

        let sent = await mock.sentMessages
        #expect(sent.count == 2)
        #expect(sent[0].text.count <= 4096)
        #expect(sent[1].text.count <= 4096)
        let total = sent.map(\.text).joined()
        #expect(total == longText)
    }

    @Test("Long message splits at newline boundaries")
    func splitAtNewlines() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

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
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        let text = String(repeating: "X", count: 4096)
        await adapter.sendReply(text, to: 123)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
    }

    // MARK: - Status Info (AC #7)

    @Test("Initial status is disabled")
    func initialStatusDisabled() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: [], log: { _ in })

        #expect(adapter.statusValue == "disabled")
    }

    @Test("Status becomes connected after start")
    func statusConnectedAfterStart() async {
        let mock = MockTGAPIClient()
        await mock.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: [], log: { _ in })

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        #expect(adapter.statusValue == "connected")

        await adapter.stop()
    }

    @Test("Status becomes error when getUpdates fails")
    func statusErrorOnFailure() async {
        let mock = MockTGAPIClient()
        await mock.setGetUpdatesError(TGAPIError.retryableNetwork("network failure"))
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: [], log: { _ in })

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
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: [], log: { _ in })

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
        await mock.setSendMessageError(TGAPIError.permanentTelegramError("rate limited"))
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        await adapter.sendReply("test", to: 123)

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    // MARK: - Task Queue Integration (AC #1, #2, #8)

    @Test("Text message submits to task queue")
    func textMessageSubmitsToQueue() async {
        let mock = MockTGAPIClient()
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "do something"
        ))
        await adapter.processUpdates([update])

        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
        #expect(tasks[0].task == "do something")
        #expect(tasks[0].chatId == 456)

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    @Test("Empty text message is silently ignored")
    func emptyTextMessageIgnored() async {
        let mock = MockTGAPIClient()
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: ""
        ))
        await adapter.processUpdates([update])

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)
    }

    @Test("Non-text message is silently ignored")
    func nonTextMessageIgnored() async {
        let mock = MockTGAPIClient()
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: nil
        ))
        await adapter.processUpdates([update])

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)
    }

    @Test("Without queue falls back to MVP reply")
    func withoutQueueFallsBackToMVP() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "hello"
        ))
        await adapter.processUpdates([update])

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "任务已收到")
    }

    // MARK: - Command Router Integration (AC #1, #2, #3)

    @Test("Command message routes to commandRouter instead of queue")
    func commandMessageRoutesToRouter() async {
        let mock = MockTGAPIClient()
        let mockQueue = MockTaskSerialQueue()
        let commandRouter = TGCommandRouter(registry: makeTestRegistry())
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, commandRouter: commandRouter, log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "/status"
        ))
        await adapter.processUpdates([update])

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text.contains("running"))
    }

    @Test("Non-command text still enqueues normally with commandRouter present")
    func nonCommandStillEnqueuesWithRouter() async {
        let mock = MockTGAPIClient()
        let mockQueue = MockTaskSerialQueue()
        let commandRouter = TGCommandRouter(registry: makeTestRegistry())
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, commandRouter: commandRouter, log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "open calculator"
        ))
        await adapter.processUpdates([update])

        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
        #expect(tasks[0].task == "open calculator")

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    @Test("Without commandRouter all messages enqueue normally (backward compat)")
    func withoutCommandRouterBackwardCompat() async {
        let mock = MockTGAPIClient()
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "/status"
        ))
        await adapter.processUpdates([update])

        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
        #expect(tasks[0].task == "/status")
    }

    @Test("Authorization check happens before command routing")
    func authCheckBeforeCommandRouting() async {
        let mock = MockTGAPIClient()
        let commandRouter = TGCommandRouter(registry: makeTestRegistry())
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], commandRouter: commandRouter, log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 999, firstName: "Stranger", lastName: nil, username: nil),
            chat: TGChat(id: 999, type: "private"),
            date: 0,
            text: "/status"
        ))
        await adapter.processUpdates([update])

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    // MARK: - Photo Support (Story 29.5)

    @Test("Photo message with caption enqueues task with image path and caption")
    func photoWithCaptionEnqueues() async {
        let mock = MockTGAPIClient()
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, log: { _ in })

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
        await adapter.processUpdates([update])

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
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, log: { _ in })

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
        await adapter.processUpdates([update])

        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
        #expect(tasks[0].task.contains("用户发送了一张图片"))
    }

    @Test("Photo download failure sends error reply")
    func photoDownloadFailureSendsError() async {
        let mock = MockTGAPIClient()
        await mock.setGetFileError(TGAPIError.permanentTelegramError("file not found"))
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, log: { _ in })

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
        await adapter.processUpdates([update])

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "图片下载失败，请重试")
    }

    @Test("Photo from unauthorized user is silently discarded")
    func photoFromUnauthorizedDiscarded() async {
        let mock = MockTGAPIClient()
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, log: { _ in })

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
        await adapter.processUpdates([update])

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)

        let sent = await mock.sentMessages
        #expect(sent.isEmpty)
    }

    @Test("Photo selects largest size from multiple sizes")
    func photoSelectsLargestSize() async {
        let mock = MockTGAPIClient()
        let mockQueue = MockTaskSerialQueue()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, log: { _ in })

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
        await adapter.processUpdates([update])

        let getFileCount = await mock.getFileCallCount
        #expect(getFileCount == 1)

        let tasks = await mockQueue.tasks
        #expect(tasks.count == 1)
    }

    @Test("Photo without queue sends acknowledgment reply")
    func photoWithoutQueueSendsReply() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

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
        await adapter.processUpdates([update])

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "图片已收到")
    }

    // MARK: - /new Command Integration

    @Test("/new command triggers clearSession and sends immediate reply")
    func newCommandClearsAndReplies() async {
        let mock = MockTGAPIClient()
        let mockQueue = MockTaskSerialQueue()
        final class ChatIdCollector: @unchecked Sendable {
            var ids: [Int64] = []
            func add(_ id: Int64) { ids.append(id) }
        }
        let collector = ChatIdCollector()
        let commandRouter = TGCommandRouter(registry: makeTestRegistry(clearSession: { chatId in
            collector.add(chatId)
        }))
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, commandRouter: commandRouter, log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "/new"
        ))
        await adapter.processUpdates([update])

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
        let mockQueue = MockTaskSerialQueue()
        let registry = TGCommandRegistry(commands: [
            TGCommandDef(name: "new", description: "开始新会话", helpText: "", menuPriority: 5) { _ in "新会话已开始" }
        ])
        let commandRouter = TGCommandRouter(registry: registry)
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], taskQueue: mockQueue, commandRouter: commandRouter, log: { _ in })

        let update = TGUpdate(updateId: 1, message: TGMessage(
            messageId: 1,
            from: TGUser(id: 123, firstName: "Nick", lastName: nil, username: nil),
            chat: TGChat(id: 456, type: "private"),
            date: 0,
            text: "/new"
        ))
        await adapter.processUpdates([update])

        let tasks = await mockQueue.tasks
        #expect(tasks.isEmpty)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
    }

    // MARK: - Formatted Sending (Story 32.1)

    @Test("sendFormatted sends with MarkdownV2 parse mode")
    func sendFormattedUsesMarkdownV2() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        await adapter.sendFormatted("# Hello", to: 456)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].parseMode == .markdownV2)
        #expect(sent[0].chatId == 456)
    }

    @Test("sendFormatted with replyToMessageId passes it on first chunk only")
    func sendFormattedReplyFirstChunk() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        let longText = String(repeating: "A", count: 5000)
        await adapter.sendFormatted(longText, to: 456, replyToMessageId: 789)

        let sent = await mock.sentMessages
        #expect(sent.count >= 2)
        #expect(sent[0].replyToMessageId == 789)
        #expect(sent[1].replyToMessageId == nil)
    }

    @Test("sendFormatted falls back from MDv2 to HTML on formatRejected")
    func sendFormattedFallbackToHTML() async {
        let mock = MockFallbackTGAPIClient()
        // First call (MDv2) throws formatRejected, second (HTML) succeeds
        await mock.setNextError(TGAPIError.formatRejected("can't parse entities"))
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        await adapter.sendFormatted("# Hello", to: 456)

        let sent = await mock.sentMessages
        #expect(sent.count == 1)
        // Should have retried with HTML
        #expect(sent[0].parseMode == .html)
    }

    @Test("sendFormatted fallback does not duplicate already-sent chunks")
    func sendFormattedFallbackNoDuplicates() async {
        let mock = MockMultiChunkFallbackTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        // Text long enough to produce 2+ chunks; mock fails on second chunk
        let longText = String(repeating: "A", count: 5000)
        await adapter.sendFormatted(longText, to: 456)

        let sent = await mock.sentMessages
        // First chunk (MDv2) sent successfully, then second fails → fallback sends
        // only the second chunk as HTML. No duplicates.
        let mdv2Sent = sent.filter { $0.parseMode == .markdownV2 }
        let htmlSent = sent.filter { $0.parseMode == .html }
        #expect(mdv2Sent.count == 1) // only first chunk in MDv2
        #expect(htmlSent.count == 1) // only second chunk in HTML
    }

    // MARK: - editMessage (Story 32.2)

    @Test("editMessage returns true on success")
    func editMessageReturnsTrueOnSuccess() async {
        let mock = MockTGAPIClient()
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        let result = await adapter.editMessage(chatId: 123, messageId: 42, text: "edited")
        #expect(result == true)

        let edited = await mock.editedMessages
        #expect(edited.count == 1)
        #expect(edited[0].chatId == 123)
        #expect(edited[0].messageId == 42)
    }

    @Test("editMessage returns false on permanent error")
    func editMessageReturnsFalseOnPermanentError() async {
        let mock = MockTGAPIClient()
        await mock.setEditMessageError(TGAPIError.permanentTelegramError("message not found"))
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        let result = await adapter.editMessage(chatId: 123, messageId: 99, text: "fail")
        #expect(result == false)
    }

    @Test("editMessage returns false on rate limited error")
    func editMessageReturnsFalseOnRateLimited() async {
        let mock = MockTGAPIClient()
        await mock.setEditMessageError(TGAPIError.rateLimited("too many requests"))
        let adapter = TelegramAdapter(apiClient: mock, allowedUsers: ["123"], log: { _ in })

        let result = await adapter.editMessage(chatId: 123, messageId: 1, text: "retry")
        #expect(result == false)
    }

    // MARK: - Helpers

    private func makeTestRegistry(
        clearSession: (@Sendable (Int64) async -> Void)? = nil
    ) -> TGCommandRegistry {
        let clear: @Sendable (Int64) async -> Void = clearSession ?? { _ in }
        return TGCommandRegistry(commands: [
            TGCommandDef(name: "status", description: "查看状态", helpText: "", menuPriority: 3) { _ in
                "📊 Gateway Status\n状态: running\n运行中任务: 0"
            },
            TGCommandDef(name: "skills", description: "查看技能", helpText: "", menuPriority: 4) { _ in "暂无可用技能" },
            TGCommandDef(name: "new", description: "开始新会话", helpText: "", menuPriority: 5) { chatId in
                await clear(chatId)
                return "新会话已开始"
            },
        ])
    }
}

// MARK: - Fallback Mock

/// Mock that can inject a one-shot error for testing fallback behavior
actor MockFallbackTGAPIClient: TGAPIClientProtocol {
    private var _sentMessages: [(chatId: Int64, text: String, parseMode: TGParseMode?, replyToMessageId: Int64?)] = []
    private var _nextError: Error?
    private var _mdv2Attempted = false

    var sentMessages: [(chatId: Int64, text: String, parseMode: TGParseMode?, replyToMessageId: Int64?)] { _sentMessages }

    func setNextError(_ error: Error?) {
        _nextError = error
    }

    func getUpdates(offset: Int64?, timeout: Int) async throws -> [TGUpdate] { [] }

    func sendMessage(chatId: Int64, text: String) async throws -> TGMessage {
        _sentMessages.append((chatId, text, nil, nil))
        return TGMessage(messageId: Int64(_sentMessages.count), from: nil, chat: TGChat(id: chatId, type: "private"), date: 0, text: text)
    }

    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyToMessageId: Int64?) async throws -> TGMessage {
        if parseMode == .markdownV2, !_mdv2Attempted {
            _mdv2Attempted = true
            if let error = _nextError { throw error }
        }
        _sentMessages.append((chatId, text, parseMode, replyToMessageId))
        return TGMessage(messageId: Int64(_sentMessages.count), from: nil, chat: TGChat(id: chatId, type: "private"), date: 0, text: text)
    }

    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup?) async throws -> TGMessage {
        _sentMessages.append((chatId, text, parseMode, nil))
        return TGMessage(messageId: Int64(_sentMessages.count), from: nil, chat: TGChat(id: chatId, type: "private"), date: 0, text: text)
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode) async throws -> TGMessage {
        TGMessage(messageId: messageId, from: nil, chat: TGChat(id: chatId, type: "private"), date: 0, text: text)
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup?) async throws -> TGMessage {
        TGMessage(messageId: messageId, from: nil, chat: TGChat(id: chatId, type: "private"), date: 0, text: text)
    }

    func answerCallbackQuery(callbackQueryId: String, text: String?) async throws {}

    func getFile(fileId: String) async throws -> TGFile {
        TGFile(fileId: fileId, filePath: "photos/file_0.jpg")
    }

    func downloadFile(filePath: String) async throws -> Data {
        Data("fake".utf8)
    }

    func sendChatAction(chatId: Int64, action: String) async throws {}
    func setMyCommands(commands: [(name: String, description: String)]) async throws {}
}

/// Mock that succeeds on first MDv2 call, fails on second MDv2 call, then succeeds on HTML.
/// Used to test that fallback doesn't duplicate already-sent chunks.
actor MockMultiChunkFallbackTGAPIClient: TGAPIClientProtocol {
    private var _sentMessages: [(chatId: Int64, text: String, parseMode: TGParseMode?, replyToMessageId: Int64?)] = []
    private var _mdv2CallCount = 0

    var sentMessages: [(chatId: Int64, text: String, parseMode: TGParseMode?, replyToMessageId: Int64?)] { _sentMessages }

    func getUpdates(offset: Int64?, timeout: Int) async throws -> [TGUpdate] { [] }

    func sendMessage(chatId: Int64, text: String) async throws -> TGMessage {
        _sentMessages.append((chatId, text, nil, nil))
        return TGMessage(messageId: Int64(_sentMessages.count), from: nil, chat: TGChat(id: chatId, type: "private"), date: 0, text: text)
    }

    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyToMessageId: Int64?) async throws -> TGMessage {
        if parseMode == .markdownV2 {
            _mdv2CallCount += 1
            if _mdv2CallCount == 2 {
                // Second MDv2 chunk fails → triggers fallback
                throw TGAPIError.formatRejected("can't parse entities")
            }
        }
        _sentMessages.append((chatId, text, parseMode, replyToMessageId))
        return TGMessage(messageId: Int64(_sentMessages.count), from: nil, chat: TGChat(id: chatId, type: "private"), date: 0, text: text)
    }

    func sendMessage(chatId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup?) async throws -> TGMessage {
        _sentMessages.append((chatId, text, parseMode, nil))
        return TGMessage(messageId: Int64(_sentMessages.count), from: nil, chat: TGChat(id: chatId, type: "private"), date: 0, text: text)
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode) async throws -> TGMessage {
        TGMessage(messageId: messageId, from: nil, chat: TGChat(id: chatId, type: "private"), date: 0, text: text)
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String, parseMode: TGParseMode, replyMarkup: TGInlineKeyboardMarkup?) async throws -> TGMessage {
        TGMessage(messageId: messageId, from: nil, chat: TGChat(id: chatId, type: "private"), date: 0, text: text)
    }

    func answerCallbackQuery(callbackQueryId: String, text: String?) async throws {}

    func getFile(fileId: String) async throws -> TGFile {
        TGFile(fileId: fileId, filePath: "photos/file_0.jpg")
    }

    func downloadFile(filePath: String) async throws -> Data {
        Data("fake".utf8)
    }

    func sendChatAction(chatId: Int64, action: String) async throws {}
    func setMyCommands(commands: [(name: String, description: String)]) async throws {}
}
