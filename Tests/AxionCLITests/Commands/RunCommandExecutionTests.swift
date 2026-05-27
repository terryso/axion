import Testing
import Foundation
import ArgumentParser
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

// MARK: - Mock

actor MockAxionRuntime: AxionRuntimeRunning {
    let executeResult: AxionRunResult?
    let executeError: (any Error)?
    private(set) var handlerCount: Int = 0
    private(set) var executeCallCount: Int = 0
    private(set) var startEventLoopCallCount: Int = 0
    private(set) var stopEventLoopCallCount: Int = 0

    init(executeResult: AxionRunResult) {
        self.executeResult = executeResult
        self.executeError = nil
    }

    init(executeError: any Error) {
        self.executeResult = nil
        self.executeError = executeError
    }

    func registerHandler(_ handler: any EventHandler) async {
        handlerCount += 1
    }

    func startEventLoop() async {
        startEventLoopCallCount += 1
    }

    func stopEventLoop() async {
        stopEventLoopCallCount += 1
    }

    func execute(
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult {
        executeCallCount += 1
        if let error = executeError { throw error }
        return executeResult!
    }

    func executeSkill(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides = .default
    ) async throws -> AxionRunResult {
        executeCallCount += 1
        if let error = executeError { throw error }
        return executeResult!
    }
}

// MARK: - Helpers

extension RunCommandExecutionTests {

    static func completedResult() -> AxionRunResult {
        AxionRunResult(
            sessionId: "test-session", task: "test", state: .completed,
            totalSteps: 1, durationMs: 100, runSucceeded: true,
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

    /// Injects mock runtime and skill override for the duration of `body`,
    /// restoring original values afterward.
    private func withMockRuntime(
        _ mock: MockAxionRuntime,
        skillOverride: (@Sendable (String, AxionConfig, Bool, Bool, Bool) async throws -> Void)? = nil,
        _ body: () async throws -> Void
    ) async throws {
        let savedFactory = RunCommand.createRuntime
        let savedSkill = RunCommand.skillExecutorOverride
        RunCommand.createRuntime = { _ in mock }
        RunCommand.skillExecutorOverride = skillOverride
        defer {
            RunCommand.createRuntime = savedFactory
            RunCommand.skillExecutorOverride = savedSkill
        }
        try await body()
    }
}

// MARK: - Tests

@Suite("RunCommand Execution", .serialized)
struct RunCommandExecutionTests {

    @Test("successful execution returns exit code 0")
    func successfulExecutionReturnsExitCode0() async throws {
        let mock = MockAxionRuntime(executeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try RunCommand.parse(["--no-skills", "--no-memory", "--dryrun", "test task"])
            try await cmd.run()

            let callCount = await mock.executeCallCount
            #expect(callCount == 1)
        }
    }

    @Test("failed execution throws ExitCode(1)")
    func failedExecutionThrowsExitCode1() async throws {
        let mock = MockAxionRuntime(executeResult: Self.failedResult())
        try await withMockRuntime(mock) {
            var cmd = try RunCommand.parse(["--no-skills", "--no-memory", "--dryrun", "test task"])
            do {
                try await cmd.run()
                Issue.record("Expected ExitCode(1) but no error was thrown")
            } catch is ExitCode {
                // Expected
            }

            let callCount = await mock.executeCallCount
            #expect(callCount == 1)
        }
    }

    @Test("skill override seam bypasses AxionRuntime")
    func skillOverrideSeamBypassesRuntime() async throws {
        let mock = MockAxionRuntime(executeResult: Self.completedResult())
        try await withMockRuntime(mock, skillOverride: { _, _, _, _, _ in /* no-op success */ }) {
            // /screenshot-analyze is a built-in skill — triggers fast-path.
            // Pass as single positional argument to avoid "unexpected extra value" error.
            var cmd = try RunCommand.parse(["/screenshot-analyze test"])
            try await cmd.run()

            let callCount = await mock.executeCallCount
            #expect(callCount == 0, "execute should NOT be called when skill fast-path is taken")
        }
    }

    @Test("--no-skills with /task still uses AxionRuntime")
    func noSkillsFlagBypassesSkillDetection() async throws {
        let mock = MockAxionRuntime(executeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try RunCommand.parse(["--no-skills", "--no-memory", "--dryrun", "/screenshot-analyze test"])
            try await cmd.run()

            let callCount = await mock.executeCallCount
            #expect(callCount == 1, "Runtime should be used when --no-skills is set")
        }
    }

    @Test("handler registration count matches expected 7")
    func handlerRegistrationCount() async throws {
        let mock = MockAxionRuntime(executeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try RunCommand.parse(["--no-skills", "--no-memory", "--dryrun", "test task"])
            try await cmd.run()

            let count = await mock.handlerCount
            #expect(count == 7, "Expected 7 handlers (Cost, VisualDelta, SeatMonitor, MemoryProcessing, Review, Notification, Trace)")
        }
    }

    @Test("event loop is stopped after successful execution")
    func eventLoopStoppedOnSuccess() async throws {
        let mock = MockAxionRuntime(executeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try RunCommand.parse(["--no-skills", "--no-memory", "--dryrun", "test task"])
            try await cmd.run()

            let stopCount = await mock.stopEventLoopCallCount
            #expect(stopCount == 1, "stopEventLoop should be called once after execution")
        }
    }

    @Test("event loop stops on execute error")
    func eventLoopCleanupOnError() async throws {
        struct TestError: Error {}
        let mock = MockAxionRuntime(executeError: TestError())
        try await withMockRuntime(mock) {
            var cmd = try RunCommand.parse(["--no-skills", "--no-memory", "--dryrun", "test task"])
            do {
                try await cmd.run()
                Issue.record("Expected error to be thrown")
            } catch {
                // Expected
            }

            let stopCount = await mock.stopEventLoopCallCount
            #expect(stopCount == 1, "stopEventLoop should still be called when execute throws")
        }
    }

    @Test("unknown skill name falls through to AxionRuntime")
    func unknownSkillFallsThroughToRuntime() async throws {
        let mock = MockAxionRuntime(executeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            // /nonexistent-skill-name-xyz will parse as a skill name but won't be found in registry
            var cmd = try RunCommand.parse(["/nonexistent-skill-name-xyz"])
            try await cmd.run()

            let callCount = await mock.executeCallCount
            #expect(callCount == 1, "Runtime should be used when skill name is not found in registry")
        }
    }
}
