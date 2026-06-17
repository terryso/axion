import Testing
import Foundation
import ArgumentParser
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

// MARK: - Mock

actor MockResumeRuntime: AxionRuntimeResuming {
    let resumeResult: AxionRunResult?
    let resumeError: (any Error)?
    private(set) var handlerCount: Int = 0
    private(set) var startEventLoopCallCount: Int = 0
    private(set) var stopEventLoopCallCount: Int = 0
    private(set) var resumeCallCount: Int = 0
    private(set) var lastBuildConfig: AgentBuilder.BuildConfig?
    private(set) var lastRunOverrides: AxionRuntime.RunOverrides?

    init(resumeResult: AxionRunResult) {
        self.resumeResult = resumeResult
        self.resumeError = nil
    }

    init(resumeError: any Error) {
        self.resumeResult = nil
        self.resumeError = resumeError
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

    func resumeSession(
        _ sessionId: String,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides
    ) async throws -> AxionRunResult {
        resumeCallCount += 1
        lastBuildConfig = buildConfig
        lastRunOverrides = runOverrides
        if let error = resumeError { throw error }
        return resumeResult!
    }

    func executeSkill(
        skill: OpenAgentSDK.Skill,
        task: String,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig,
        runOverrides: AxionRuntime.RunOverrides = .default
    ) async throws -> AxionRunResult {
        if let error = resumeError { throw error }
        return resumeResult!
    }
}

// MARK: - Helpers

extension ResumeCommandTests {

    static func completedResult() -> AxionRunResult {
        AxionRunResult(
            sessionId: "resumed-session", task: "Continue the previous task.", state: .completed,
            totalSteps: 5, durationMs: 2000, runSucceeded: true,
            createdAt: Date()
        )
    }

    static func failedResult() -> AxionRunResult {
        AxionRunResult(
            sessionId: "resumed-session", task: "Continue the previous task.", state: .failed,
            totalSteps: 0, durationMs: 0, runSucceeded: false,
            errorMessage: "agent execution failed", createdAt: Date()
        )
    }

    private func withMockRuntime(
        _ mock: MockResumeRuntime,
        _ body: () async throws -> Void
    ) async throws {
        let savedFactory = ResumeCommand.createRuntime
        let savedNotify = ResumeCommand.notify
        ResumeCommand.createRuntime = { _ in mock }
        ResumeCommand.notify = { _, _, _ in }
        defer {
            ResumeCommand.createRuntime = savedFactory
            ResumeCommand.notify = savedNotify
        }
        try await body()
    }
}

// MARK: - Tests

@Suite("ResumeCommand", .serialized)
struct ResumeCommandTests {

    @Test("successful resume returns exit code 0")
    func successfulResumeReturnsExitCode0() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["test-session-id"])
            try await cmd.run()

            let callCount = await mock.resumeCallCount
            #expect(callCount == 1)
        }
    }

    @Test("failed resume throws ExitCode(1)")
    func failedResumeThrowsExitCode1() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.failedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["test-session-id"])
            do {
                try await cmd.run()
                Issue.record("Expected ExitCode(1) but no error was thrown")
            } catch is ExitCode {
                // Expected
            }

            let callCount = await mock.resumeCallCount
            #expect(callCount == 1)
        }
    }

    @Test("session not found throws error with session ID")
    func sessionNotFoundThrowsError() async throws {
        let mock = MockResumeRuntime(resumeError: AxionError.sessionNotFound(id: "bad-id"))
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["bad-id"])
            do {
                try await cmd.run()
                Issue.record("Expected error to be thrown")
            } catch let error as AxionError {
                if case .sessionNotFound(let id) = error {
                    #expect(id == "bad-id")
                } else {
                    Issue.record("Expected sessionNotFound error, got \(error)")
                }
            }
        }
    }

    @Test("session already running throws error with session ID")
    func sessionAlreadyRunningThrowsError() async throws {
        let mock = MockResumeRuntime(resumeError: AxionError.sessionAlreadyRunning(id: "running-id"))
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["running-id"])
            do {
                try await cmd.run()
                Issue.record("Expected error to be thrown")
            } catch let error as AxionError {
                if case .sessionAlreadyRunning(let id) = error {
                    #expect(id == "running-id")
                } else {
                    Issue.record("Expected sessionAlreadyRunning error, got \(error)")
                }
            }
        }
    }

    @Test("--fast flag propagates to buildConfig")
    func fastFlagPropagation() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["--fast", "test-session"])
            try await cmd.run()

            let config = await mock.lastBuildConfig
            #expect(config != nil)
            #expect(config!.fast == true)
        }
    }

    @Test("handler registration count matches expected")
    func handlerRegistrationCount() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["test-session"])
            try await cmd.run()

            let count = await mock.handlerCount
            #expect(count == 6, "Expected 6 handlers (Trace, VisualDelta, SeatMonitor, MemoryProcessing, Review, ToolCallLog)")
        }
    }

    @Test("event loop is stopped after successful execution")
    func eventLoopStoppedOnSuccess() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["test-session"])
            try await cmd.run()

            let stopCount = await mock.stopEventLoopCallCount
            #expect(stopCount == 1, "stopEventLoop should be called once after execution")
        }
    }

    @Test("event loop stops on resume error")
    func eventLoopCleanupOnError() async throws {
        struct TestError: Error {}
        let mock = MockResumeRuntime(resumeError: TestError())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["test-session"])
            do {
                try await cmd.run()
            } catch {
                // Expected
            }

            let stopCount = await mock.stopEventLoopCallCount
            #expect(stopCount == 1, "stopEventLoop should still be called when resumeSession throws")
        }
    }

    @Test("--no-memory flag propagates to buildConfig")
    func noMemoryFlagPropagation() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["--no-memory", "test-session"])
            try await cmd.run()

            let config = await mock.lastBuildConfig
            #expect(config != nil)
            #expect(config!.noMemory == true)
        }
    }

    @Test("--no-visual-delta and --no-review propagate to runOverrides")
    func overrideFlagsPropagation() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["--no-visual-delta", "--no-review", "test-session"])
            try await cmd.run()

            let overrides = await mock.lastRunOverrides
            #expect(overrides != nil)
            #expect(overrides!.noVisualDelta == true)
            #expect(overrides!.noReview == true)
        }
    }

    @Test("--max-steps flag propagates to buildConfig")
    func maxStepsFlagPropagation() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["--max-steps", "10", "test-session"])
            try await cmd.run()

            let config = await mock.lastBuildConfig
            #expect(config != nil)
            #expect(config!.maxSteps == 10)
        }
    }

    @Test("session ID is passed as first argument")
    func sessionIdArgument() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["my-session-123"])
            #expect(cmd.sessionId == "my-session-123")
            try await cmd.run()

            let callCount = await mock.resumeCallCount
            #expect(callCount == 1)
        }
    }

    @Test("--verbose flag propagates to buildConfig")
    func verboseFlagPropagation() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["--verbose", "test-session"])
            try await cmd.run()

            let config = await mock.lastBuildConfig
            #expect(config != nil)
            #expect(config!.verbose == true)
        }
    }

    @Test("--json flag propagates to runOverrides")
    func jsonFlagPropagation() async throws {
        let mock = MockResumeRuntime(resumeResult: Self.completedResult())
        try await withMockRuntime(mock) {
            var cmd = try ResumeCommand.parse(["--json", "test-session"])
            try await cmd.run()

            let overrides = await mock.lastRunOverrides
            #expect(overrides != nil)
            #expect(overrides!.json == true)
        }
    }
}
