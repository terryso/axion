import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

// MARK: - Mocks

struct MockRunExecutor: RunExecuting {
    let runResult: RunOrchestrator.RunResult
    let error: Error?

    init(runResult: RunOrchestrator.RunResult, error: Error? = nil) {
        self.runResult = runResult
        self.error = error
    }

    func execute(buildResult: AgentBuildResult, runConfig: RunOrchestrator.RunConfig) async throws -> RunOrchestrator.RunResult {
        if let error { throw error }
        return runResult
    }

    func generateRunId() -> String { "20260527-\(UUID().uuidString.prefix(6).lowercased())" }
}

struct MockAgentBuilder: AgentBuilding {
    let buildResult: AgentBuildResult?
    let error: Error?

    init(buildResult: AgentBuildResult? = nil, error: Error? = nil) {
        self.buildResult = buildResult
        self.error = error
    }

    func build(_ config: AgentBuilder.BuildConfig) async throws -> AgentBuildResult {
        if let error { throw error }
        guard let buildResult else { fatalError("MockAgentBuilder: no buildResult and no error") }
        return buildResult
    }
}

// MARK: - Helpers

extension AxionRuntimeTests {

    static func successResult() -> RunOrchestrator.RunResult {
        RunOrchestrator.RunResult(
            totalSteps: 3, durationMs: 1500, runSucceeded: true,
            externallyModified: false, takeoverEvent: nil, runCompleteContext: nil
        )
    }

    static func makeRuntime(
        executorResult: RunOrchestrator.RunResult? = nil,
        executorError: Error? = nil,
        builderResult: AgentBuildResult? = nil,
        builderError: Error? = nil,
        eventBus: EventBus? = nil
    ) -> AxionRuntime {
        let result = executorResult ?? successResult()
        let executor = MockRunExecutor(runResult: result, error: executorError)
        let builder = MockAgentBuilder(buildResult: builderResult, error: builderError)
        return AxionRuntime(eventBus: eventBus, executor: executor, builder: builder)
    }

    static func dummyBuildResult() -> AgentBuildResult {
        let options = AgentOptions(apiKey: "sk-test", model: "claude-sonnet-4-6", maxTurns: 1, maxTokens: 256)
        let agent = Agent(options: options)
        return AgentBuildResult(
            agent: agent,
            helperPath: "/tmp/axion-helper",
            memoryDir: "/tmp/axion-memory",
            systemPrompt: "test prompt",
            agentOptions: options,
            skillRegistry: SkillRegistry(),
            skillRegisteredCount: 0,
            runCompleteBox: RunCompleteContextBox(),
            reviewOrchestrator: nil,
            intelligentCurator: nil,
            usageStore: nil
        )
    }
}

// MARK: - Tests

@Suite("AxionRuntime")
struct AxionRuntimeTests {

    // MARK: - Initial state

    @Test("AxionRuntime initial state is created")
    func initialState() async {
        let runtime = Self.makeRuntime()
        let state = await runtime.state
        #expect(state == .created)
    }

    // MARK: - run() — COMPLETED on success

    @Test("run() transitions to COMPLETED on successful executor result")
    func runTransitionsToCompleted() async throws {
        let runtime = Self.makeRuntime()
        let buildResult = Self.dummyBuildResult()
        let runConfig = Self.makeRunConfig()

        let result = try await runtime.run(
            task: "test task",
            buildResult: buildResult,
            runConfig: runConfig
        )

        #expect(result.state == .completed)
        #expect(result.task == "test task")
        #expect(result.totalSteps == 3)
        #expect(result.durationMs == 1500)
        #expect(result.runSucceeded == true)
        #expect(result.sessionId.hasPrefix("20260527-"))

        let state = await runtime.state
        #expect(state == .completed)
    }

    // MARK: - run() — FAILED on executor error

