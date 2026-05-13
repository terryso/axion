import XCTest
@testable import AxionCLI

// [P0] ATDD GREEN-PHASE — Story 5.1 AC2/AC3/AC4

final class RunTrackerTests: XCTestCase {

    // MARK: - AC2: submitRun returns valid runId

    func test_submitRun_returnsNonEmptyRunId() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        XCTAssertFalse(runId.isEmpty, "submitRun should return a non-empty runId")
    }

    func test_submitRun_runIdMatchesExpectedFormat() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let regex = try NSRegularExpression(pattern: #"^\d{8}-[a-z0-9]{6}$"#)
        let range = NSRange(runId.startIndex..., in: runId)
        let match = regex.firstMatch(in: runId, range: range)
        XCTAssertNotNil(match, "runId should match format YYYYMMDD-{6random}, got: \(runId)")
    }

    // MARK: - AC3: getRun returns submitted task

    func test_getRun_returnsSubmittedRun() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let run = await tracker.getRun(runId: runId)

        XCTAssertNotNil(run, "getRun should return a run for a valid runId")
        XCTAssertEqual(run?.task, "open calculator")
        XCTAssertEqual(run?.status, .running)
        XCTAssertEqual(run?.runId, runId)
    }

    func test_getRun_nonExistentRunId_returnsNil() async throws {
        let tracker = RunTracker()

        let run = await tracker.getRun(runId: "nonexistent-id")

        XCTAssertNil(run, "getRun should return nil for non-existent runId")
    }

    // MARK: - AC4: updateRun correctly updates status

    func test_updateRun_updatesStatusToDone() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        await tracker.updateRun(
            runId: runId,
            status: .done,
            steps: [step],
            durationMs: 5000,
            replanCount: 0
        )

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try XCTUnwrap(run)
        XCTAssertEqual(unwrapped.status, .done)
        XCTAssertEqual(unwrapped.totalSteps, 1)
        XCTAssertEqual(unwrapped.durationMs, 5000)
        XCTAssertEqual(unwrapped.replanCount, 0)
        XCTAssertEqual(unwrapped.steps.count, 1)
    }

    func test_updateRun_updatesStatusToFailed() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        await tracker.updateRun(
            runId: runId,
            status: .failed,
            steps: [],
            durationMs: 1000,
            replanCount: 0
        )

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try XCTUnwrap(run)
        XCTAssertEqual(unwrapped.status, .failed)
    }

    func test_updateRun_preservesMultipleStepsInOrder() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let steps = [
            StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true),
            StepSummary(index: 1, tool: "click", purpose: "Input expression", success: true),
            StepSummary(index: 2, tool: "click", purpose: "Verify result", success: true),
        ]
        await tracker.updateRun(
            runId: runId,
            status: .done,
            steps: steps,
            durationMs: 8200,
            replanCount: 0
        )

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try XCTUnwrap(run)
        XCTAssertEqual(unwrapped.steps.count, 3)
        XCTAssertEqual(unwrapped.steps[0].tool, "launch_app")
        XCTAssertEqual(unwrapped.steps[1].tool, "click")
        XCTAssertEqual(unwrapped.steps[2].tool, "click")
    }

    // MARK: - AC3/AC4: listRuns

    func test_listRuns_returnsAllSubmittedRuns() async throws {
        let tracker = RunTracker()
        _ = await tracker.submitRun(task: "task 1", options: RunOptions(task: "task 1"))
        _ = await tracker.submitRun(task: "task 2", options: RunOptions(task: "task 2"))
        _ = await tracker.submitRun(task: "task 3", options: RunOptions(task: "task 3"))

        let runs = await tracker.listRuns()

        XCTAssertEqual(runs.count, 3, "listRuns should return all submitted runs")
    }

    func test_listRuns_emptyTracker_returnsEmptyArray() async throws {
        let tracker = RunTracker()

        let runs = await tracker.listRuns()

        XCTAssertTrue(runs.isEmpty, "listRuns on empty tracker should return empty array")
    }

    // MARK: - AC2: submitRun initial state

    func test_submitRun_initialState_isCorrect() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try XCTUnwrap(run)

        XCTAssertFalse(unwrapped.submittedAt.isEmpty, "submittedAt should be set")
        XCTAssertNil(unwrapped.completedAt, "completedAt should be nil for running task")
        XCTAssertTrue(unwrapped.steps.isEmpty, "steps should be empty for newly submitted run")
        XCTAssertEqual(unwrapped.totalSteps, 0, "totalSteps should be 0 for newly submitted run")
        XCTAssertNil(unwrapped.durationMs, "durationMs should be nil for running task")
    }

    // MARK: - SSE extension point (Story 5.2 prep)

    func test_updateRun_invokesOnStatusChangedCallback() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let callbackState = CallbackState()

        await tracker.setOnStatusChanged { invokedRunId, invokedStatus in
            callbackState.invoked = true
            callbackState.runId = invokedRunId
            callbackState.status = invokedStatus
        }

        await tracker.updateRun(
            runId: runId,
            status: .done,
            steps: [],
            durationMs: 1000,
            replanCount: 0
        )

        XCTAssertTrue(callbackState.invoked, "onStatusChanged should be invoked when status changes")
        XCTAssertEqual(callbackState.runId, runId)
        XCTAssertEqual(callbackState.status, .done)
    }
}

/// Thread-safe callback state holder for testing actor callbacks.
private final class CallbackState: @unchecked Sendable {
    var invoked: Bool = false
    var runId: String?
    var status: APIRunStatus?
}
