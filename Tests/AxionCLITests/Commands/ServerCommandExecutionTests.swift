import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

// MARK: - Helpers

extension ServerCommandExecutionTests {

    static func completedResult() -> AxionRunResult {
        AxionRunResult(
            sessionId: "test-session", task: "test", state: .completed,
            totalSteps: 3, durationMs: 100, runSucceeded: true,
            createdAt: Date()
        )
    }

    static func failedResult() -> AxionRunResult {
        AxionRunResult(
            sessionId: "test-session", task: "test", state: .failed,
            totalSteps: 0, durationMs: 0, runSucceeded: false,
            errorMessage: "build failed", createdAt: Date()
        )
    }

    /// Inject mock runtime for the duration of `body`, restoring originals afterward.
    private func withMockRuntime(
        _ mock: MockAxionRuntime,
        _ body: () async throws -> Void
    ) async throws {
        let savedFactory = ServerCommand.createRuntime
        ServerCommand.createRuntime = { _ in mock }
        defer {
            ServerCommand.createRuntime = savedFactory
        }
        try await body()
    }
}

// MARK: - Tests

@Suite("ServerCommand Execution via AxionRuntime", .serialized)
struct ServerCommandExecutionTests {

    @Test("createRuntime seam returns injected mock and registerHandler increments count")
    func handlerRegistrationCount() async throws {
        let mock = MockAxionRuntime(executeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            let eventBus = EventBus()
            let runtime = ServerCommand.createRuntime(eventBus) as! MockAxionRuntime

            await runtime.registerHandler(CostEventHandler())
            await runtime.registerHandler(TraceEventHandler(traceDir: "/tmp/test-traces"))

            let finalCount = await runtime.handlerCount
            #expect(finalCount == 2, "ServerCommand should register exactly 2 handlers (cost + trace)")
        }
    }

    @Test("mock runtime execute returns .completed result")
    func successfulExecution() async throws {
        let mock = MockAxionRuntime(executeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            let eventBus = EventBus()
            let runtime = ServerCommand.createRuntime(eventBus) as! MockAxionRuntime

            let result = try await runtime.execute(
                buildConfig: AgentBuilder.BuildConfig.forAPI(
                    config: AxionConfig(apiKey: "test"),
                    task: "test task",
                    request: CreateRunRequest(task: "test task")
                ),
                runOverrides: .default
            )

            #expect(result.state == .completed)
            #expect(result.totalSteps == 3)
        }
    }

    @Test("mock runtime execute returns .failed result")
    func failedExecution() async throws {
        let mock = MockAxionRuntime(executeResult: Self.failedResult())
        try await withMockRuntime(mock) {
            let eventBus = EventBus()
            let runtime = ServerCommand.createRuntime(eventBus) as! MockAxionRuntime

            let result = try await runtime.execute(
                buildConfig: AgentBuilder.BuildConfig.forAPI(
                    config: AxionConfig(apiKey: "test"),
                    task: "test task",
                    request: CreateRunRequest(task: "test task")
                ),
                runOverrides: .default
            )

            #expect(result.state == .failed)
        }
    }

    @Test("ConcurrencyLimiter acquire/release does not deadlock")
    func limiterAcquireRelease() async throws {
        let mock = MockAxionRuntime(executeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            let eventBus = EventBus()
            let runtime = ServerCommand.createRuntime(eventBus) as! MockAxionRuntime

            let limiter = ConcurrencyLimiter(maxConcurrent: 5)
            await limiter.acquire()

            _ = try await runtime.execute(
                buildConfig: AgentBuilder.BuildConfig.forAPI(
                    config: AxionConfig(apiKey: "test"),
                    task: "test task",
                    request: CreateRunRequest(task: "test task")
                ),
                runOverrides: .default
            )

            await limiter.release()
        }
    }

    @Test("event loop start/stop lifecycle tracked in mock")
    func eventLoopLifecycle() async throws {
        let mock = MockAxionRuntime(executeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            let eventBus = EventBus()
            let runtime = ServerCommand.createRuntime(eventBus) as! MockAxionRuntime

            await runtime.startEventLoop()

            _ = try await runtime.execute(
                buildConfig: AgentBuilder.BuildConfig.forAPI(
                    config: AxionConfig(apiKey: "test"),
                    task: "test task",
                    request: CreateRunRequest(task: "test task")
                ),
                runOverrides: .default
            )

            await runtime.stopEventLoop()

            let startCount = await runtime.startEventLoopCallCount
            let stopCount = await runtime.stopEventLoopCallCount
            #expect(startCount == 1, "startEventLoop should be called once")
            #expect(stopCount == 1, "stopEventLoop should be called once")
        }
    }

    @Test("execute error is propagated and stopEventLoop still tracked")
    func errorTriggersCleanup() async throws {
        struct TestError: Error {}
        let mock = MockAxionRuntime(executeError: TestError())
        try await withMockRuntime(mock) {
            let eventBus = EventBus()
            let runtime = ServerCommand.createRuntime(eventBus) as! MockAxionRuntime

            do {
                _ = try await runtime.execute(
                    buildConfig: AgentBuilder.BuildConfig.forAPI(
                        config: AxionConfig(apiKey: "test"),
                        task: "test task",
                        request: CreateRunRequest(task: "test task")
                    ),
                    runOverrides: .default
                )
                Issue.record("Expected error to be thrown")
            } catch {
                // Expected
            }

            await runtime.stopEventLoop()

            let stopCount = await mock.stopEventLoopCallCount
            #expect(stopCount == 1, "stopEventLoop should be called on error")
        }
    }
}
