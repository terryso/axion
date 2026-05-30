import Testing
import Foundation
import AxionCore
import OpenAgentSDK
@testable import AxionCLI

@Suite("TaskSerialQueue")
struct TaskSerialQueueTests {

    // MARK: - Mocks

    actor MockRuntimeManager: DaemonRuntimeManaging {
        private var results: [String: AxionRunResult] = [:]
        private var delays: [String: UInt64] = [:]
        private var executeCallCount = 0
        private var resumeCallCount = 0
        private var executedTasks: [String] = []
        private var resumedSessionIds: [String] = []
        private var resumeError: Error?

        var callCount: Int { executeCallCount }
        var tasks: [String] { executedTasks }
        var resumeCount: Int { resumeCallCount }
        var resumedSessions: [String] { resumedSessionIds }

        func setResult(_ result: AxionRunResult, for task: String) {
            results[task] = result
        }

        func setDelay(_ nanos: UInt64, for task: String) {
            delays[task] = nanos
        }

        func setResumeError(_ error: Error) {
            resumeError = error
        }

        func executeRun(task: String, buildConfig: AgentBuilder.BuildConfig, eventBus: OpenAgentSDK.EventBus, runOverrides: AxionRuntime.RunOverrides, sessionId: String? = nil) async throws -> AxionRunResult {
            return try await executeRun(task: task, buildConfig: buildConfig, eventBus: eventBus, runOverrides: runOverrides, extraHandlers: [], sessionId: sessionId)
        }

        func executeRun(task: String, buildConfig: AgentBuilder.BuildConfig, eventBus: OpenAgentSDK.EventBus, runOverrides: AxionRuntime.RunOverrides, extraHandlers: [any EventHandler], sessionId: String? = nil) async throws -> AxionRunResult {
            executedTasks.append(task)
            executeCallCount += 1
            if let delay = delays[task] {
                try await _Concurrency.Task.sleep(nanoseconds: delay)
            }
            guard let result = results[task] else {
                return AxionRunResult(
                    sessionId: "test-\(task)",
                    task: task,
                    state: .completed,
                    totalSteps: 1,
                    durationMs: 100,
                    runSucceeded: true,
                    createdAt: Date()
                )
            }
            return result
        }

        func resumeRun(sessionId: String, task: String, buildConfig: AgentBuilder.BuildConfig, eventBus: OpenAgentSDK.EventBus, runOverrides: AxionRuntime.RunOverrides, extraHandlers: [any EventHandler]) async throws -> AxionRunResult {
            if let error = resumeError {
                throw error
            }
            resumedSessionIds.append(sessionId)
            executedTasks.append(task)
            resumeCallCount += 1
            executeCallCount += 1
            guard let result = results[task] else {
                return AxionRunResult(
                    sessionId: sessionId,
                    task: task,
                    state: .completed,
                    totalSteps: 1,
                    durationMs: 100,
                    runSucceeded: true,
                    createdAt: Date()
                )
            }
            return result
        }

        func executeSkill(skill: OpenAgentSDK.Skill, task: String, config: AxionConfig, buildConfig: AgentBuilder.BuildConfig, eventBus: OpenAgentSDK.EventBus, runOverrides: AxionRuntime.RunOverrides) async throws -> AxionRunResult {
            fatalError("not used in these tests")
        }

        func listActiveSessions() async -> [DaemonSessionInfo] { [] }
        func shutdown() async {}
    }

    // MARK: - Helpers

    private func makeConfig(timeout: Double? = nil) -> AxionConfig {
        AxionConfig(apiKey: nil, gatewayTaskTimeoutMinutes: timeout)
    }

    private func makeRunner() -> (GatewayRunner, MockGatewayServerForQueue) {
        let server = MockGatewayServerForQueue()
        let runner = GatewayRunner(server: server)
        return (runner, server)
    }

    actor ReplyCollector {
        private var replies: [(chatId: Int64, message: String)] = []

        func add(chatId: Int64, message: String) {
            replies.append((chatId, message))
        }

        var all: [(chatId: Int64, message: String)] { replies }

        func messages(for chatId: Int64) -> [String] {
            replies.filter { $0.chatId == chatId }.map(\.message)
        }

        func clear() { replies.removeAll() }
    }

    actor MockGatewayServerForQueue: GatewayHTTPControlling {
        private var continuation: CheckedContinuation<Void, Error>?

        func start() async throws {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
            }
        }

