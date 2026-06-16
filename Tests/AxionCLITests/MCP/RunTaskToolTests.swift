import Foundation
import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("RunTaskTool")
struct RunTaskToolTests {

    @Test("name is correct")
    func nameIsCorrect() {
        let (tool, _, _, lockDir) = createTool()
        defer { cleanup(lockDir) }
        #expect(tool.name == "run_task")
    }

    @Test("description is non-empty")
    func descriptionIsNonEmpty() {
        let (tool, _, _, lockDir) = createTool()
        defer { cleanup(lockDir) }
        #expect(!tool.description.isEmpty)
    }

    @Test("inputSchema contains task")
    func inputSchemaContainsTask() {
        let (tool, _, _, lockDir) = createTool()
        defer { cleanup(lockDir) }
        guard let props = tool.inputSchema["properties"] as? [String: Any] else {
            Issue.record("inputSchema should have 'properties'")
            return
        }
        #expect(props["task"] != nil)
    }

    @Test("inputSchema requires task")
    func inputSchemaRequiresTask() {
        let (tool, _, _, lockDir) = createTool()
        defer { cleanup(lockDir) }
        guard let required = tool.inputSchema["required"] as? [String] else {
            Issue.record("inputSchema should have 'required' array")
            return
        }
        #expect(required.contains("task"))
    }

    @Test("isReadOnly is false")
    func isReadOnlyIsFalse() {
        let (tool, _, _, lockDir) = createTool()
        defer { cleanup(lockDir) }
        #expect(!tool.isReadOnly)
    }

    @Test("call returns run_id")
    func callReturnsRunId() async throws {
        let (tool, _, _, lockDir) = createTool()
        defer { cleanup(lockDir) }
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["task": "open calculator"], context: context)

