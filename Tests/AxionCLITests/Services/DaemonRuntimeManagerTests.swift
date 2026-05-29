import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

// MARK: - Mock

final class MockDaemonRuntime: AxionRuntimeRunning, @unchecked Sendable {
    let result: AxionRunResult?
    let error: Error?
    private let _handlerCount = LockedCounter()
    private let _startEventLoopCount = LockedCounter()
    private let _stopEventLoopCount = LockedCounter()
    private let _executeCount = LockedCounter()

    var handlerCount: Int { _handlerCount.value }
    var startEventLoopCount: Int { _startEventLoopCount.value }
    var stopEventLoopCount: Int { _stopEventLoopCount.value }
    var executeCount: Int { _executeCount.value }

    init(result: AxionRunResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func registerHandler(_ handler: any EventHandler) async {
        _handlerCount.increment()
    }

    func startEventLoop() async {
        _startEventLoopCount.increment()
    }

    func stopEventLoop() async {
        _stopEventLoopCount.increment()
    }

    func execute(
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult {
        _executeCount.increment()
        if let error { throw error }
        guard let result else { fatalError("MockDaemonRuntime: no result and no error") }
        return result
    }

    func executeSkill(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides = .default
    ) async throws -> AxionRunResult {
        _executeCount.increment()
        if let error { throw error }
        guard let result else { fatalError("MockDaemonRuntime: no result and no error") }
        return result
    }
}

private final class LockedCounter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

private final class AtomicBox<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()
    var value: T { lock.withLock { _value } }
    init(_ value: T) { self._value = value }
    func update(_ transform: (inout T) -> Void) { lock.withLock { transform(&_value) } }
}

// MARK: - Helpers

private func makeResult(
    sessionId: String = "test-session-\(UUID().uuidString.prefix(6).lowercased())",
    state: AxionRunState = .completed
) -> AxionRunResult {
    AxionRunResult(
        sessionId: sessionId,
        task: "test task",
        state: state,
        totalSteps: 3,
        durationMs: 1500,
        runSucceeded: state == .completed,
        createdAt: Date()
    )
}

private func makeBuildConfig(task: String = "test task") -> AgentBuilder.BuildConfig {
    .forCLI(
        config: AxionConfig(apiKey: "test"),
        task: task, noMemory: true, noSkills: true,
        allowForeground: false, maxSteps: 1, maxTokens: 256,
        verbose: false, dryrun: true, fast: false
    )
}

// MARK: - Mock DaemonRuntimeManager (for ServerCommand seam tests)

final class MockDaemonRuntimeManager: DaemonRuntimeManaging, @unchecked Sendable {
    let result: AxionRunResult?
    let error: Error?
    private let _executeCount = LockedCounter()
    private let _shutdownCount = LockedCounter()

    var executeCount: Int { _executeCount.value }
    var shutdownCount: Int { _shutdownCount.value }

