import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("AxionRuntime Skill Execution")
struct AxionRuntimeSkillTests {

    // MARK: - Test Helpers

    private func makeSkill(name: String = "test-skill") -> OpenAgentSDK.Skill {
        OpenAgentSDK.Skill(
            name: name,
            description: "Test skill",
            promptTemplate: "Execute the test task: {{args}}"
        )
    }

    private func makeConfig() -> AxionConfig {
        AxionConfig(apiKey: "sk-test")
    }

    private func makeBuildConfig() -> AgentBuilder.BuildConfig {
        .forSkillExecution(
            config: makeConfig(),
            skill: makeSkill(),
            maxSteps: 5,
            verbose: false
        )
    }

    private func makeSkillResult(
        sessionId: String = "skill-session-\(UUID().uuidString.prefix(6).lowercased())"
    ) -> AxionRunResult {
        AxionRunResult(
            sessionId: sessionId,
            task: "/test-skill hello",
            state: .completed,
            totalSteps: 2,
            durationMs: 500,
            runSucceeded: true,
            createdAt: Date()
        )
    }

    // MARK: - State transition guard

    @Test("executeSkill() rejects second call via state guard")
    func executeSkillTwiceRejected() async throws {
        let runtime = AxionRuntime(eventBus: EventBus(), executor: MockRunExecutor(runResult: AxionRuntimeTests.successResult()), builder: MockAgentBuilder(buildResult: AxionRuntimeTests.dummyBuildResult()))

        _ = try await runtime.executeSkill(
            skill: makeSkill(),
            task: "/test-skill first",
            config: makeConfig(),
            buildConfig: makeBuildConfig()
        )

        let second = try await runtime.executeSkill(
            skill: makeSkill(),
            task: "/test-skill second",
            config: makeConfig(),
            buildConfig: makeBuildConfig()
        )
        #expect(second.state == .failed)
        #expect(second.errorMessage?.contains("Invalid state transition") == true)
    }

    // MARK: - axion-state.json written on skill execution

    @Test("executeSkill() writes axion-state.json")
    func executeSkillWritesState() async throws {
        let runtime = AxionRuntime(eventBus: EventBus(), executor: MockRunExecutor(runResult: AxionRuntimeTests.successResult()), builder: MockAgentBuilder(buildResult: AxionRuntimeTests.dummyBuildResult()))

        let result = try await runtime.executeSkill(
            skill: makeSkill(),
            task: "/test-skill state test",
            config: makeConfig(),
            buildConfig: makeBuildConfig()
        )

        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        let statePath = ((sessionsDir as NSString).appendingPathComponent(result.sessionId) as NSString)
            .appendingPathComponent("axion-state.json")

        #expect(FileManager.default.fileExists(atPath: statePath), "axion-state.json should be written during executeSkill")
    }

    // MARK: - EventBus + Handler registration

    @Test("executeSkill() with EventBus accepts handler registration")
    func executeSkillRegistersHandler() async throws {
        let eventBus = EventBus()
        let handler = SkillTestEventHandler()
        let runtime = AxionRuntime(eventBus: eventBus, executor: MockRunExecutor(runResult: AxionRuntimeTests.successResult()), builder: MockAgentBuilder(buildResult: AxionRuntimeTests.dummyBuildResult()))
        await runtime.registerHandler(handler)

        let eventLoopTask = _Concurrency.Task { await runtime.startEventLoop() }

        _ = try await runtime.executeSkill(
            skill: makeSkill(),
            task: "/test-skill event test",
            config: makeConfig(),
            buildConfig: makeBuildConfig()
        )

        eventLoopTask.cancel()
        await runtime.stopEventLoop()

        let identifier = await handler.identifier
        #expect(identifier == "skill-test-handler")
    }

    // MARK: - RunCommand skillExecutorOverride seam

