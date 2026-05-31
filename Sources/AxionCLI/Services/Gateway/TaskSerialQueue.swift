import Foundation
import OpenAgentSDK
import AxionCore

// MARK: - Protocol

protocol TaskSerialQueueProtocol: Sendable {
    func enqueue(task: String, chatId: Int64) async
    func startProcessing() async
    func cancelAll() async
    func clearSession(chatId: Int64) async
    var pendingCount: Int { get async }
    var isProcessing: Bool { get async }
}

// MARK: - TaskSerialQueue

actor TaskSerialQueue: TaskSerialQueueProtocol {
    private struct ActiveSession: Sendable {
        let sessionId: String
        let chatId: Int64
        let lastActivityAt: ContinuousClock.Instant
        let createdAt: Date
    }

    private struct PendingTask: Sendable {
        let task: String
        let chatId: Int64
        let shouldResume: Bool
        let existingSessionId: String?
        let startMessage: String
    }

    private struct TaskTimeoutError: Error {}

    private static let sessionTimeout: Duration = .seconds(30 * 60)
    private static let newSessionPrefix = "新会话已开始\n"

    private var queue: [PendingTask] = []
    private var isExecuting = false
    private var isShuttingDown = false
    private var newTaskContinuation: CheckedContinuation<Void, Never>?
    private var chatSessions: [Int64: ActiveSession] = [:]

    private let runtimeManager: any DaemonRuntimeManaging
    private let config: AxionConfig
    private let runner: GatewayRunner
    private let extraHandlers: [any EventHandler]
    private var replyHandler: @Sendable (Int64, String) async -> Int64?
    private var editHandler: @Sendable (Int64, Int64, String) async -> Bool
    private var chatActionHandler: @Sendable (Int64, String) async -> Void

    init(
        runtimeManager: any DaemonRuntimeManaging,
        config: AxionConfig,
        runner: GatewayRunner,
        extraHandlers: [any EventHandler] = [],
        replyHandler: @Sendable @escaping (Int64, String) async -> Int64?,
        editHandler: @Sendable @escaping (Int64, Int64, String) async -> Bool = { _, _, _ in false },
        chatActionHandler: @Sendable @escaping (Int64, String) async -> Void = { _, _ in }
    ) {
        self.runtimeManager = runtimeManager
        self.config = config
        self.runner = runner
        self.extraHandlers = extraHandlers
        self.replyHandler = replyHandler
        self.editHandler = editHandler
        self.chatActionHandler = chatActionHandler
    }

    func enqueue(task: String, chatId: Int64) async {
        guard !isShuttingDown else {
            _ = await replyHandler(chatId, "Gateway 正在关闭，任务已取消")
            return
        }

        let now = ContinuousClock.now
        let shouldResume: Bool
        let existingSessionId: String?
        let startMessage: String

        if let session = chatSessions[chatId] {
            let elapsed = now - session.lastActivityAt
            if elapsed < Self.sessionTimeout {
                shouldResume = true
                existingSessionId = session.sessionId
                startMessage = "任务开始执行: \"\(task.prefix(50))\""
            } else {
                chatSessions.removeValue(forKey: chatId)
                shouldResume = false
                existingSessionId = nil
                startMessage = "\(Self.newSessionPrefix)任务开始执行: \"\(task.prefix(50))\""
            }
        } else {
            shouldResume = false
            existingSessionId = nil
            startMessage = "任务开始执行: \"\(task.prefix(50))\""
        }

        let pendingCount = queue.count
        queue.append(PendingTask(
            task: task,
            chatId: chatId,
            shouldResume: shouldResume,
            existingSessionId: existingSessionId,
            startMessage: startMessage
        ))
        if isExecuting {
            _ = await replyHandler(chatId, "任务已排队 (队列: \(pendingCount + 1))")
        }
        newTaskContinuation?.resume()
        newTaskContinuation = nil
    }

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

            _ = await replyHandler(pending.chatId, pending.startMessage)
            await runner.taskStarted()

            let timeoutMinutes = config.gatewayTaskTimeoutMinutes ?? 10.0

            do {
                let result: AxionRunResult
                if pending.shouldResume, let sessionId = pending.existingSessionId {
                    result = try await executeWithTimeout(
                        timeoutMinutes: timeoutMinutes,
                        pending: pending,
                        sessionId: sessionId
                    )
                } else {
                    result = try await executeNewWithTimeout(
                        timeoutMinutes: timeoutMinutes,
                        pending: pending
                    )
                }
                updateSession(from: result, chatId: pending.chatId)
            } catch is TaskTimeoutError {
                _ = await replyHandler(pending.chatId, "任务超时已取消 (\(Int(timeoutMinutes)) 分钟)")
            } catch {
                _ = await replyHandler(pending.chatId, "任务执行失败: \(error.localizedDescription)")
            }

            await runner.taskFinished()
        }
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

    func clearSession(chatId: Int64) async {
        chatSessions.removeValue(forKey: chatId)
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

    var pendingCount: Int { queue.count }
    var isProcessing: Bool { isExecuting }

    // MARK: - Private Execution Helpers

    private func makeStreamingConfig() -> TGStreamingConfig {
        TGStreamingConfig(
            editInterval: TGStreamingConfig.default.editInterval,
            bufferThreshold: TGStreamingConfig.default.bufferThreshold,
            transport: TGStreamingConfig.default.transport,
            freshFinalAfter: TGStreamingConfig.default.freshFinalAfter,
            typingEnabled: config.tgTypingEnabled,
            typingInterval: config.tgTypingInterval
        )
    }

    private func executeNewWithTimeout(
        timeoutMinutes: Double,
        pending: PendingTask
    ) async throws -> AxionRunResult {
        let streamingConfig = makeStreamingConfig()
        return try await withThrowingTaskGroup(of: AxionRunResult.self) { group in
            group.addTask {
                let request = OpenAgentSDK.CreateRunRequest(task: pending.task)
                let buildConfig = AgentBuilder.BuildConfig(
                    config: self.config,
                    task: pending.task,
                    noMemory: false,
                    noSkills: false,
                    includePlaywright: false,
                    allowForeground: request.allowForeground ?? false,
                    maxSteps: request.maxSteps,
                    maxTokens: nil,
                    verbose: false,
                    dryrun: false,
                    fast: false,
                    runId: nil,
                    sessionId: nil,
                    sessionStore: nil,
                    emitTokenStream: true
                )
                let eventBus = EventBus()
                let tgHandler = TGEventHandler(
                    chatId: pending.chatId,
                    sendMessage: { [weak self] message, chatId in
                        await self?.replyHandler(chatId, message) ?? nil
                    },
                    editMessage: { [weak self] chatId, messageId, text in
                        await self?.editHandler(chatId, messageId, text) ?? false
                    },
                    sendChatAction: { [weak self] chatId, action in
                        await self?.chatActionHandler(chatId, action)
                    },
                    streamingConfig: streamingConfig
                )
                let allHandlers: [any EventHandler] = [tgHandler] + self.extraHandlers
                return try await self.runtimeManager.executeRun(
                    task: pending.task,
                    buildConfig: buildConfig,
                    eventBus: eventBus,
                    runOverrides: .default,
                    extraHandlers: allHandlers,
                    sessionId: nil
                )
            }
            group.addTask {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(timeoutMinutes * 60 * 1_000_000_000))
                throw TaskTimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func executeWithTimeout(
        timeoutMinutes: Double,
        pending: PendingTask,
        sessionId: String
    ) async throws -> AxionRunResult {
        let streamingConfig = makeStreamingConfig()
        do {
            return try await withThrowingTaskGroup(of: AxionRunResult.self) { group in
                group.addTask {
                    let request = OpenAgentSDK.CreateRunRequest(task: pending.task)
                    let buildConfig = AgentBuilder.BuildConfig(
                        config: self.config,
                        task: pending.task,
                        noMemory: false,
                        noSkills: false,
                        includePlaywright: false,
                        allowForeground: request.allowForeground ?? false,
                        maxSteps: request.maxSteps,
                        maxTokens: nil,
                        verbose: false,
                        dryrun: false,
                        fast: false,
                        runId: nil,
                        sessionId: nil,
                        sessionStore: nil,
                        emitTokenStream: true
                    )
                    let eventBus = EventBus()
                    let tgHandler = TGEventHandler(
                        chatId: pending.chatId,
                        sendMessage: { [weak self] message, chatId in
                            await self?.replyHandler(chatId, message)
                        },
                        editMessage: { [weak self] chatId, messageId, text in
                            await self?.editHandler(chatId, messageId, text) ?? false
                        },
                        sendChatAction: { [weak self] chatId, action in
                            await self?.chatActionHandler(chatId, action)
                        },
                        streamingConfig: streamingConfig
                    )
                    let allHandlers: [any EventHandler] = [tgHandler] + self.extraHandlers
                    return try await self.runtimeManager.resumeRun(
                        sessionId: sessionId,
                        task: pending.task,
                        buildConfig: buildConfig,
                        eventBus: eventBus,
                        runOverrides: .default,
                        extraHandlers: allHandlers
                    )
                }
                group.addTask {
                    try await _Concurrency.Task.sleep(nanoseconds: UInt64(timeoutMinutes * 60 * 1_000_000_000))
                    throw TaskTimeoutError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch {
            if error is TaskTimeoutError { throw error }
            fputs("[axion] resumeSession failed for \(sessionId), degrading to new session: \(error.localizedDescription)\n", stderr)
            chatSessions.removeValue(forKey: pending.chatId)
            return try await executeNewWithTimeout(timeoutMinutes: timeoutMinutes, pending: pending)
        }
    }

    private func updateSession(from result: AxionRunResult, chatId: Int64) {
        chatSessions[chatId] = ActiveSession(
            sessionId: result.sessionId,
            chatId: chatId,
            lastActivityAt: ContinuousClock.now,
            createdAt: result.createdAt
        )
    }

    static func summarize(_ result: AxionRunResult) -> String {
        let maxLen = 500
        var summary: String
        if let error = result.errorMessage {
            summary = "❌ 任务失败: \(error)"
        } else {
            summary = "✅ 任务完成 (\(result.totalSteps) 步, \(result.durationMs / 1000)s)"
        }
        guard summary.count > maxLen else { return summary }
        return "\(summary.prefix(maxLen))...(完整结果 \(summary.count) 字符)"
    }
}