    init(result: AxionRunResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func executeRun(
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult {
        return try await executeRun(
            task: task, buildConfig: buildConfig, eventBus: eventBus,
            runOverrides: runOverrides, extraHandlers: []
        )
    }

    func executeRun(
        task: String,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus,
        runOverrides: AxionRuntime.RunOverrides,
        extraHandlers: [any EventHandler]
    ) async throws -> AxionRunResult {
        _executeCount.increment()
        if let error { throw error }
        guard let result else { fatalError("MockDaemonRuntimeManager: no result and no error") }
        return result
    }

    func executeSkill(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        eventBus: EventBus = EventBus(),
        runOverrides: AxionRuntime.RunOverrides = .default
    ) async throws -> AxionRunResult {
        _executeCount.increment()
        if let error { throw error }
        guard let result else { fatalError("MockDaemonRuntimeManager: no result and no error") }
        return result
    }

    func listActiveSessions() async -> [DaemonSessionInfo] { [] }
    func shutdown() async { _shutdownCount.increment() }
}

// MARK: - Tests

@Suite("DaemonRuntimeManager")
struct DaemonRuntimeManagerTests {

    @Test("Runtime created per executeRun call")
    func runtimeCreatedPerRequest() async throws {
        let expected = makeResult()
        let mock = MockDaemonRuntime(result: expected)

        let manager = DaemonRuntimeManager(traceDir: "/tmp/test-traces") { _ in mock }
        let eventBus = EventBus()

        let result = try await manager.executeRun(
            task: "test",
            buildConfig: makeBuildConfig(),
            eventBus: eventBus,
            runOverrides: AxionRuntime.RunOverrides.default
        )

        #expect(result.sessionId == expected.sessionId)
        #expect(mock.executeCount == 1)
    }

    @Test("Handlers registered — 2 API handlers (cost + trace)")
    func handlersRegistered() async throws {
        let mock = MockDaemonRuntime(result: makeResult())

        let manager = DaemonRuntimeManager(traceDir: "/tmp/test-traces") { _ in mock }
        let eventBus = EventBus()

        _ = try await manager.executeRun(
            task: "test",
            buildConfig: makeBuildConfig(),
            eventBus: eventBus,
            runOverrides: AxionRuntime.RunOverrides.default
        )

        #expect(mock.handlerCount == 2, "Should register CostEventHandler + TraceEventHandler")
    }

    @Test("Event loop lifecycle — execute completes without hanging")
    func eventLoopLifecycle() async throws {
        let mock = MockDaemonRuntime(result: makeResult())

        let manager = DaemonRuntimeManager(traceDir: "/tmp/test-traces") { _ in mock }
        let eventBus = EventBus()

        let result = try await manager.executeRun(
            task: "test",
            buildConfig: makeBuildConfig(),
            eventBus: eventBus,
            runOverrides: AxionRuntime.RunOverrides.default
        )

        #expect(result.state == .completed, "Execute should complete without hanging")
    }

    @Test("Multiple sequential runs complete successfully")
    func multipleSequentialRuns() async throws {
        let mock = MockDaemonRuntime(result: makeResult())

        let manager = DaemonRuntimeManager(traceDir: "/tmp/test-traces") { _ in mock }

        let r1 = try await manager.executeRun(
            task: "run1",
            buildConfig: makeBuildConfig(task: "run1"),
            eventBus: EventBus(),
            runOverrides: AxionRuntime.RunOverrides.default
        )
        let r2 = try await manager.executeRun(
            task: "run2",
            buildConfig: makeBuildConfig(task: "run2"),
            eventBus: EventBus(),
            runOverrides: AxionRuntime.RunOverrides.default
        )

        #expect(r1.state == .completed)
        #expect(r2.state == .completed)
        #expect(mock.executeCount == 2)
    }

    @Test("Concurrent executeRun calls complete independently")
    func concurrentExecution() async throws {
        let result1 = makeResult(sessionId: "session-alpha")
        let result2 = makeResult(sessionId: "session-beta")

        let mock1 = MockDaemonRuntime(result: result1)
        let mock2 = MockDaemonRuntime(result: result2)

        let callCount = AtomicBox(0)
        let manager = DaemonRuntimeManager(traceDir: "/tmp/test-traces") { _ in
            callCount.update { $0 += 1 }
            return callCount.value == 1 ? mock1 : mock2
        }

        async let r1 = manager.executeRun(
            task: "alpha",
            buildConfig: makeBuildConfig(task: "alpha"),
            eventBus: EventBus(),
            runOverrides: AxionRuntime.RunOverrides.default
        )
        async let r2 = manager.executeRun(
            task: "beta",
            buildConfig: makeBuildConfig(task: "beta"),
            eventBus: EventBus(),
            runOverrides: AxionRuntime.RunOverrides.default
        )

        let res1 = try await r1
        let res2 = try await r2

        #expect(res1.sessionId == "session-alpha")
        #expect(res2.sessionId == "session-beta")
        #expect(mock1.executeCount == 1)
        #expect(mock2.executeCount == 1)
    }

    @Test("Per-request EventBus isolation")
    func perRequestEventBusIsolation() async throws {
        let capturedBuses = AtomicBox<[ObjectIdentifier]>([])

        let manager = DaemonRuntimeManager(traceDir: "/tmp/test-traces") { bus in
            capturedBuses.update { $0.append(ObjectIdentifier(bus)) }
            return MockDaemonRuntime(result: makeResult())
        }

        let bus1 = EventBus()
        let bus2 = EventBus()

        _ = try await manager.executeRun(
            task: "run1",
            buildConfig: makeBuildConfig(),
            eventBus: bus1,
            runOverrides: AxionRuntime.RunOverrides.default
        )

        _ = try await manager.executeRun(
            task: "run2",
            buildConfig: makeBuildConfig(),
            eventBus: bus2,
            runOverrides: AxionRuntime.RunOverrides.default
        )

        let buses = capturedBuses.value
        #expect(buses.count == 2)
        #expect(buses[0] != buses[1], "Each run should receive a different EventBus")
    }

    @Test("Active session tracking after run")
    func activeSessionTracking() async throws {
        let manager = DaemonRuntimeManager(traceDir: "/tmp/test-traces") { _ in
            MockDaemonRuntime(result: makeResult(sessionId: "tracked-session"))
        }

        _ = try await manager.executeRun(
            task: "test",
            buildConfig: makeBuildConfig(),
            eventBus: EventBus(),
            runOverrides: AxionRuntime.RunOverrides.default
        )

        let sessions = await manager.listActiveSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].sessionId == "tracked-session")
        #expect(sessions[0].task == "test")
    }

