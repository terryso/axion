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
}