        #expect(!result.isError)
        #expect(result.content.contains("run_id"))
        #expect(result.content.contains("running"))
    }

    @Test("call with missing task returns error")
    func callMissingTaskReturnsError() async throws {
        let (tool, _, _, lockDir) = createTool()
        defer { cleanup(lockDir) }
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: [:], context: context)

        #expect(result.isError)
        #expect(result.content.contains("missing_task"))
    }

    @Test("call with empty task returns error")
    func callEmptyTaskReturnsError() async throws {
        let (tool, _, _, lockDir) = createTool()
        defer { cleanup(lockDir) }
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["task": ""], context: context)

        #expect(result.isError)
        #expect(result.content.contains("missing_task"))
    }

    @Test("call submits run to tracker")
    func callSubmitsRunToTracker() async throws {
        let (tool, tracker, _, lockDir) = createTool()
        defer { cleanup(lockDir) }
        let context = ToolContext(cwd: "/tmp", toolUseId: "test-id")

        let result = await tool.call(input: ["task": "open calculator"], context: context)

        let content = result.content
        let range = content.range(of: #"(?<=run_id":")([^"]+)"#, options: .regularExpression)
        #expect(range != nil)
        if let range = range {
            let runId = String(content[range])
            let run = await tracker.getRun(runId: runId)
            #expect(run != nil)
            #expect(run?.task == "open calculator")
        }
    }

    // MARK: - Run lock + status transition coverage (Epic 40 / RunTaskTool)

    @Test("call returns run_locked when an existing live run holds the lock")
    func callReturnsRunLockedWhenLockHeldByLiveRun() async throws {
        // [P1] Desktop-level exclusive run lock: prevents two live runs from driving the
        // desktop concurrently. Seed an existing lock held by a "live" process so acquire()
        // fails, then assert the tool surfaces a run_locked error that names the conflicting run.
        let tempLockDir = NSTemporaryDirectory() + "axion-test-lock-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempLockDir, withIntermediateDirectories: true)
        defer { cleanup(tempLockDir) }

        let conflictingRunId = "existing-run-xyz"
        let lockPath = (tempLockDir as NSString).appendingPathComponent("run.lock")
        let seededLock = RunLockData(runId: conflictingRunId, pid: 99_999, startedAt: "2026-06-16T00:00:00Z")
        try axionSortedEncoder.encode(seededLock).write(to: URL(fileURLWithPath: lockPath))

        let tracker = RunCoordinator()
        let queue = TaskQueue()
        // processAliveChecker always reports the holder as alive → acquire() must refuse.
        let runLockService = RunLockService(lockDirectory: tempLockDir, processAliveChecker: { _ in true })
        let tool = RunTaskTool(
            runTracker: tracker,
            taskQueue: queue,
            runLockService: runLockService,
            executeTask: { _ in Self.successfulQueryResult() }
        )

        let result = await tool.call(
            input: ["task": "open calculator"],
            context: ToolContext(cwd: "/tmp", toolUseId: "test-id")
        )

        #expect(result.isError)
        #expect(result.content.contains("run_locked"))
        // Error echoes the conflicting run id so callers know what is blocking them.
        #expect(result.content.contains(conflictingRunId))
    }

    @Test("call marks run failed when executeTask returns non-success")
    func callMarksRunFailedWhenExecuteTaskFails() async throws {
        // [P2] The enqueued closure maps a non-success QueryResult onto APIRunStatus.failed.
        let (tool, tracker, _, lockDir) = createTool(executeTask: { _ in Self.failingQueryResult() })
        defer { cleanup(lockDir) }

        let result = await tool.call(
            input: ["task": "open calculator"],
            context: ToolContext(cwd: "/tmp", toolUseId: "test-id")
        )

        // Submission itself succeeds; the failure surfaces in the run status, not the tool result.
        #expect(!result.isError)
        guard let runId = extractRunId(from: result.content) else {
            Issue.record("run_id not found in result content")
            return
        }
        await waitForRunStatus(tracker: tracker, runId: runId, expected: .failed)
    }

    @Test("call marks run completed and releases the lock when executeTask succeeds")
    func callMarksRunCompletedAndReleasesLock() async throws {
        // [P2] Success path: QueryResult.success → APIRunStatus.completed, and the run lock is released.
        let (tool, tracker, lockDir) = createToolInLockDir(executeTask: { _ in Self.successfulQueryResult() })
        defer { cleanup(lockDir) }
        let lockPath = (lockDir as NSString).appendingPathComponent("run.lock")

        let result = await tool.call(
            input: ["task": "open calculator"],
            context: ToolContext(cwd: "/tmp", toolUseId: "test-id")
        )

        #expect(!result.isError)
        guard let runId = extractRunId(from: result.content) else {
            Issue.record("run_id not found in result content")
            return
        }
        await waitForRunStatus(tracker: tracker, runId: runId, expected: .completed)

        // The enqueued closure calls runLockService.release() after updateRun; the lock file
        // written by acquire() must be gone once the closure has run to completion.
        let lockReleased = await waitForCondition { FileManager.default.fileExists(atPath: lockPath) == false }
        #expect(lockReleased, "run.lock should be removed after successful execution")
    }

    // MARK: - Helpers

    private func createTool(
        executeTask: @escaping @Sendable (String) async -> QueryResult = { _ in Self.successfulQueryResult() }
    ) -> (RunTaskTool, RunCoordinator, TaskQueue, String) {
        let tempLockDir = NSTemporaryDirectory() + "axion-test-lock-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempLockDir, withIntermediateDirectories: true)
        let testRunLockService = RunLockService(lockDirectory: tempLockDir, processAliveChecker: { _ in false })

        let tracker = RunCoordinator()
        let queue = TaskQueue()
        let tool = RunTaskTool(
            runTracker: tracker,
            taskQueue: queue,
            runLockService: testRunLockService,
            executeTask: executeTask
        )
        return (tool, tracker, queue, tempLockDir)
    }

    /// Creates a tool backed by a dedicated temp lock dir, returning the dir so tests can
    /// verify lock state (e.g. release after successful execution).
    private func createToolInLockDir(
        executeTask: @escaping @Sendable (String) async -> QueryResult
    ) -> (RunTaskTool, RunCoordinator, String) {
        let tempLockDir = NSTemporaryDirectory() + "axion-test-lock-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempLockDir, withIntermediateDirectories: true)
        let runLockService = RunLockService(lockDirectory: tempLockDir, processAliveChecker: { _ in false })

        let tracker = RunCoordinator()
        let queue = TaskQueue()
        let tool = RunTaskTool(
            runTracker: tracker,
            taskQueue: queue,
            runLockService: runLockService,
            executeTask: executeTask
        )
        return (tool, tracker, tempLockDir)
    }

    /// Removes a temp lock dir created by `createTool`/`createToolInLockDir`/inline seeding.
    /// Best-effort: ignores missing files. Aligns with AgentBuilder* test hygiene.
    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func extractRunId(from content: String) -> String? {
        // Capture the run_id value from the JSON result, e.g. ..."run_id":"20260616-abc123"...
        guard let range = content.range(of: #"(?<=run_id":")([^"]+)"#, options: .regularExpression) else {
            return nil
        }
        return String(content[range])
    }

    /// Polls the tracker until `runId` reaches `expected`, or records an issue after the timeout.
    /// The enqueued work completes in microseconds, so the 500ms budget never trips in practice —
    /// this is a standard eventual-consistency pattern for fire-and-forget TaskQueue dispatch.
    private func waitForRunStatus(
        tracker: RunCoordinator,
        runId: String,
        expected: APIRunStatus,
        timeoutMs: Int = 500
    ) async {
        for _ in 0..<timeoutMs {
            if let run = await tracker.getRun(runId: runId), run.status == expected {
                return
            }
            try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000) // 1ms (OpenAgentSDK Task name clash → _Concurrency.Task)
        }
        let final = await tracker.getRun(runId: runId)?.status
        Issue.record("Run \(runId) never reached \(expected) (final: \(String(describing: final)))")
    }

    /// Polls `check` until it returns true, or gives up after the timeout. Returns the final check result.
    private func waitForCondition(timeoutMs: Int = 500, check: @escaping @Sendable () -> Bool) async -> Bool {
        for _ in 0..<timeoutMs {
            if check() { return true }
            try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000) // 1ms (OpenAgentSDK Task name clash → _Concurrency.Task)
        }
        return check()
    }

    private static func successfulQueryResult() -> QueryResult {
        QueryResult(
            text: "ok",
            usage: TokenUsage(inputTokens: 0, outputTokens: 0),
            numTurns: 1,
            durationMs: 0,
            messages: [],
            status: .success
        )
    }

    private static func failingQueryResult() -> QueryResult {
        QueryResult(
            text: "boom",
            usage: TokenUsage(inputTokens: 0, outputTokens: 0),
            numTurns: 1,
            durationMs: 0,
            messages: [],
            status: .errorDuringExecution
        )
    }
}
