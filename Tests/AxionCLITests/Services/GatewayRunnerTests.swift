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

    // MARK: - GatewayRunnerStatus Codable (Task 4.1)

    @Test("GatewayRunnerStatus Codable round-trip preserves all fields")
    func statusCodableRoundTrip() throws {
        let original = GatewayRunnerStatus(
            state: "running",
            activeTaskCount: 3,
            uptimeSeconds: 123.456,
            label: "dev.axion.gateway",
            pid: 12345,
            tgConnected: nil,
            lastReviewAt: "2026-05-29T10:00:00Z",
            lastReviewSummary: "新增 2 条记忆, 更新 1 个技能",
            lastCuratorAt: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GatewayRunnerStatus.self, from: data)

        #expect(decoded == original)
        #expect(decoded.state == "running")
        #expect(decoded.activeTaskCount == 3)
        #expect(decoded.uptimeSeconds == 123.456)
        #expect(decoded.label == "dev.axion.gateway")
        #expect(decoded.pid == 12345)
        #expect(decoded.tgConnected == nil)
        #expect(decoded.lastReviewAt == "2026-05-29T10:00:00Z")
        #expect(decoded.lastReviewSummary == "新增 2 条记忆, 更新 1 个技能")
        #expect(decoded.lastCuratorAt == nil)
    }

    @Test("GatewayRunnerStatus encodes all nullable fields as null in JSON")
    func statusEncodesNullFields() throws {
        let status = GatewayRunnerStatus(
            state: "running",
            activeTaskCount: 0,
            uptimeSeconds: 0,
            label: "dev.axion.gateway",
            pid: nil,
            tgConnected: nil,
            lastReviewAt: nil,
            lastCuratorAt: nil
        )

        let data = try JSONEncoder().encode(status)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"active_tasks\""))
        #expect(json.contains("\"uptime_seconds\""))
        #expect(json.contains("\"tg_connected\":null"))
        #expect(json.contains("\"last_review_at\":null"))
        #expect(json.contains("\"last_review_summary\":null"))
        #expect(json.contains("\"last_curator_at\":null"))
    }

    // MARK: - GatewayRunner.getStatus() (Task 4.2, 4.3)

    @Test("getStatus returns correct state and task count")
    func getStatusReturnsCorrectState() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        // Before start
        let beforeStart = await runner.getStatus()
        #expect(beforeStart.state == "created")
        #expect(beforeStart.activeTaskCount == 0)
        #expect(beforeStart.uptimeSeconds == 0)

        // Start the runner
        let runnerTask = _Concurrency.Task { try await runner.start() }
        try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        await runner.taskStarted()
        await runner.taskStarted()

        let whileRunning = await runner.getStatus()
        #expect(whileRunning.state == "running")
        #expect(whileRunning.activeTaskCount == 2)
        #expect(whileRunning.label == "dev.axion.gateway")

        await runner.stop(graceful: false)
        _ = try? await runnerTask.result
    }

    @Test("getStatus computes uptime from startTime")
    func getStatusComputesUptime() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        // Before start, uptime should be 0
        let beforeStart = await runner.getStatus()
        #expect(beforeStart.uptimeSeconds == 0)

        // Start and wait
        let runnerTask = _Concurrency.Task { try await runner.start() }
        try await _Concurrency.Task.sleep(nanoseconds: 150_000_000) // 150ms

        let whileRunning = await runner.getStatus()
        #expect(whileRunning.uptimeSeconds > 0)

        await runner.stop(graceful: false)
        _ = try? await runnerTask.result
    }

    // MARK: - Status Providers (Task 1.4)

    @Test("setStatusProviders populates optional fields in status")
    func setStatusProvidersPopulatesFields() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        await runner.setStatusProviders(
            tgStatus: { "connected" },
            reviewStatus: { "2026-05-29T10:00:00Z" },
            reviewSummary: { "新增 1 条记忆" },
            curatorStatus: nil
        )

        let status = await runner.getStatus()
        #expect(status.tgConnected == "connected")
        #expect(status.lastReviewAt == "2026-05-29T10:00:00Z")
        #expect(status.lastReviewSummary == "新增 1 条记忆")
        #expect(status.lastCuratorAt == nil)
    }

    @Test("getStatus without providers returns nil for optional fields")
    func getStatusWithoutProvidersReturnsNil() async {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let status = await runner.getStatus()
        #expect(status.tgConnected == nil)
        #expect(status.lastReviewAt == nil)
        #expect(status.lastReviewSummary == nil)
        #expect(status.lastCuratorAt == nil)
    }
}