    @Test("Failure propagation — runtime error is thrown")
    func failurePropagation() async {
        struct TestError: Error {}
        let mock = MockDaemonRuntime(error: TestError())
        let manager = DaemonRuntimeManager(traceDir: "/tmp/test-traces") { _ in mock }

        do {
            _ = try await manager.executeRun(
                task: "failing",
                buildConfig: makeBuildConfig(),
                eventBus: EventBus(),
                runOverrides: AxionRuntime.RunOverrides.default
            )
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
        }

        #expect(mock.stopEventLoopCount == 1, "Event loop should be stopped even on failure")
    }

    @Test("Shutdown clears active sessions")
    func shutdownClearsSessions() async throws {
        let manager = DaemonRuntimeManager(traceDir: "/tmp/test-traces") { _ in
            MockDaemonRuntime(result: makeResult())
        }

        _ = try await manager.executeRun(
            task: "test",
            buildConfig: makeBuildConfig(),
            eventBus: EventBus(),
            runOverrides: AxionRuntime.RunOverrides.default
        )

        var sessions = await manager.listActiveSessions()
        #expect(sessions.count == 1)

        await manager.shutdown()

        sessions = await manager.listActiveSessions()
        #expect(sessions.isEmpty, "Shutdown should clear active sessions")
    }

    @Test("Multiple runs tracked in active sessions")
    func multipleRunsTracked() async throws {
        let callIdx = AtomicBox(0)
        let manager = DaemonRuntimeManager(traceDir: "/tmp/test-traces") { _ in
            callIdx.update { $0 += 1 }
            return MockDaemonRuntime(result: makeResult(sessionId: "session-\(callIdx.value)"))
        }

        _ = try await manager.executeRun(
            task: "task1",
            buildConfig: makeBuildConfig(),
            eventBus: EventBus(),
            runOverrides: AxionRuntime.RunOverrides.default
        )
        _ = try await manager.executeRun(
            task: "task2",
            buildConfig: makeBuildConfig(),
            eventBus: EventBus(),
            runOverrides: AxionRuntime.RunOverrides.default
        )

        let sessions = await manager.listActiveSessions()
        #expect(sessions.count == 2)

        let tasks = Set(sessions.map(\.task))
        #expect(tasks == ["task1", "task2"])
    }
}

// MARK: - ServerCommand createRuntimeManager Seam Tests

@Suite("ServerCommand DaemonRuntimeManager Seam")
struct ServerCommandRuntimeManagerTests {

    @Test("createRuntimeManager seam returns working DaemonRuntimeManager")
    func seamReturnsWorkingManager() async throws {
        let manager = ServerCommand.createRuntimeManager("/tmp/test-traces")
        let sessions = await manager.listActiveSessions()
        #expect(sessions.isEmpty, "New manager should have no sessions")
    }

    @Test("createRuntimeManager seam can be overridden with mock")
    func seamCanBeOverridden() async throws {
        let mock = MockDaemonRuntimeManager(result: makeResult(sessionId: "seam-test"))
        let saved = ServerCommand.createRuntimeManager
        ServerCommand.createRuntimeManager = { _ in mock }
        defer { ServerCommand.createRuntimeManager = saved }

        let manager = ServerCommand.createRuntimeManager("/tmp")
        let result = try await manager.executeRun(
            task: "seam test",
            buildConfig: makeBuildConfig(),
            eventBus: EventBus(),
            runOverrides: AxionRuntime.RunOverrides.default
        )

        #expect(result.sessionId == "seam-test")
        #expect(mock.executeCount == 1)
    }

    @Test("Mock DaemonRuntimeManager propagates errors through seam")
    func seamErrorPropagation() async {
        struct TestError: Error {}
        let mock = MockDaemonRuntimeManager(error: TestError())
        let saved = ServerCommand.createRuntimeManager
        ServerCommand.createRuntimeManager = { _ in mock }
        defer { ServerCommand.createRuntimeManager = saved }

        let manager = ServerCommand.createRuntimeManager("/tmp")

        do {
            _ = try await manager.executeRun(
                task: "fail test",
                buildConfig: makeBuildConfig(),
                eventBus: EventBus(),
                runOverrides: AxionRuntime.RunOverrides.default
            )
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
        }

        #expect(mock.executeCount == 1)
    }
}
