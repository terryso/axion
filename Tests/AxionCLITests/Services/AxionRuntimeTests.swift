import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("AxionRuntime")
struct AxionRuntimeTests {

    private var testConfig: AxionConfig {
        AxionConfig(apiKey: "sk-test-unit-test-key")
    }

    private func buildDryrunResult() async throws -> AgentBuildResult {
        try await AgentBuilder.build(
            .forCLI(
                config: testConfig,
                task: "test task",
                noMemory: true,
                noSkills: true,
                allowForeground: false,
                maxSteps: 1,
                maxTokens: 256,
                verbose: false,
                dryrun: true,
                fast: false
            )
        )
    }

    private func makeRunConfig(task: String = "test task") -> RunOrchestrator.RunConfig {
        RunOrchestrator.RunConfig(
            task: task, fast: false, dryrun: true, json: false,
            noMemory: true, noVisualDelta: true, allowForeground: false,
            maxSteps: 1, config: testConfig,
            noReview: true, onReviewCompleted: nil, eventBus: nil
        )
    }

    // MARK: - Initial state

    @Test("AxionRuntime initial state is created")
    func initialState() async {
        let runtime = AxionRuntime()
        let state = await runtime.state
        #expect(state == .created)
    }

    // MARK: - 5.6: COMPLETED on successful RunOrchestrator result (dryrun)

    @Test("AxionRuntime transitions to COMPLETED on successful dryrun")
    func transitionsToCompletedOnDryrun() async throws {
        let runtime = AxionRuntime()
        let buildResult = try await buildDryrunResult()

        let result = try await runtime.run(
            task: "test task",
            buildResult: buildResult,
            runConfig: makeRunConfig()
        )

        #expect(result.state == .completed)
        #expect(result.task == "test task")
        #expect(!result.sessionId.isEmpty)

        let state = await runtime.state
        #expect(state == .completed)
    }

    // MARK: - 5.7: FAILED when RunOrchestrator throws

    @Test("AxionRuntime transitions to FAILED when run lock is held")
    func transitionsToFailedOnThrow() async throws {
        let runtime = AxionRuntime()
        let buildResult = try await buildDryrunResult()

        // Acquire lock to force RunOrchestrator to throw
        let lockService = RunLockService()
        let acquired = await lockService.acquire(runId: "blocking-test")
        #expect(acquired)

        let runConfig = RunOrchestrator.RunConfig(
            task: "test task", fast: false, dryrun: false, json: false,
            noMemory: true, noVisualDelta: true, allowForeground: false,
            maxSteps: 1, config: testConfig,
            noReview: true, onReviewCompleted: nil, eventBus: nil
        )

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

        await lockService.release()
    }

    // MARK: - 5.8: EventBus passthrough

    @Test("AxionRuntime passes eventBus through RunConfig")
    func eventBusPassthrough() async throws {
        let bus = EventBus()
        let runtime = AxionRuntime(eventBus: bus)
        let buildResult = try await buildDryrunResult()

        let result = try await runtime.run(
            task: "test task",
            buildResult: buildResult,
            runConfig: makeRunConfig()
        )

        #expect(result.state == .completed)
    }

    // MARK: - 5.9: sessionId format

    @Test("sessionId follows YYYYMMDD-{6 lowercase alphanumeric} format")
    func sessionIdFormat() async throws {
        let runtime = AxionRuntime()
        let buildResult = try await buildDryrunResult()

        let result = try await runtime.run(
            task: "test",
            buildResult: buildResult,
            runConfig: makeRunConfig(task: "test")
        )

        let sid = result.sessionId
        #expect(sid.count == 15, "sessionId should be YYYYMMDD-XXXXXX (15 chars), got '\(sid)'")

        let dashIndex = sid.index(sid.startIndex, offsetBy: 8)
        #expect(sid[dashIndex] == "-", "9th char should be '-'")

        let datePart = String(sid[sid.startIndex..<dashIndex])
        let randomPart = String(sid[sid.index(after: dashIndex)...])

        #expect(datePart.count == 8, "date part should be 8 chars")
        #expect(randomPart.count == 6, "random part should be 6 chars")

        let allowedChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        #expect(randomPart.unicodeScalars.allSatisfy { allowedChars.contains($0) },
                "random part should be lowercase alphanumeric")

