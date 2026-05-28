import Testing
import Foundation
@testable import AxionCLI

@Suite("GatewayRunner")
struct GatewayRunnerTests {

    // MARK: - Mock Server

    /// Thread-safe mock server that blocks start() until stop() is called.
    actor MockGatewayServer: GatewayHTTPControlling {
        private var startCalled = false
        private var stopCalled = false
        private var continuation: CheckedContinuation<Void, Error>?

        var wasStartCalled: Bool { startCalled }
        var wasStopCalled: Bool { stopCalled }

        func start() async throws {
            startCalled = true
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
            }
        }

        func stop() async {
            stopCalled = true
            let cont = continuation
            continuation = nil
            cont?.resume()
        }
    }

    // MARK: - State Transitions (Task 3.1)

    @Test("GatewayRunner initial state is created")
    func initialStateIsCreated() async {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)
        #expect(await runner.currentState == .created)
    }

    @Test("GatewayRunner transitions to running after start")
    func transitionsToRunning() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let runnerTask = _Concurrency.Task { try await runner.start() }

        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        let state = await runner.currentState
        #expect(state == .running)

        await runner.stop(graceful: false)
        _ = try? await runnerTask.result
    }

    @Test("GatewayRunner transitions to stopped after stop")
    func transitionsToStopped() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let runnerTask = _Concurrency.Task { try await runner.start() }
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        await runner.stop(graceful: false)
        _ = try? await runnerTask.result

        let state = await runner.currentState
        #expect(state == .stopped)
    }

    // MARK: - Stop with Graceful Flag (Task 3.2)

    @Test("GatewayRunner stop graceful waits for active tasks")
    func stopGracefulWaitsForActiveTasks() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let runnerTask = _Concurrency.Task { try await runner.start() }
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        await runner.taskStarted()

        let finishTask = _Concurrency.Task {
            try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
            await runner.taskFinished()
        }

        await runner.stop(graceful: true)
        _ = try? await runnerTask.result
        _ = try? await finishTask.result

        let activeTasks = await runner.activeTaskCount
        #expect(activeTasks == 0)
    }

    @Test("GatewayRunner stop immediate does not wait")
    func stopImmediateDoesNotWait() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let runnerTask = _Concurrency.Task { try await runner.start() }
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        await runner.stop(graceful: false)
        _ = try? await runnerTask.result

        let state = await runner.currentState
        #expect(state == .stopped)
        let stopped = await server.wasStopCalled
        #expect(stopped)
    }

    @Test("GatewayRunner stop calls server stop")
    func stopCallsServerStop() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let runnerTask = _Concurrency.Task { try await runner.start() }
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        await runner.stop(graceful: false)
        _ = try? await runnerTask.result

        let stopped = await server.wasStopCalled
        #expect(stopped)
    }

    // MARK: - Active Task Tracking

    @Test("GatewayRunner tracks active task count")
    func tracksActiveTaskCount() async {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        #expect(await runner.activeTaskCount == 0)

        await runner.taskStarted()
        #expect(await runner.activeTaskCount == 1)

        await runner.taskStarted()
        #expect(await runner.activeTaskCount == 2)

        await runner.taskFinished()
        #expect(await runner.activeTaskCount == 1)

        await runner.taskFinished()
        #expect(await runner.activeTaskCount == 0)
    }

    // MARK: - Signal Handler Wiring (Task 3.4)

    @Test("GatewayRunner rejects new tasks when stopping")
    func rejectsNewTasksWhenStopping() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let runnerTask = _Concurrency.Task { try await runner.start() }
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        #expect(await runner.isAcceptingTasks == true)

        await runner.stop(graceful: true)
        _ = try? await runnerTask.result

        #expect(await runner.isAcceptingTasks == false)
    }

    @Test("GatewayRunner stop simulates signal-triggered shutdown")
    func signalHandlerTriggersShutdown() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let runnerTask = _Concurrency.Task { try await runner.start() }
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        await runner.stop(graceful: true)
        _ = try? await runnerTask.result

        let state = await runner.currentState
        #expect(state == .stopped)
    }
}
