import Testing
import Foundation
@testable import AxionCLI

@Suite("RunTracker")
struct RunTrackerTests {

    @Test("submitRun returns non-empty runId")
    func submitRunReturnsNonEmptyRunId() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        #expect(!runId.isEmpty)
    }

    @Test("submitRun runId matches expected format")
    func submitRunRunIdMatchesExpectedFormat() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let regex = try NSRegularExpression(pattern: #"^\d{8}-[a-z0-9]{6}$"#)
        let range = NSRange(runId.startIndex..., in: runId)
        let match = regex.firstMatch(in: runId, range: range)
        #expect(match != nil)
    }

    @Test("getRun returns submitted run")
    func getRunReturnsSubmittedRun() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let run = await tracker.getRun(runId: runId)

        #expect(run != nil)
        #expect(run?.task == "open calculator")
        #expect(run?.status == .running)
        #expect(run?.runId == runId)
    }

    @Test("getRun with non-existent runId returns nil")
    func getRunNonExistentRunIdReturnsNil() async throws {
        let tracker = RunTracker()

        let run = await tracker.getRun(runId: "nonexistent-id")

        #expect(run == nil)
    }

    @Test("updateRun updates status to completed")
    func updateRunUpdatesStatusToCompleted() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        await tracker.updateRun(
            runId: runId,
            status: .completed,
            steps: [step],
            durationMs: 5000,
            replanCount: 0
        )

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try #require(run)
        #expect(unwrapped.status == .completed)
        #expect(unwrapped.totalSteps == 1)
        #expect(unwrapped.durationMs == 5000)
        #expect(unwrapped.replanCount == 0)
        #expect(unwrapped.steps.count == 1)
    }

    @Test("updateRun updates status to failed")
    func updateRunUpdatesStatusToFailed() async throws {
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
        let unwrapped = try #require(run)
        #expect(unwrapped.status == .failed)
    }

    @Test("updateRun preserves multiple steps in order")
    func updateRunPreservesMultipleStepsInOrder() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let steps = [
            StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true),
            StepSummary(index: 1, tool: "click", purpose: "Input expression", success: true),
            StepSummary(index: 2, tool: "click", purpose: "Verify result", success: true),
        ]
        await tracker.updateRun(
            runId: runId,
            status: .completed,
            steps: steps,
            durationMs: 8200,
            replanCount: 0
        )

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try #require(run)
        #expect(unwrapped.steps.count == 3)
        #expect(unwrapped.steps[0].tool == "launch_app")
        #expect(unwrapped.steps[1].tool == "click")
        #expect(unwrapped.steps[2].tool == "click")
    }

    @Test("listRuns returns all submitted runs")
    func listRunsReturnsAllSubmittedRuns() async throws {
        let tracker = RunTracker()
        _ = await tracker.submitRun(task: "task 1", options: RunOptions(task: "task 1"))
        _ = await tracker.submitRun(task: "task 2", options: RunOptions(task: "task 2"))
        _ = await tracker.submitRun(task: "task 3", options: RunOptions(task: "task 3"))

        let runs = await tracker.listRuns()

        #expect(runs.count == 3)
    }

    @Test("listRuns on empty tracker returns empty array")
    func listRunsEmptyTrackerReturnsEmptyArray() async throws {
        let tracker = RunTracker()

        let runs = await tracker.listRuns()

        #expect(runs.isEmpty)
    }

    @Test("submitRun initial state is correct")
    func submitRunInitialStateIsCorrect() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try #require(run)

        #expect(!unwrapped.submittedAt.isEmpty)
        #expect(unwrapped.completedAt == nil)
        #expect(unwrapped.steps.isEmpty)
        #expect(unwrapped.totalSteps == 0)
        #expect(unwrapped.durationMs == nil)
    }

    @Test("updateRun invokes onStatusChanged callback")
    func updateRunInvokesOnStatusChangedCallback() async throws {
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
            status: .completed,
            steps: [],
            durationMs: 1000,
            replanCount: 0
        )

        #expect(callbackState.invoked)
        #expect(callbackState.runId == runId)
        #expect(callbackState.status == .completed)
    }

    @Test("updateRun with EventBroadcaster emits runCompleted event")
    func updateRunWithEventBroadcasterEmitsRunCompletedEvent() async throws {
        let broadcaster = EventBroadcaster()
        let tracker = RunTracker(eventBroadcaster: broadcaster)
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let stream = await broadcaster.subscribe(runId: runId)

        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        await tracker.updateRun(
            runId: runId,
            status: .completed,
            steps: [step],
            durationMs: 5000,
            replanCount: 0
        )

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()

        #expect(received != nil)

        if case let .runCompleted(data) = received! {
            #expect(data.runId == runId)
            #expect(data.finalStatus == "completed")
            #expect(data.totalSteps == 1)
            #expect(data.durationMs == 5000)
            #expect(data.replanCount == 0)
        } else {
            Issue.record("Expected .runCompleted event, got different event type")
        }
    }

    @Test("Tracker with EventBroadcaster backward compatible listRuns")
    func trackerWithEventBroadcasterBackwardCompatibleListRuns() async throws {
        let broadcaster = EventBroadcaster()
        let tracker = RunTracker(eventBroadcaster: broadcaster)

        _ = await tracker.submitRun(task: "task 1", options: RunOptions(task: "task 1"))
        _ = await tracker.submitRun(task: "task 2", options: RunOptions(task: "task 2"))

        let runs = await tracker.listRuns()
        #expect(runs.count == 2)
    }

    @Test("Tracker with EventBroadcaster backward compatible getRun")
    func trackerWithEventBroadcasterBackwardCompatibleGetRun() async throws {
        let broadcaster = EventBroadcaster()
        let tracker = RunTracker(eventBroadcaster: broadcaster)
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let run = await tracker.getRun(runId: runId)
        #expect(run != nil)
        #expect(run?.task == "open calculator")
    }

    @Test("updateRunResult writes ApiTaskResult to tracked run")
    func updateRunResultWritesApiTaskResultToTrackedRun() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "read email", options: RunOptions(task: "read email"))

        let result = ApiTaskResult(kind: .answer, title: "read email", body: "Latest email from Alice", createdAt: "2026-05-17T10:00:05+08:00")
        await tracker.updateRunResult(runId: runId, result: result)

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try #require(run)
        #expect(unwrapped.result?.kind == .answer)
        #expect(unwrapped.result?.body == "Latest email from Alice")
    }

    @Test("updateRunIntervention writes InterventionData to tracked run")
    func updateRunInterventionWritesInterventionDataToTrackedRun() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "delete file", options: RunOptions(task: "delete file"))

        let intervention = InterventionData(reason: "需要确认", availableActions: ["resume", "abort"], blockingIssue: "弹窗阻塞")
        await tracker.updateRunIntervention(runId: runId, intervention: intervention)

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try #require(run)
        #expect(unwrapped.intervention?.reason == "需要确认")
        #expect(unwrapped.intervention?.availableActions == ["resume", "abort"])
    }

    @Test("submitRun with allowForeground option stores correctly")
    func submitRunWithAllowForegroundOptionStoresCorrectly() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "test", options: RunOptions(task: "test", allowForeground: true))

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try #require(run)
        #expect(unwrapped.allowForeground == true)
        #expect(unwrapped.live == true)
        #expect(unwrapped.schemaVersion == 1)
    }

    @Test("toStandardOutput on running run returns correct status")
    func toStandardOutputOnRunningRunReturnsCorrectStatus() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "test", options: RunOptions(task: "test"))

        let run = await tracker.getRun(runId: runId)
        let unwrapped = try #require(run)
        let output = unwrapped.toStandardOutput()

        #expect(output.status == .running)
        #expect(output.ok == true)
        #expect(output.live == true)
        #expect(output.endedAt == nil)
    }

    @Test("updateRun sets exitCode for completed and failed")
    func updateRunSetsExitCodeForCompletedAndFailed() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "test", options: RunOptions(task: "test"))

        await tracker.updateRun(runId: runId, status: .completed, steps: [], durationMs: 100, replanCount: 0)
        var run = await tracker.getRun(runId: runId)
        #expect(run?.exitCode == 0)

        await tracker.updateRun(runId: runId, status: .failed, steps: [], durationMs: 50, replanCount: 0, error: "boom")
        run = await tracker.getRun(runId: runId)
        #expect(run?.exitCode == 1)
        #expect(run?.error == "boom")
    }
}

/// Thread-safe callback state holder for testing actor callbacks.
private final class CallbackState: @unchecked Sendable {
    var invoked: Bool = false
    var runId: String?
    var status: APIRunStatus?
}