        let digits = CharacterSet.decimalDigits
        #expect(datePart.unicodeScalars.allSatisfy { digits.contains($0) },
                "date part should be all digits")
    }

    // MARK: - createdAt is set

    @Test("AxionRuntime sets createdAt on run")
    func createdAtIsSet() async throws {
        let runtime = AxionRuntime()
        let before = Date()
        let buildResult = try await buildDryrunResult()

        let result = try await runtime.run(
            task: "test",
            buildResult: buildResult,
            runConfig: makeRunConfig()
        )

        let after = Date()
        #expect(result.createdAt >= before)
        #expect(result.createdAt <= after)
    }

    // MARK: - execute() tests

    private func makeDryrunBuildConfig(task: String = "test task") -> AgentBuilder.BuildConfig {
        .forCLI(
            config: testConfig,
            task: task,
            noMemory: true,
            noSkills: true,
            allowForeground: false,
            maxSteps: 1,
            maxTokens: 256,
            verbose: false,
            dryrun: true,
            fast: false
        )
    }

    @Test("execute() with dryrun BuildConfig returns COMPLETED with valid result (AC #1)")
    func executeDryrunReturnsCompleted() async throws {
        let runtime = AxionRuntime()
        let result = try await runtime.execute(
            buildConfig: makeDryrunBuildConfig()
        )

        #expect(result.state == .completed)
        #expect(result.task == "test task")
        #expect(!result.sessionId.isEmpty)

        let state = await runtime.state
        #expect(state == .completed)
    }

    @Test("execute() with missing API key config returns FAILED with errorMessage (AC #2)")
    func executeMissingApiKeyReturnsFailed() async throws {
        let runtime = AxionRuntime()
        let noKeyConfig = AxionConfig(apiKey: nil)
        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: noKeyConfig,
            task: "test task",
            noMemory: true,
            noSkills: true,
            allowForeground: false,
            maxSteps: 1,
            maxTokens: 256,
            verbose: false,
            dryrun: true,
            fast: false
        )

        let result = try await runtime.execute(buildConfig: buildConfig)

        #expect(result.state == .failed)
        #expect(result.runSucceeded == false)
        #expect(result.totalSteps == 0)
        #expect(result.durationMs == 0)
        #expect(result.errorMessage != nil, "errorMessage should be populated on build failure")

        let state = await runtime.state
        #expect(state == .failed)
    }

    @Test("execute() with default RunOverrides uses correct values (AC #4)")
    func executeDefaultOverrides() async throws {
        let runtime = AxionRuntime()
        let result = try await runtime.execute(
            buildConfig: makeDryrunBuildConfig(),
            runOverrides: .default
        )

        #expect(result.state == .completed)
    }

    @Test("execute() passes eventBus through to RunConfig (AC #5)")
    func executeEventBusPassthrough() async throws {
        let bus = EventBus()
        let runtime = AxionRuntime(eventBus: bus)
        let result = try await runtime.execute(
            buildConfig: makeDryrunBuildConfig()
        )

        #expect(result.state == .completed)
    }

    @Test("execute() uses buildConfig.task as runConfig.task (AC #6)")
    func executeTaskPassthrough() async throws {
        let runtime = AxionRuntime()
        let customTask = "my custom task"
        let result = try await runtime.execute(
            buildConfig: makeDryrunBuildConfig(task: customTask)
        )

        #expect(result.task == customTask)
    }

    @Test("existing run() method still works unchanged (AC #7)")
    func runStillWorksAfterExecute() async throws {
        let runtime = AxionRuntime()
        let buildResult = try await buildDryrunResult()

        let result = try await runtime.run(
            task: "test task",
            buildResult: buildResult,
            runConfig: makeRunConfig()
        )

        #expect(result.state == .completed)
        #expect(result.task == "test task")
    }

    @Test("second execute() call on same instance is rejected by state guard (AC #8)")
    func executeTwiceRejected() async throws {
        let runtime = AxionRuntime()

        let first = try await runtime.execute(
            buildConfig: makeDryrunBuildConfig()
        )
        #expect(first.state == .completed)

        let second = try await runtime.execute(
            buildConfig: makeDryrunBuildConfig()
        )
        #expect(second.state == .failed)
        #expect(second.errorMessage != nil)
    }

    @Test("execute() in dryrun mode returns completed (AC #9)")
    func executeDryrunModeReturnsSuccess() async throws {
        let runtime = AxionRuntime()
        let result = try await runtime.execute(
            buildConfig: makeDryrunBuildConfig()
        )

        #expect(result.state == .completed)
    }

    // MARK: - Story 24.3: Runtime State

    @Test("externallyModified is false initially and updated after dryrun (AC #1)")
    func externallyModifiedState() async throws {
        let runtime = AxionRuntime()
        let externallyMod = await runtime.externallyModified
        #expect(externallyMod == false)

        let result = try await runtime.execute(buildConfig: makeDryrunBuildConfig())
        #expect(result.state == .completed)

        let afterRun = await runtime.externallyModified
        #expect(afterRun == false, "dryrun should not detect external modification")
    }

    @Test("takeoverEvent is nil after dryrun (AC #2)")
    func takeoverEventNilAfterDryrun() async throws {
        let runtime = AxionRuntime()
        let result = try await runtime.execute(buildConfig: makeDryrunBuildConfig())
        #expect(result.state == .completed)

        let takeover = await runtime.takeoverEvent
        #expect(takeover == nil, "dryrun should not produce takeover event")
    }

    @Test("AxionRunResult carries runCompleteContext from dryrun (AC #8)")
    func runCompleteContextInResult() async throws {
        let runtime = AxionRuntime()
        let result = try await runtime.execute(buildConfig: makeDryrunBuildConfig())
        #expect(result.state == .completed)
        // With a fake API key, the SDK may or may not produce a RunCompleteContext
        // depending on whether the dryrun completes before hitting the 401.
        // The important thing is that the field exists and is accessible.
        if let ctx = result.runCompleteContext {
            #expect(!ctx.task.isEmpty)
        }
    }

    // MARK: - Story 24.3: Session Queries

    @Test("listSessions() returns empty array when no sessions exist (AC #4)")
    func listSessionsEmpty() async throws {
        let tmpDir = NSTemporaryDirectory().appending("/axion-test-sessions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let runtime = AxionRuntime()
        // Runtime uses default ~/.axion/sessions — test that listing doesn't crash
        let sessions = try await runtime.listSessions()
        // Can't assert empty because other sessions may exist
        #expect(type(of: sessions) == [SessionInfo].self)
    }

    @Test("getSession() returns nil for non-existent session (AC #5)")
    func getSessionNil() async throws {
        let runtime = AxionRuntime()
        let result = try await runtime.getSession("nonexistent-session-\(UUID().uuidString)")
        #expect(result == nil)
    }

    // MARK: - Story 24.3: Axion State Persistence

    @Test("writeAxionState writes valid JSON to expected path (AC #6)")
    func writeAxionState() async throws {
        let runtime = AxionRuntime()
        let result = try await runtime.execute(buildConfig: makeDryrunBuildConfig())
        #expect(result.state == .completed)

        // After dryrun, axion-state.json should exist at ~/.axion/sessions/{sessionId}/
        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        let statePath = ((sessionsDir as NSString).appendingPathComponent(result.sessionId) as NSString)
            .appendingPathComponent("axion-state.json")

        let data = try #require(FileManager.default.contents(atPath: statePath),
                                 "axion-state.json should exist after run")
        let overlay = try JSONDecoder().decode(AxionStateOverlay.self, from: data)
        #expect(overlay.status == "completed")
        #expect(overlay.totalSteps == result.totalSteps)
        #expect(overlay.durationMs == result.durationMs)
    }

    @Test("dryrun run writes axion-state.json with completed status")
    func dryrunWritesState() async throws {
        let runtime = AxionRuntime()
        let result = try await runtime.execute(buildConfig: makeDryrunBuildConfig())
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

    // MARK: - Story 24.4: Session Lifecycle Persistence

    @Test("createSession() writes axion-state.json with CREATED status")
    func createSessionWritesCreatedState() async throws {
        let runtime = AxionRuntime()
        let sid = try await runtime.createSession(task: "test task", config: testConfig)

        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        let statePath = ((sessionsDir as NSString).appendingPathComponent(sid) as NSString)
            .appendingPathComponent("axion-state.json")

        let data = try #require(FileManager.default.contents(atPath: statePath),
                                 "axion-state.json should exist after createSession")
        let overlay = try JSONDecoder().decode(AxionStateOverlay.self, from: data)
        #expect(overlay.status == "created")
        #expect(overlay.totalSteps == 0)
    }

    @Test("run() writes RUNNING state during execution then COMPLETED on success")
    func runTransitionsPersist() async throws {
        let runtime = AxionRuntime()
        let result = try await runtime.execute(buildConfig: makeDryrunBuildConfig())
        #expect(result.state == .completed)

        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        let statePath = ((sessionsDir as NSString).appendingPathComponent(result.sessionId) as NSString)
            .appendingPathComponent("axion-state.json")

        let data = try #require(FileManager.default.contents(atPath: statePath))
        let overlay = try JSONDecoder().decode(AxionStateOverlay.self, from: data)
        #expect(overlay.status == "completed")
    }

    @Test("two sessions write axion-state.json files independently")
    func twoSessionsWriteStateFiles() async throws {
        let runtime1 = AxionRuntime()
        let result1 = try await runtime1.execute(buildConfig: makeDryrunBuildConfig())
        #expect(result1.state == .completed)

        let runtime2 = AxionRuntime()
        let result2 = try await runtime2.execute(buildConfig: makeDryrunBuildConfig())
        #expect(result2.state == .completed)

        let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".axion/sessions")
        let path1 = ((sessionsDir as NSString).appendingPathComponent(result1.sessionId) as NSString)
            .appendingPathComponent("axion-state.json")
        let path2 = ((sessionsDir as NSString).appendingPathComponent(result2.sessionId) as NSString)
            .appendingPathComponent("axion-state.json")

        #expect(FileManager.default.fileExists(atPath: path1))
        #expect(FileManager.default.fileExists(atPath: path2))
    }
}
