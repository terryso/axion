import Foundation
import OpenAgentSDK
import AxionCore

// MARK: - Protocol

protocol TaskSerialQueueProtocol: Sendable, Actor {
    func enqueue(task: String, chatId: Int64, userId: Int64) async
    func startProcessing() async
    func cancelAll() async
    func clearSession(chatId: Int64) async
    var pendingCount: Int { get async }
    var isProcessing: Bool { get async }
    func pendingCount(chatId: Int64) async -> Int
    func isProcessing(chatId: Int64) async -> Bool
    func hasActiveSession(chatId: Int64) async -> Bool
    func registerResumeHandle(pendingId: String, handle: @Sendable @escaping (String) async -> Void)
    func resumeInteraction(pendingId: String, context: String) async -> Bool
    func cancelCurrentTask(chatId: Int64) -> Bool
}

// MARK: - TaskSerialQueue

actor TaskSerialQueue: TaskSerialQueueProtocol {
    struct ActiveSession: Sendable {
        let sessionId: String
        let chatId: Int64
        let lastActivityAt: ContinuousClock.Instant
        let createdAt: Date
    }

    struct PendingTask: Sendable {
        let task: String
        let chatId: Int64
        let userId: Int64
        let shouldResume: Bool
        let existingSessionId: String?
        let shouldReviewMemory: Bool
    }

    private static let sessionTimeout: Duration = .seconds(30 * 60)

    private var queue: [PendingTask] = []
    private var isExecuting = false
    private var isShuttingDown = false
    private var newTaskContinuation: CheckedContinuation<Void, Never>?

    var currentChatId: Int64?
    var chatSessions: [Int64: ActiveSession] = [:]
    var activeResumeHandles: [String: @Sendable (String) async -> Void] = [:]
    var currentExecutionTask: _Concurrency.Task<Void, Never>?

    let runtimeManager: any DaemonRuntimeManaging
    let config: AxionConfig
    let runner: GatewayRunner
    let extraHandlers: [any EventHandler]
    let handlerProfile: HandlerProfile
    var replyHandler: @Sendable (Int64, String) async -> Int64?
    var editHandler: @Sendable (Int64, Int64, String) async -> Bool
    var chatActionHandler: @Sendable (Int64, String) async -> Void
    let sessionStore: TGInteractiveSessionStore?
    var sendMessageWithMarkupHandler: @Sendable (Int64, String, TGInlineKeyboardMarkup?) async -> Int64?
    let gatewaySessionStore: GatewaySessionStore?

    init(
        runtimeManager: any DaemonRuntimeManaging,
        config: AxionConfig,
        runner: GatewayRunner,
        extraHandlers: [any EventHandler] = [],
        handlerProfile: HandlerProfile,
        gatewaySessionStore: GatewaySessionStore? = nil,
        replyHandler: @Sendable @escaping (Int64, String) async -> Int64?,
        editHandler: @Sendable @escaping (Int64, Int64, String) async -> Bool = { _, _, _ in false },
        chatActionHandler: @Sendable @escaping (Int64, String) async -> Void = { _, _ in },
        sessionStore: TGInteractiveSessionStore? = nil,
        sendMessageWithMarkupHandler: @Sendable @escaping (Int64, String, TGInlineKeyboardMarkup?) async -> Int64? = { _, _, _ in nil }
    ) {
        self.runtimeManager = runtimeManager
        self.config = config
        self.runner = runner
        self.extraHandlers = extraHandlers
        self.handlerProfile = handlerProfile
        self.gatewaySessionStore = gatewaySessionStore
        self.replyHandler = replyHandler
        self.editHandler = editHandler
        self.chatActionHandler = chatActionHandler
        self.sessionStore = sessionStore
        self.sendMessageWithMarkupHandler = sendMessageWithMarkupHandler
    }

    // MARK: - Enqueue

    func enqueue(task: String, chatId: Int64, userId: Int64) async {
        guard !isShuttingDown else {
            _ = await replyHandler(chatId, "Gateway 正在关闭，任务已取消")
            return
        }

        let now = ContinuousClock.now
        let shouldResume: Bool
        let existingSessionId: String?

        if let session = chatSessions[chatId] {
            let elapsed = now - session.lastActivityAt
            if elapsed < Self.sessionTimeout {
                shouldResume = true
                existingSessionId = session.sessionId
            } else {
                chatSessions.removeValue(forKey: chatId)
                shouldResume = false
                existingSessionId = nil
            }
        } else {
            shouldResume = false
            existingSessionId = nil
        }
        // Track user turns for session-aware review triggering (non-resume only)
        var shouldReviewMemory = false
        if !shouldResume {
            if let store = gatewaySessionStore {
                await store.recordTurn(chatId: chatId, sessionId: existingSessionId ?? "")
                let state = await store.state(for: chatId)
                let nudgeInterval = config.memoryNudgeInterval
                shouldReviewMemory = (state?.turnsSinceMemory ?? 0) >= nudgeInterval
                if shouldReviewMemory {
                    await store.resetMemoryCounter(chatId: chatId)
                }
            }
        }

        let pendingCount = queue.count
        queue.append(PendingTask(
            task: task,
            chatId: chatId,
            userId: userId,
            shouldResume: shouldResume,
            existingSessionId: existingSessionId,
            shouldReviewMemory: shouldReviewMemory
        ))
        if isExecuting {
            _ = await replyHandler(chatId, "任务已排队 (队列: \(pendingCount + 1))")
        }
        newTaskContinuation?.resume()
        newTaskContinuation = nil
    }

    // MARK: - Processing Loop

    func startProcessing() async {
        while !isShuttingDown {
            if queue.isEmpty {
                isExecuting = false
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    self.newTaskContinuation = cont
                }
                guard !isShuttingDown else { return }
                if queue.isEmpty { return }
            }
            isExecuting = true
            let pending = queue.removeFirst()
            currentChatId = pending.chatId

            await runner.taskStarted()

            let timeoutMinutes = config.gatewayTaskTimeoutMinutes ?? 10.0

            // Wrap execution in a Task so we can cancel it from cancelCurrentTask
            currentExecutionTask = _Concurrency.Task {
                await self.executeAndFinalize(pending: pending, timeoutMinutes: timeoutMinutes)
            }

            // Await the task to maintain sequential processing
            _ = await currentExecutionTask?.value

            // Cleanup (also done in executeAndFinalize, but safe to double-clean)
            if currentChatId != nil {
                activeResumeHandles.removeAll()
                currentChatId = nil
                currentExecutionTask = nil
                await runner.taskFinished()
            }
        }
    }

    // MARK: - Cancellation

    func cancelCurrentTask(chatId: Int64) -> Bool {
        // Can only cancel if currently executing for this chat
        guard isExecuting && currentChatId == chatId else {
            return false
        }
        // Cancel the running task — triggers CancellationError propagation
        currentExecutionTask?.cancel()
        // Clear queued tasks for this chat as well
        queue.removeAll { $0.chatId == chatId }
        // Clear the session so next message starts fresh
        chatSessions.removeValue(forKey: chatId)
        activeResumeHandles.removeAll()
        return true
    }

    func cancelAll() async {
        isShuttingDown = true
        for pending in queue {
            _ = await replyHandler(pending.chatId, "Gateway 正在关闭，任务已取消")
        }
        queue.removeAll()
        newTaskContinuation?.resume()
        newTaskContinuation = nil
    }

    // MARK: - Session Management

    func clearSession(chatId: Int64) async {
        chatSessions.removeValue(forKey: chatId)
        if let store = gatewaySessionStore {
            await store.clearSession(chatId: chatId)
        }
    }

    func updateReplyHandler(_ handler: @Sendable @escaping (Int64, String) async -> Int64?) {
        self.replyHandler = handler
    }

    func updateEditHandler(_ handler: @Sendable @escaping (Int64, Int64, String) async -> Bool) {
        self.editHandler = handler
    }

    func updateChatActionHandler(_ handler: @Sendable @escaping (Int64, String) async -> Void) {
        self.chatActionHandler = handler
    }

    func updateSendMessageWithMarkupHandler(_ handler: @Sendable @escaping (Int64, String, TGInlineKeyboardMarkup?) async -> Int64?) {
        self.sendMessageWithMarkupHandler = handler
    }

    func registerResumeHandle(pendingId: String, handle: @Sendable @escaping (String) async -> Void) {
        activeResumeHandles[pendingId] = handle
    }

    func resumeInteraction(pendingId: String, context: String) async -> Bool {
        guard let handle = activeResumeHandles.removeValue(forKey: pendingId) else { return false }
        await handle(context)
        return true
    }

    // MARK: - Queries

    var pendingCount: Int { queue.count }
    var isProcessing: Bool { isExecuting }

    func pendingCount(chatId: Int64) -> Int {
        queue.filter { $0.chatId == chatId }.count
    }

    func isProcessing(chatId: Int64) -> Bool {
        isExecuting && currentChatId == chatId
    }

    func hasActiveSession(chatId: Int64) -> Bool {
        chatSessions[chatId] != nil
    }

    // MARK: - Session Update

    func updateSession(from result: AxionRunResult, chatId: Int64) {
        chatSessions[chatId] = ActiveSession(
            sessionId: result.sessionId,
            chatId: chatId,
            lastActivityAt: ContinuousClock.now,
            createdAt: result.createdAt
        )
    }

}