    @Test("run() transitions to FAILED when executor throws")
    func runTransitionsToFailedOnThrow() async throws {
        let runtime = Self.makeRuntime(executorError: AxionError.runLocked(runId: "locked", pid: 1234))
        let buildResult = Self.dummyBuildResult()
        let runConfig = Self.makeRunConfig()

        let result = try await runtime.run(
            task: "test task",
            buildResult: buildResult,
            runConfig: runConfig
        )

        #expect(result.state == .failed)
        #expect(result.runSucceeded == false)
        #expect(result.totalSteps == 0)
        #expect(result.durationMs == 0)
        #expect(result.errorMessage != nil, "errorMessage should be populated on failure")

        let state = await runtime.state
        #expect(state == .failed)
    }

    // MARK: - run() — EventBus passthrough

    @Test("run() passes eventBus through RunConfig")
    func runEventBusPassthrough() async throws {
        let bus = EventBus()
        let runtime = Self.makeRuntime(eventBus: bus)
        let buildResult = Self.dummyBuildResult()

        let result = try await runtime.run(
            task: "test task",
            buildResult: buildResult,
            runConfig: Self.makeRunConfig()
        )

        #expect(result.state == .completed)
    }

    // MARK: - sessionId format

    @Test("sessionId follows expected format from executor")
    func sessionIdFormat() async throws {
        let runtime = Self.makeRuntime()
        let buildResult = Self.dummyBuildResult()

        let result = try await runtime.run(
            task: "test",
            buildResult: buildResult,
            runConfig: Self.makeRunConfig(task: "test")
        )

        let sid = result.sessionId
        #expect(sid.hasPrefix("20260527-"), "sessionId should follow YYYYMMDD-xxxxxx format")
    }

    // MARK: - createdAt is set

    @Test("run() sets createdAt on run")
    func createdAtIsSet() async throws {
        let runtime = Self.makeRuntime()
        let before = Date()
        let buildResult = Self.dummyBuildResult()

        let result = try await runtime.run(
            task: "test",
            buildResult: buildResult,
            runConfig: Self.makeRunConfig()
        )

        let after = Date()
        #expect(result.createdAt >= before)
        #expect(result.createdAt <= after)
    }

    // MARK: - execute() — COMPLETED

    @Test("execute() with successful build returns COMPLETED")
    func executeReturnsCompleted() async throws {
        let buildResult = Self.dummyBuildResult()
        let runtime = Self.makeRuntime(builderResult: buildResult)

        let result = try await runtime.execute(
            buildConfig: Self.makeBuildConfig()
        )

        #expect(result.state == .completed)
        #expect(result.task == "test task")
        #expect(!result.sessionId.isEmpty)

        let state = await runtime.state
        #expect(state == .completed)
    }

    // MARK: - execute() — FAILED on build error

    @Test("execute() with build failure returns FAILED with errorMessage")
    func executeBuildFailureReturnsFailed() async throws {
        let runtime = Self.makeRuntime(builderError: AxionError.missingApiKey(suggestion: "test"))

        let result = try await runtime.execute(buildConfig: Self.makeBuildConfig())

        #expect(result.state == .failed)
        #expect(result.runSucceeded == false)
        #expect(result.totalSteps == 0)
        #expect(result.durationMs == 0)
        #expect(result.errorMessage != nil, "errorMessage should be populated on build failure")

        let state = await runtime.state
        #expect(state == .failed)
    }

    // MARK: - execute() — default RunOverrides

    @Test("execute() with default RunOverrides succeeds")
    func executeDefaultOverrides() async throws {
        let buildResult = Self.dummyBuildResult()
        let runtime = Self.makeRuntime(builderResult: buildResult)

        let result = try await runtime.execute(
            buildConfig: Self.makeBuildConfig(),
            runOverrides: .default
        )

        #expect(result.state == .completed)
    }

    // MARK: - execute() — eventBus passthrough

