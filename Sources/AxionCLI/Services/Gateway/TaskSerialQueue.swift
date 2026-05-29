import Foundation
import OpenAgentSDK
import AxionCore

// MARK: - Protocol

protocol TaskSerialQueueProtocol: Sendable {
    func enqueue(task: String, chatId: Int64) async
    func startProcessing() async
    func cancelAll() async
    var pendingCount: Int { get async }
    var isProcessing: Bool { get async }
}

// MARK: - TaskSerialQueue

actor TaskSerialQueue: TaskSerialQueueProtocol {
    private struct PendingTask: Sendable {
        let task: String
        let chatId: Int64
    }

    private struct TaskTimeoutError: Error {}

    private var queue: [PendingTask] = []
    private var isExecuting = false
    private var isShuttingDown = false
    private var newTaskContinuation: CheckedContinuation<Void, Never>?

    private let runtimeManager: any DaemonRuntimeManaging
    private let config: AxionConfig
    private let runner: GatewayRunner
    private let replyHandler: @Sendable (Int64, String) async -> Void

    init(
        runtimeManager: any DaemonRuntimeManaging,
        config: AxionConfig,
        runner: GatewayRunner,
        replyHandler: @Sendable @escaping (Int64, String) async -> Void
    ) {
        self.runtimeManager = runtimeManager
        self.config = config
        self.runner = runner
        self.replyHandler = replyHandler
    }

    func enqueue(task: String, chatId: Int64) async {
        guard !isShuttingDown else {
            await replyHandler(chatId, "Gateway 正在关闭，任务已取消")
            return
        }
        let pendingCount = queue.count
        queue.append(PendingTask(task: task, chatId: chatId))
        if isExecuting {
            await replyHandler(chatId, "任务已排队 (队列: \(pendingCount + 1))")
        }
        newTaskContinuation?.resume()
        newTaskContinuation = nil
    }

    func startProcessing() async {
        await processNext()
    }

    private func processNext() async {
        if queue.isEmpty {
            isExecuting = false
            guard !isShuttingDown else { return }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.newTaskContinuation = cont
            }
            guard !isShuttingDown else { return }
            if queue.isEmpty {
                isExecuting = false
                return
            }
        }
        isExecuting = true
        let pending = queue.removeFirst()

        await replyHandler(pending.chatId, "任务开始执行: \"\(pending.task.prefix(50))\"")
        await runner.taskStarted()

        do {
            let timeoutMinutes = config.gatewayTaskTimeoutMinutes ?? 10.0
            let result = try await withThrowingTaskGroup(of: AxionRunResult.self) { group in
                group.addTask {
                    let request = OpenAgentSDK.CreateRunRequest(task: pending.task)
                    let buildConfig = AgentBuilder.BuildConfig.forAPI(
                        config: self.config,
                        task: pending.task,
                        request: request
                    )
                    return try await self.runtimeManager.executeRun(
                        task: pending.task,
                        buildConfig: buildConfig,
                        eventBus: EventBus(),
                        runOverrides: .default
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
            let summary = Self.summarize(result)
            await replyHandler(pending.chatId, summary)
        } catch is TaskTimeoutError {
            let timeoutMinutes = config.gatewayTaskTimeoutMinutes ?? 10.0
            await replyHandler(pending.chatId, "任务超时已取消 (\(Int(timeoutMinutes)) 分钟)")
        } catch {
            await replyHandler(pending.chatId, "任务执行失败: \(error.localizedDescription)")
        }

        await runner.taskFinished()
        await processNext()
    }

    func cancelAll() async {
        isShuttingDown = true
        for pending in queue {
            await replyHandler(pending.chatId, "Gateway 正在关闭，任务已取消")
        }
        queue.removeAll()
        newTaskContinuation?.resume()
        newTaskContinuation = nil
    }

    var pendingCount: Int { queue.count }
    var isProcessing: Bool { isExecuting }

    private static func summarize(_ result: AxionRunResult) -> String {
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
