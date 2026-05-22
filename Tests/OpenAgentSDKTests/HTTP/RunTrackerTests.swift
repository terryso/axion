import XCTest
@testable import OpenAgentSDK

final class RunTrackerTests: XCTestCase {

    private var tracker: RunTracker!

    override func setUp() {
        tracker = RunTracker()
    }

    // MARK: - Submit & Start

    func testSubmitRunReturnsRunId() async {
        let run = await tracker.submitRun(task: "analyze data")
        XCTAssertFalse(run.runId.isEmpty)
        XCTAssertEqual(run.runId.count, 15) // YYYYMMDD-xxxxxx
    }

    func testSubmitRunCreatesQueuedRun() async {
        let run = await tracker.submitRun(task: "test task")
        let tracked = await tracker.getRun(runId: run.runId)
        XCTAssertNotNil(tracked)
        XCTAssertEqual(tracked?.status, .queued)
        XCTAssertEqual(tracked?.task, "test task")
    }

    func testStartRunTransitionsQueuedToRunning() async throws {
        let runId = await tracker.submitRun(task: "test").runId
        try await tracker.startRun(runId: runId)
        let run = await tracker.getRun(runId: runId)
        XCTAssertEqual(run?.status, .running)
    }

    // MARK: - Complete

    func testCompleteRunTransitionsRunningToCompleted() async throws {
        let runId = await tracker.submitRun(task: "test").runId
        try await tracker.startRun(runId: runId)
        try await tracker.completeRun(runId: runId, resultText: "done", totalSteps: 3, durationMs: 1500)
        let run = await tracker.getRun(runId: runId)
        XCTAssertEqual(run?.status, .completed)
        XCTAssertEqual(run?.totalSteps, 3)
        XCTAssertEqual(run?.durationMs, 1500)
        XCTAssertEqual(run?.resultText, "done")
    }

    // MARK: - Fail

    func testFailRunTransitionsRunningToFailed() async throws {
        let runId = await tracker.submitRun(task: "test").runId
        try await tracker.startRun(runId: runId)
        try await tracker.failRun(runId: runId, error: "something broke")
        let run = await tracker.getRun(runId: runId)
        XCTAssertEqual(run?.status, .failed)
        XCTAssertEqual(run?.error, "something broke")
    }

    // MARK: - Cancel

    func testCancelRunTransitionsRunningToCancelled() async throws {
        let runId = await tracker.submitRun(task: "test").runId
        try await tracker.startRun(runId: runId)
        try await tracker.cancelRun(runId: runId)
        let run = await tracker.getRun(runId: runId)
        XCTAssertEqual(run?.status, .cancelled)
    }

    // MARK: - Invalid Transitions

    func testStartRunRejectsNonQueued() async throws {
        let runId = await tracker.submitRun(task: "test").runId
        try await tracker.startRun(runId: runId)
        do {
            try await tracker.startRun(runId: runId)
            XCTFail("Should have thrown")
        } catch let error as RunTrackerError {
            if case .invalidTransition(let from, let to) = error {
                XCTAssertEqual(from, .running)
                XCTAssertEqual(to, .running)
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCompleteRunRejectsQueued() async {
        let runId = await tracker.submitRun(task: "test").runId
        do {
            try await tracker.completeRun(runId: runId, resultText: nil, totalSteps: 0, durationMs: nil)
            XCTFail("Should have thrown")
        } catch let error as RunTrackerError {
            if case .invalidTransition(let from, let to) = error {
                XCTAssertEqual(from, .queued)
                XCTAssertEqual(to, .completed)
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRunNotFoundThrows() async {
        do {
            try await tracker.startRun(runId: "nonexistent")
            XCTFail("Should have thrown")
        } catch let error as RunTrackerError {
            if case .runNotFound(let id) = error {
                XCTAssertEqual(id, "nonexistent")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - List

    func testListRunsReturnsAllRuns() async {
        _ = await tracker.submitRun(task: "task1")
        _ = await tracker.submitRun(task: "task2")
        _ = await tracker.submitRun(task: "task3")
        let runs = await tracker.listRuns()
        XCTAssertEqual(runs.count, 3)
    }

    func testListRunsRespectsLimit() async {
        _ = await tracker.submitRun(task: "task1")
        _ = await tracker.submitRun(task: "task2")
        _ = await tracker.submitRun(task: "task3")
        let runs = await tracker.listRuns(limit: 2)
        XCTAssertEqual(runs.count, 2)
    }

    // MARK: - Restore

    func testRestoreRun() async {
        let run = TrackedRun(
            runId: "restored-id",
            status: .failed,
            task: "recovered task",
            createdAt: "2026-01-01T00:00:00Z",
            error: "server interrupted"
        )
        await tracker.restoreRun(run)
        let restored = await tracker.getRun(runId: "restored-id")
        XCTAssertEqual(restored?.status, .failed)
        XCTAssertEqual(restored?.task, "recovered task")
    }

    // MARK: - Additional Edge Cases

    func testCancelRunRejectsQueuedRun() async {
        let runId = await tracker.submitRun(task: "test").runId
        do {
            try await tracker.cancelRun(runId: runId)
            XCTFail("Should have thrown")
        } catch let error as RunTrackerError {
            if case .invalidTransition(let from, let to) = error {
                XCTAssertEqual(from, .queued)
                XCTAssertEqual(to, .cancelled)
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFailRunRejectsQueuedRun() async {
        let runId = await tracker.submitRun(task: "test").runId
        do {
            try await tracker.failRun(runId: runId, error: "fail")
            XCTFail("Should have thrown")
        } catch let error as RunTrackerError {
            if case .invalidTransition(let from, let to) = error {
                XCTAssertEqual(from, .queued)
                XCTAssertEqual(to, .failed)
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCompleteRunRejectsAlreadyCompleted() async throws {
        let runId = await tracker.submitRun(task: "test").runId
        try await tracker.startRun(runId: runId)
        try await tracker.completeRun(runId: runId, resultText: "done", totalSteps: 1, durationMs: nil)

        do {
            try await tracker.completeRun(runId: runId, resultText: nil, totalSteps: 0, durationMs: nil)
            XCTFail("Should have thrown")
        } catch let error as RunTrackerError {
            if case .invalidTransition(let from, let to) = error {
                XCTAssertEqual(from, .completed)
                XCTAssertEqual(to, .completed)
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListRunsSortedByCreationTime() async {
        _ = await tracker.submitRun(task: "first")
        try? await _Concurrency.Task.sleep(for: .milliseconds(10))
        _ = await tracker.submitRun(task: "second")
        try? await _Concurrency.Task.sleep(for: .milliseconds(10))
        _ = await tracker.submitRun(task: "third")

        let runs = await tracker.listRuns()
        XCTAssertEqual(runs.count, 3)
        // Newest first
        XCTAssertEqual(runs[0].task, "third")
        XCTAssertEqual(runs[1].task, "second")
        XCTAssertEqual(runs[2].task, "first")
    }

    func testRestoreOverwritesExistingRun() async {
        _ = await tracker.submitRun(task: "original")
        let runs = await tracker.listRuns()
        let originalRunId = runs.first!.runId

        let updatedRun = TrackedRun(
            runId: originalRunId,
            status: .completed,
            task: "restored",
            createdAt: "2026-01-01T00:00:00Z"
        )
        await tracker.restoreRun(updatedRun)

        let restored = await tracker.getRun(runId: originalRunId)
        XCTAssertEqual(restored?.task, "restored")
        XCTAssertEqual(restored?.status, .completed)
    }
}