    @Test("execute() passes eventBus through to RunConfig")
    func executeEventBusPassthrough() async throws {
        let bus = EventBus()
        let buildResult = Self.dummyBuildResult()
        let runtime = Self.makeRuntime(builderResult: buildResult, eventBus: bus)

        let result = try await runtime.execute(buildConfig: Self.makeBuildConfig())
        #expect(result.state == .completed)
    }

    // MARK: - execute() — task passthrough

    @Test("execute() uses buildConfig.task as runConfig.task")
    func executeTaskPassthrough() async throws {
        let buildResult = Self.dummyBuildResult()
        let runtime = Self.makeRuntime(builderResult: buildResult)

        let result = try await runtime.execute(
            buildConfig: Self.makeBuildConfig(task: "custom task")
        )

        #expect(result.task == "custom task")
    }

    // MARK: - run() still works after execute()

    @Test("run() method still works unchanged")
    func runStillWorksAfterExecute() async throws {
        let buildResult = Self.dummyBuildResult()
        let runtime = Self.makeRuntime(builderResult: buildResult)

        let result = try await runtime.run(
            task: "test task",
            buildResult: buildResult,
            runConfig: Self.makeRunConfig()
        )

        #expect(result.state == .completed)
        #expect(result.task == "test task")
    }

    // MARK: - Second run rejected by state guard

    @Test("second run() call on same instance is rejected by state guard")
    func runTwiceRejected() async throws {
        let runtime = Self.makeRuntime()
        let buildResult = Self.dummyBuildResult()

        let first = try await runtime.run(
            task: "first",
            buildResult: buildResult,
            runConfig: Self.makeRunConfig()
        )
        #expect(first.state == .completed)

        let second = try await runtime.run(
            task: "second",
            buildResult: buildResult,
            runConfig: Self.makeRunConfig()
        )
        #expect(second.state == .failed)
        #expect(second.errorMessage != nil)
    }

    // MARK: - externallyModified tracking

    @Test("externallyModified is false initially and false after mock success")
    func externallyModifiedState() async throws {
        let runtime = Self.makeRuntime()
        let externallyMod = await runtime.externallyModified
        #expect(externallyMod == false)

        let buildResult = Self.dummyBuildResult()
        let result = try await runtime.run(
            task: "test", buildResult: buildResult, runConfig: Self.makeRunConfig()
        )
        #expect(result.state == .completed)

        let afterRun = await runtime.externallyModified
        #expect(afterRun == false)
    }

    // MARK: - takeoverEvent tracking

    @Test("takeoverEvent is nil after mock success")
    func takeoverEventNilAfterSuccess() async throws {
        let runtime = Self.makeRuntime()
        let buildResult = Self.dummyBuildResult()
        let result = try await runtime.run(
            task: "test", buildResult: buildResult, runConfig: Self.makeRunConfig()
        )
        #expect(result.state == .completed)

        let takeover = await runtime.takeoverEvent
        #expect(takeover == nil)
    }

    // MARK: - createSession()