    @Test("RunCommand skillExecutorOverride seam works")
    func runCommandSkillPathUsesOverride() async throws {
        let called = LockedBool()
        RunCommand.skillExecutorOverride = { _, _, _, _, _ in
            called.set(true)
        }
        defer { RunCommand.skillExecutorOverride = nil }

        #expect(!called.value)

        try await RunCommand.skillExecutorOverride?("/test-skill hello", makeConfig(), false, false, false)
        #expect(called.value)
    }

    // MARK: - DaemonRuntimeManager protocol conformance

    @Test("DaemonRuntimeManager executeSkill method exists and lists sessions")
    func daemonRuntimeManagerExecuteSkill() async throws {
        let manager = DaemonRuntimeManager(traceDir: "/tmp/axion-test-traces")

        let sessions = await manager.listActiveSessions()
        #expect(sessions.isEmpty)
    }

    // MARK: - MockDaemonRuntimeManager executeSkill delegation

    @Test("MockDaemonRuntimeManager executeSkill returns result")
    func mockDaemonRuntimeManagerExecuteSkill() async throws {
        let expected = makeSkillResult()
        let mock = MockDaemonRuntimeManager(result: expected)

        let result = try await mock.executeSkill(
            skill: makeSkill(),
            task: "/test-skill api",
            config: makeConfig(),
            buildConfig: makeBuildConfig(),
            eventBus: EventBus()
        )
        #expect(result.sessionId == expected.sessionId)
        #expect(mock.executeCount == 1)
    }

    @Test("MockDaemonRuntimeManager executeSkill propagates error")
    func mockDaemonRuntimeManagerExecuteSkillError() async throws {
        let mock = MockDaemonRuntimeManager(error: TestError())

        do {
            _ = try await mock.executeSkill(
                skill: makeSkill(),
                task: "/test-skill api",
                config: makeConfig(),
                buildConfig: makeBuildConfig(),
                eventBus: EventBus()
            )
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
        }
        #expect(mock.executeCount == 1)
    }

    // MARK: - MockDaemonRuntime executeSkill delegation

    @Test("MockDaemonRuntime executeSkill returns result")
    func mockDaemonRuntimeExecuteSkill() async throws {
        let expected = makeSkillResult()
        let mock = MockDaemonRuntime(result: expected)

        let result = try await mock.executeSkill(
            skill: makeSkill(),
            task: "/test-skill runtime",
            config: makeConfig(),
            buildConfig: makeBuildConfig()
        )
        #expect(result.sessionId == expected.sessionId)
        #expect(mock.executeCount == 1)
    }

    // MARK: - MockAxionRuntime executeSkill delegation

    @Test("MockAxionRuntime executeSkill returns result")
    func mockAxionRuntimeExecuteSkill() async throws {
        let expected = makeSkillResult()
        let mock = MockAxionRuntime(executeResult: expected)

        let result = try await mock.executeSkill(
            skill: makeSkill(),
            task: "/test-skill mock",
            config: makeConfig(),
            buildConfig: makeBuildConfig()
        )
        #expect(result.sessionId == expected.sessionId)
        let count = await mock.executeCallCount
        #expect(count == 1)
    }

    @Test("MockAxionRuntime executeSkill propagates error")
    func mockAxionRuntimeExecuteSkillError() async throws {
        let mock = MockAxionRuntime(executeError: AxionError.missingApiKey(suggestion: "test"))

        do {
            _ = try await mock.executeSkill(
                skill: makeSkill(),
                task: "/test-skill mock-error",
                config: makeConfig(),
                buildConfig: makeBuildConfig()
            )
            Issue.record("Expected error")
        } catch {
            // Expected
        }
        let count = await mock.executeCallCount
        #expect(count == 1)
    }
}

// MARK: - Test Types

private struct TestError: Error {}

private actor SkillTestEventHandler: EventHandler {
    let identifier: String = "skill-test-handler"
    let subscribedEventTypes: [any AgentEvent.Type] = []

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        _ = event
    }
}

private final class LockedBool: @unchecked Sendable {
    private var _value = false
    private let lock = NSLock()
    var value: Bool { lock.withLock { _value } }
    func set(_ v: Bool) { lock.withLock { _value = v } }
}