        func stop() async {
            continuation?.resume()
            continuation = nil
        }
    }

    // MARK: - Tests: Serial Execution (Task 5.1)

    @Test("Tasks execute serially one at a time")
    func serialExecution() async throws {
        let runtime = MockRuntimeManager()
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        await queue.enqueue(task: "task-A", chatId: 100)
        await queue.enqueue(task: "task-B", chatId: 100)

        // Wait for processing
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await queue.cancelAll()
        processingTask.cancel()

        let tasks = await runtime.tasks
        #expect(tasks.count == 2)
        #expect(tasks[0] == "task-A")
        #expect(tasks[1] == "task-B")

        await server.stop()
    }

    // MARK: - Tests: Queueing + FIFO (Task 5.2)

    @Test("Second task is queued when first is executing")
    func queuingSecondTask() async throws {
        let runtime = MockRuntimeManager()
        await runtime.setDelay(200_000_000, for: "task-A") // 200ms
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        await queue.enqueue(task: "task-A", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000) // let task-A start
        await queue.enqueue(task: "task-B", chatId: 200)

        // Check queue notification
        let repliesForB = await collector.messages(for: 200)
        #expect(repliesForB.contains { $0.contains("已排队") })

        // Wait for both to complete
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        await queue.cancelAll()
        processingTask.cancel()

        let tasks = await runtime.tasks
        #expect(tasks.count == 2)
        #expect(tasks[0] == "task-A")
        #expect(tasks[1] == "task-B")

        await server.stop()
    }

    // MARK: - Tests: Timeout Cancellation (Task 5.3)

    @Test("Task exceeding timeout is cancelled")
    func timeoutCancellation() async throws {
        let runtime = MockRuntimeManager()
        await runtime.setDelay(5_000_000_000, for: "slow-task") // 5 seconds
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let config = makeConfig(timeout: 0.001) // 0.001 minutes = 60ms
        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: config,
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        await queue.enqueue(task: "slow-task", chatId: 100)

        // Wait for timeout to trigger
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        await queue.cancelAll()
        processingTask.cancel()

        let replies = await collector.messages(for: 100)
        #expect(replies.contains { $0.contains("超时已取消") })

        await server.stop()
    }

    // MARK: - Tests: cancelAll (Task 5.4)

    @Test("cancelAll discards queued tasks and notifies users")
    func cancelAllDiscardsQueued() async throws {
        let runtime = MockRuntimeManager()
        await runtime.setDelay(5_000_000_000, for: "running-task") // won't actually complete
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        await queue.enqueue(task: "running-task", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        await queue.enqueue(task: "queued-1", chatId: 200)
        await queue.enqueue(task: "queued-2", chatId: 300)

        await queue.cancelAll()

        let pendingCount = await queue.pendingCount
        #expect(pendingCount == 0)

        let replies200 = await collector.messages(for: 200)
        let replies300 = await collector.messages(for: 300)
        #expect(replies200.contains { $0.contains("正在关闭") })
        #expect(replies300.contains { $0.contains("正在关闭") })

        processingTask.cancel()
        await server.stop()
    }

    @Test("enqueue after cancelAll returns cancellation notice")
    func enqueueAfterCancelAll() async throws {
        let runtime = MockRuntimeManager()
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        await queue.cancelAll()
        await queue.enqueue(task: "late-task", chatId: 100)

        let replies = await collector.messages(for: 100)
        #expect(replies.contains { $0.contains("正在关闭") })

        await server.stop()
    }

    // MARK: - Tests: Result Summary Truncation (Task 5.7)

    @Test("Result summary is truncated at 500 characters")
    func resultSummaryTruncation() async {
        let longError = String(repeating: "X", count: 600)
        let result = AxionRunResult(
            sessionId: "s1",
            task: "task",
            state: .completed,
            totalSteps: 5,
            durationMs: 10_000,
            runSucceeded: false,
            errorMessage: longError,
            createdAt: Date()
        )
        let summary = TaskSerialQueue.summarize(result)
        #expect(summary.count > 500)
        #expect(summary.contains("完整结果"))
    }

    @Test("Short result summary is not truncated")
    func shortResultNotTruncated() async {
        let result = AxionRunResult(
            sessionId: "s1",
            task: "task",
            state: .completed,
            totalSteps: 3,
            durationMs: 5_000,
            runSucceeded: true,
            createdAt: Date()
        )
        let summary = TaskSerialQueue.summarize(result)
        #expect(summary.contains("任务完成"))
        #expect(!summary.contains("完整结果"))
    }

    @Test("Error result summary shows error message")
    func errorResultSummary() async {
        let result = AxionRunResult(
            sessionId: "s1",
            task: "task",
            state: .completed,
            totalSteps: 1,
            durationMs: 100,
            runSucceeded: false,
            errorMessage: "something went wrong",
            createdAt: Date()
        )
        let summary = TaskSerialQueue.summarize(result)
        #expect(summary.contains("任务失败"))
        #expect(summary.contains("something went wrong"))
    }

    // MARK: - Tests: Start Execution Notification (AC #1, #3)

    @Test("First task gets 'started' notification immediately")
    func firstTaskStartsImmediately() async throws {
        let runtime = MockRuntimeManager()
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }
        await queue.enqueue(task: "hello", chatId: 100)

        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        await queue.cancelAll()
        processingTask.cancel()

        let replies = await collector.messages(for: 100)
        #expect(replies.contains { $0.contains("任务开始执行") && $0.contains("hello") })

        await server.stop()
    }

    @Test("Queued task starts after previous completes")
    func queuedTaskStartsAfterPrevious() async throws {
        let runtime = MockRuntimeManager()
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        await queue.enqueue(task: "first", chatId: 100)
        await queue.enqueue(task: "second", chatId: 100)

        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        await queue.cancelAll()
        processingTask.cancel()

        let replies = await collector.messages(for: 100)
        let startedMessages = replies.filter { $0.contains("任务开始执行") }
        #expect(startedMessages.count == 2)
        #expect(startedMessages[0].contains("first"))
        #expect(startedMessages[1].contains("second"))

        await server.stop()
    }

    // MARK: - Tests: activeTaskCount Integration (Task 5.8)

    @Test("activeTaskCount updates during task execution")
    func activeTaskCountUpdates() async throws {
        let runtime = MockRuntimeManager()
        await runtime.setDelay(500_000_000, for: "task") // 500ms
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        await queue.enqueue(task: "task", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // let task start

        let countDuringExecution = await runner.activeTaskCount
        #expect(countDuringExecution == 1)

        try await _Concurrency.Task.sleep(nanoseconds: 600_000_000) // wait for completion
        await queue.cancelAll()
        processingTask.cancel()

        let countAfterCompletion = await runner.activeTaskCount
        #expect(countAfterCompletion == 0)

        await server.stop()
    }

    // MARK: - Tests: Session Resume (AC1)

    @Test("Follow-up message resumes session within timeout")
    func followUpResumesSession() async throws {
        let runtime = MockRuntimeManager()
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        await queue.enqueue(task: "open calculator", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)

        await queue.enqueue(task: "what was the result", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)

        await queue.cancelAll()
        processingTask.cancel()

        let resumeCount = await runtime.resumeCount
        #expect(resumeCount == 1)

        let tasks = await runtime.tasks
        #expect(tasks.count == 2)
        #expect(tasks[0] == "open calculator")
        #expect(tasks[1] == "what was the result")

        await server.stop()
    }

    // MARK: - Tests: Timeout Reset (AC2)

    @Test("Cleared session creates new session without resume")
    func clearedSessionCreatesNew() async throws {
        let runtime = MockRuntimeManager()
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        await queue.enqueue(task: "first task", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)

        await queue.clearSession(chatId: 100)

        await queue.enqueue(task: "second task", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)

        await queue.cancelAll()
        processingTask.cancel()

        let resumeCount = await runtime.resumeCount
        #expect(resumeCount == 0)

        let tasks = await runtime.tasks
        #expect(tasks.count == 2)

        await server.stop()
    }

    // MARK: - Tests: Resume Failure Degradation (AC4)

    @Test("Resume failure degrades to executeRun")
    func resumeFailureDegradesToExecuteRun() async throws {
        let runtime = MockRuntimeManager()
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        await queue.enqueue(task: "first", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)

        await runtime.setResumeError(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "session corrupted"]))
        await queue.enqueue(task: "second", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

        await queue.cancelAll()
        processingTask.cancel()

        let tasks = await runtime.tasks
        #expect(tasks.count == 2)
        #expect(tasks[0] == "first")
        #expect(tasks[1] == "second")

        let callCount = await runtime.callCount
        #expect(callCount == 2)

        await server.stop()
    }

    // MARK: - Tests: /new Does Not Affect Queued Tasks (AC5)

    @Test("clearSession does not affect already queued tasks")
    func clearSessionDoesNotAffectQueuedTasks() async throws {
        let runtime = MockRuntimeManager()
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        // First task completes quickly, creating a session
        await queue.enqueue(task: "first", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)

        // Second task enqueued while no task running — sees active session, freezes resume decision
        await queue.enqueue(task: "follow-up", chatId: 100)

        // Now clear the session (simulating /new)
        await queue.clearSession(chatId: 100)

        // Third task after clear — should NOT resume
        await queue.enqueue(task: "after-clear", chatId: 100)

        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        await queue.cancelAll()
        processingTask.cancel()

        let tasks = await runtime.tasks
        #expect(tasks.count == 3)

        // follow-up was enqueued before clearSession, so it should resume
        let resumeCount = await runtime.resumeCount
        #expect(resumeCount == 1)

        await server.stop()
    }

    // MARK: - Tests: clearSession Isolation

    @Test("clearSession for one chatId does not affect another")
    func clearSessionIsolation() async throws {
        let runtime = MockRuntimeManager()
        let collector = ReplyCollector()
        let (runner, server) = makeRunner()

        let queue = TaskSerialQueue(
            runtimeManager: runtime,
            config: makeConfig(),
            runner: runner,
            replyHandler: { await collector.add(chatId: $0, message: $1) }
        )

        let processingTask = _Concurrency.Task { await queue.startProcessing() }

        await queue.enqueue(task: "task-A", chatId: 100)
        await queue.enqueue(task: "task-B", chatId: 200)
        try await _Concurrency.Task.sleep(nanoseconds: 400_000_000)

        await queue.clearSession(chatId: 100)

        await queue.enqueue(task: "follow-up-200", chatId: 200)
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)

        await queue.enqueue(task: "follow-up-100", chatId: 100)
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)

        await queue.cancelAll()
        processingTask.cancel()

        let resumeCount = await runtime.resumeCount
        #expect(resumeCount == 1)

        await server.stop()
    }
}