    @Test("createSession() writes axion-state.json with CREATED status")
    func createSessionWritesCreatedState() async throws {
        let runtime = Self.makeRuntime()
        let sid = try await runtime.createSession(task: "test task", config: AxionConfig(apiKey: "test"))

        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        let statePath = ((sessionsDir as NSString).appendingPathComponent(sid) as NSString)
            .appendingPathComponent("axion-state.json")

        let data = try #require(FileManager.default.contents(atPath: statePath),
                                 "axion-state.json should exist after createSession")
        let overlay = try JSONDecoder().decode(AxionStateOverlay.self, from: data)
        #expect(overlay.status == "created")
        #expect(overlay.totalSteps == 0)
    }

    // MARK: - listSessions()

    @Test("listSessions() returns array without crashing")
    func listSessionsNoCrash() async throws {
        let runtime = Self.makeRuntime()
        let sessions = try await runtime.listSessions()
        #expect(type(of: sessions) == [SessionInfo].self)
    }

    // MARK: - getSession()

    @Test("getSession() returns nil for non-existent session")
    func getSessionNil() async throws {
        let runtime = Self.makeRuntime()
        let result = try await runtime.getSession("nonexistent-session-\(UUID().uuidString)")
        #expect(result == nil)
    }

    // MARK: - State persistence

    @Test("run() writes axion-state.json with completed status")
    func runWritesCompletedState() async throws {
        let runtime = Self.makeRuntime()
        let buildResult = Self.dummyBuildResult()
        let result = try await runtime.run(
            task: "test", buildResult: buildResult, runConfig: Self.makeRunConfig()
        )
        #expect(result.state == .completed)

        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        let statePath = ((sessionsDir as NSString).appendingPathComponent(result.sessionId) as NSString)
            .appendingPathComponent("axion-state.json")

        guard let data = FileManager.default.contents(atPath: statePath) else {
            Issue.record("axion-state.json not found for session \(result.sessionId)")
            return
        }
        let overlay = try JSONDecoder().decode(AxionStateOverlay.self, from: data)
        #expect(overlay.status == "completed")
    }

    @Test("two runs write independent axion-state.json files")
    func twoRunsWriteStateFiles() async throws {
        let buildResult = Self.dummyBuildResult()

        let runtime1 = Self.makeRuntime()
        let result1 = try await runtime1.run(
            task: "r1", buildResult: buildResult, runConfig: Self.makeRunConfig()
        )
        #expect(result1.state == .completed)

        let runtime2 = Self.makeRuntime()
        let result2 = try await runtime2.run(
            task: "r2", buildResult: buildResult, runConfig: Self.makeRunConfig()
        )
        #expect(result2.state == .completed)

        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        let path1 = ((sessionsDir as NSString).appendingPathComponent(result1.sessionId) as NSString)
            .appendingPathComponent("axion-state.json")
        let path2 = ((sessionsDir as NSString).appendingPathComponent(result2.sessionId) as NSString)
            .appendingPathComponent("axion-state.json")

        #expect(FileManager.default.fileExists(atPath: path1))
        #expect(FileManager.default.fileExists(atPath: path2))
    }
    // MARK: - resumeSession()

    @Test("resumeSession() with valid completed session returns COMPLETED")
    func resumeSessionCompleted() async throws {
        let buildResult = Self.dummyBuildResult()
        let runtime = Self.makeRuntime(builderResult: buildResult)

        // Create a session with transcript so sessionStore.load() finds it
        let sid = try await runtime.createSession(task: "original task", config: AxionConfig(apiKey: "test"))
        try Self.writeTranscript(sessionId: sid, task: "original task")

        // Mark it as completed
        try await runtime.writeAxionState(sessionId: sid, status: "completed", totalSteps: 3, durationMs: 1000)

        let resumeConfig = Self.makeBuildConfig(task: "Continue the previous task.")
        let result = try await runtime.resumeSession(sid, buildConfig: resumeConfig)

        #expect(result.state == .completed)
        #expect(result.sessionId == sid)
        #expect(result.runSucceeded == true)

        let state = await runtime.state
        #expect(state == .completed)
    }

    @Test("resumeSession() with non-existent session throws sessionNotFound")
    func resumeSessionNotFound() async throws {
        let runtime = Self.makeRuntime()

        let resumeConfig = Self.makeBuildConfig()
        do {
            _ = try await runtime.resumeSession("nonexistent-\(UUID().uuidString)", buildConfig: resumeConfig)
            Issue.record("Expected sessionNotFound error")
        } catch let error as AxionError {
            if case .sessionNotFound = error {
                // Expected
            } else {
                Issue.record("Expected sessionNotFound, got \(error)")
            }
        }
    }

    @Test("resumeSession() with running session throws sessionAlreadyRunning")
    func resumeSessionAlreadyRunning() async throws {
        let runtime = Self.makeRuntime()

        // Create a session with transcript and mark it as running
        let sid = try await runtime.createSession(task: "running task", config: AxionConfig(apiKey: "test"))
        try Self.writeTranscript(sessionId: sid, task: "running task")
        try await runtime.writeAxionState(sessionId: sid, status: "running", totalSteps: 0, durationMs: 0)

        let resumeConfig = Self.makeBuildConfig()
        do {
            _ = try await runtime.resumeSession(sid, buildConfig: resumeConfig)
            Issue.record("Expected sessionAlreadyRunning error")
        } catch let error as AxionError {
            if case .sessionAlreadyRunning = error {
                // Expected
            } else {
                Issue.record("Expected sessionAlreadyRunning, got \(error)")
            }
        }
    }

    @Test("resumeSession() with build failure returns FAILED")
    func resumeSessionBuildFailure() async throws {
        let runtime = Self.makeRuntime(builderError: AxionError.missingApiKey(suggestion: "test"))

        // Create a session with transcript
        let sid = try await runtime.createSession(task: "original task", config: AxionConfig(apiKey: "test"))
        try Self.writeTranscript(sessionId: sid, task: "original task")

        let resumeConfig = Self.makeBuildConfig()
        let result = try await runtime.resumeSession(sid, buildConfig: resumeConfig)

        #expect(result.state == .failed)
        #expect(result.sessionId == sid)
        #expect(result.errorMessage != nil)
    }

    @Test("resumeSession() with failed session returns COMPLETED (AC #2)")
    func resumeFailedSession() async throws {
        let buildResult = Self.dummyBuildResult()
        let runtime = Self.makeRuntime(builderResult: buildResult)

        // Create a session and mark it as FAILED
        let sid = try await runtime.createSession(task: "failed task", config: AxionConfig(apiKey: "test"))
        try Self.writeTranscript(sessionId: sid, task: "failed task")
        try await runtime.writeAxionState(sessionId: sid, status: "failed", totalSteps: 2, durationMs: 500)

        let resumeConfig = Self.makeBuildConfig(task: "Continue the previous task.")
        let result = try await runtime.resumeSession(sid, buildConfig: resumeConfig)

        #expect(result.state == .completed)
        #expect(result.sessionId == sid)
        #expect(result.runSucceeded == true)
    }
}

// MARK: - Shared Helpers

extension AxionRuntimeTests {

    static func makeRunConfig(task: String = "test task") -> RunOrchestrator.RunConfig {
        RunOrchestrator.RunConfig(
            task: task, fast: false, dryrun: true, json: false,
            noMemory: true, noVisualDelta: true, allowForeground: false,
            maxSteps: 1, config: AxionConfig(apiKey: "test"),
            noReview: true, onReviewCompleted: nil, eventBus: nil
        )
    }

    static func makeBuildConfig(task: String = "test task") -> AgentBuilder.BuildConfig {
        .forCLI(
            config: AxionConfig(apiKey: "test"),
            task: task, noMemory: true, noSkills: true,
            allowForeground: false, maxSteps: 1, maxTokens: 256,
            verbose: false, dryrun: true, fast: false
        )
    }

    /// Writes a minimal transcript.json so SessionStore.load() can find the session.
    static func writeTranscript(sessionId: String, task: String) throws {
        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        let sessionDir = (sessionsDir as NSString).appendingPathComponent(sessionId)
        try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = dateFormatter.string(from: Date())

        let transcript: [String: Any] = [
            "metadata": [
                "id": sessionId,
                "cwd": "/tmp",
                "model": "claude-sonnet-4-6",
                "createdAt": now,
                "updatedAt": now,
                "messageCount": 2,
                "summary": task
            ],
            "messages": [
                ["role": "user", "content": task],
                ["role": "assistant", "content": "done"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: transcript, options: [.sortedKeys])
        let transcriptPath = (sessionDir as NSString).appendingPathComponent("transcript.json")
        FileManager.default.createFile(atPath: transcriptPath, contents: data)
    }
}
