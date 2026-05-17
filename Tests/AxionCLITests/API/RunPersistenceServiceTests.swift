import Testing
import Foundation
@testable import AxionCLI

@Suite("RunPersistenceService")
struct RunPersistenceServiceTests {

    /// Helper: create a temp directory for each test.
    private func makeTempDir() -> String {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("axion-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Helper: create a sample TrackedRun.
    private func makeRun(
        runId: String = "20260517-abc123",
        status: APIRunStatus = .running,
        task: String = "open calculator"
    ) -> TrackedRun {
        TrackedRun(
            runId: runId,
            task: task,
            status: status,
            submittedAt: "2026-05-17T10:00:00.000+08:00",
            completedAt: status == .completed ? "2026-05-17T10:01:00.000+08:00" : nil,
            totalSteps: status == .completed ? 1 : 0,
            durationMs: status == .completed ? 5000 : nil,
            steps: status == .completed
                ? [StepSummary(index: 0, tool: "launch_app", purpose: "Launch", success: true)]
                : [],
            live: true,
            allowForeground: false,
            error: status == .failed ? "something went wrong" : nil
        )
    }

    // MARK: - 7.2 persistRecord + loadRecord round-trip

    @Test("persistRecord and loadRecord round-trip preserves all fields")
    func persistRecordLoadRecordRoundTrip() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let original = makeRun(
            runId: "20260517-roundtrip",
            status: .completed,
            task: "open Safari and search"
        )

        try service.persistRecord(original)
        let loaded = service.loadRecord(runId: "20260517-roundtrip")

        #expect(loaded != nil)
        let unwrapped = try #require(loaded)
        #expect(unwrapped.runId == original.runId)
        #expect(unwrapped.task == original.task)
        #expect(unwrapped.status == original.status)
        #expect(unwrapped.submittedAt == original.submittedAt)
        #expect(unwrapped.completedAt == original.completedAt)
        #expect(unwrapped.totalSteps == original.totalSteps)
        #expect(unwrapped.durationMs == original.durationMs)
        #expect(unwrapped.live == original.live)
        #expect(unwrapped.allowForeground == original.allowForeground)
        #expect(unwrapped.steps.count == 1)
        #expect(unwrapped.steps[0].tool == "launch_app")
    }

    // MARK: - 7.3 persistEvent + loadEvents

    @Test("persistEvent and loadEvents preserves order and content")
    func persistEventLoadEventsPreservesOrder() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let runId = "20260517-events01"

        let event1 = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        let event2 = SSEEvent.stepCompleted(StepCompletedData(
            stepIndex: 0, tool: "launch_app", purpose: "Launch", success: true, durationMs: 500
        ))
        let event3 = SSEEvent.runCompleted(RunCompletedData(
            runId: runId, finalStatus: "completed", totalSteps: 1, durationMs: 500, replanCount: 0
        ))

        try service.persistEvent(runId: runId, event: event1)
        try service.persistEvent(runId: runId, event: event2)
        try service.persistEvent(runId: runId, event: event3)

        let events = service.loadEvents(runId: runId)
        #expect(events.count == 3)

        if case let .stepStarted(data) = events[0] {
            #expect(data.stepIndex == 0)
            #expect(data.tool == "launch_app")
        } else {
            Issue.record("First event should be stepStarted")
        }

        if case let .stepCompleted(data) = events[1] {
            #expect(data.stepIndex == 0)
            #expect(data.success == true)
        } else {
            Issue.record("Second event should be stepCompleted")
        }

        if case let .runCompleted(data) = events[2] {
            #expect(data.runId == runId)
            #expect(data.finalStatus == "completed")
        } else {
            Issue.record("Third event should be runCompleted")
        }
    }

    // MARK: - 7.4 Atomic write verification

    @Test("persistRecord creates api-output.json (not temp file)")
    func persistRecordCreatesCorrectFile() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let run = makeRun(runId: "20260517-atomic01")

        try service.persistRecord(run)

        let runDir = (tempDir as NSString).appendingPathComponent("20260517-atomic01")
        let jsonPath = (runDir as NSString).appendingPathComponent("api-output.json")
        let tmpPath = (runDir as NSString).appendingPathComponent("api-output.json.tmp")

        #expect(FileManager.default.fileExists(atPath: jsonPath))
        #expect(!FileManager.default.fileExists(atPath: tmpPath))

        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        let decoded = try JSONDecoder().decode(TrackedRun.self, from: data)
        #expect(decoded.runId == "20260517-atomic01")
    }

    // MARK: - 7.5 loadAllPersistedRuns

    @Test("loadAllPersistedRuns loads all run directories")
    func loadAllPersistedRunsLoadsAllDirectories() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)

        let run1 = makeRun(runId: "20260517-multi01", status: .completed)
        let run2 = makeRun(runId: "20260517-multi02", status: .failed, task: "task two")
        let run3 = makeRun(runId: "20260517-multi03", status: .running, task: "task three")

        try service.persistRecord(run1)
        try service.persistRecord(run2)
        try service.persistRecord(run3)

        let allRuns = service.loadAllPersistedRuns()
        #expect(allRuns.count == 3)

        let ids = Set(allRuns.map(\.runId))
        #expect(ids.contains("20260517-multi01"))
        #expect(ids.contains("20260517-multi02"))
        #expect(ids.contains("20260517-multi03"))
    }

    // MARK: - 7.6 persistRecordSafely failure handling

    @Test("persistRecordSafely does not crash on invalid path")
    func persistRecordSafelyDoesNotCrashOnInvalidPath() {
        let service = RunPersistenceService(baseDirectory: "/nonexistent/deeply/nested/invalid/path")
        let run = makeRun(runId: "20260517-fail01")

        // Should not throw — just log warning
        service.persistRecordSafely(run)

        // Verify no crash and record is not persisted
        let loaded = service.loadRecord(runId: "20260517-fail01")
        #expect(loaded == nil)
    }

    // MARK: - 7.7 Recovery: running/queued → failed

    @Test("Recovery marks running runs as failed")
    func recoveryMarksRunningAsFailed() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        let run = makeRun(runId: "20260517-running01", status: .running)
        try service.persistRecord(run)

        await RunRecoveryService.recover(from: tracker, persistenceService: service, eventBroadcaster: broadcaster)

        let recovered = await tracker.getRun(runId: "20260517-running01")
        let unwrapped = try #require(recovered)
        #expect(unwrapped.status == .failed)
        #expect(unwrapped.error == "server interrupted")
        #expect(unwrapped.exitCode == 1)

        // Also verify persisted file is updated
        let fromDisk = service.loadRecord(runId: "20260517-running01")
        #expect(fromDisk?.status == .failed)
    }

    @Test("Recovery marks queued runs as failed")
    func recoveryMarksQueuedAsFailed() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        let run = makeRun(runId: "20260517-queued01", status: .queued)
        try service.persistRecord(run)

        await RunRecoveryService.recover(from: tracker, persistenceService: service, eventBroadcaster: broadcaster)

        let recovered = await tracker.getRun(runId: "20260517-queued01")
        #expect(recovered?.status == .failed)
        #expect(recovered?.error == "server interrupted")
    }

    @Test("Recovery marks resuming runs as failed")
    func recoveryMarksResumingAsFailed() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        let run = makeRun(runId: "20260517-resuming01", status: .resuming)
        try service.persistRecord(run)

        await RunRecoveryService.recover(from: tracker, persistenceService: service, eventBroadcaster: broadcaster)

        let recovered = await tracker.getRun(runId: "20260517-resuming01")
        #expect(recovered?.status == .failed)
        #expect(recovered?.error == "server interrupted")
    }

    @Test("Recovery marks userTakeover runs as failed")
    func recoveryMarksUserTakeoverAsFailed() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        let run = makeRun(runId: "20260517-takeover01", status: .userTakeover)
        try service.persistRecord(run)

        await RunRecoveryService.recover(from: tracker, persistenceService: service, eventBroadcaster: broadcaster)

        let recovered = await tracker.getRun(runId: "20260517-takeover01")
        #expect(recovered?.status == .failed)
        #expect(recovered?.error == "server interrupted")
    }

    // MARK: - 7.8 intervention_needed preserved

    @Test("Recovery preserves intervention_needed status")
    func recoveryPreservesInterventionNeeded() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        var run = makeRun(runId: "20260517-interv01", status: .interventionNeeded)
        run.intervention = InterventionData(
            reason: "需要确认", availableActions: ["resume", "abort"], blockingIssue: "弹窗阻塞"
        )
        try service.persistRecord(run)

        await RunRecoveryService.recover(from: tracker, persistenceService: service, eventBroadcaster: broadcaster)

        let recovered = await tracker.getRun(runId: "20260517-interv01")
        #expect(recovered?.status == .interventionNeeded)
        #expect(recovered?.intervention?.reason == "需要确认")
    }

    // MARK: - 7.9 completed/failed/cancelled preserved

    @Test("Recovery preserves completed status")
    func recoveryPreservesCompleted() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        let run = makeRun(runId: "20260517-done01", status: .completed)
        try service.persistRecord(run)

        await RunRecoveryService.recover(from: tracker, persistenceService: service, eventBroadcaster: broadcaster)

        let recovered = await tracker.getRun(runId: "20260517-done01")
        #expect(recovered?.status == .completed)
    }

    @Test("Recovery preserves failed status")
    func recoveryPreservesFailed() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        let run = makeRun(runId: "20260517-failed01", status: .failed)
        try service.persistRecord(run)

        await RunRecoveryService.recover(from: tracker, persistenceService: service, eventBroadcaster: broadcaster)

        let recovered = await tracker.getRun(runId: "20260517-failed01")
        #expect(recovered?.status == .failed)
    }

    @Test("Recovery preserves cancelled status")
    func recoveryPreservesCancelled() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        let run = makeRun(runId: "20260517-cancel01", status: .cancelled)
        try service.persistRecord(run)

        await RunRecoveryService.recover(from: tracker, persistenceService: service, eventBroadcaster: broadcaster)

        let recovered = await tracker.getRun(runId: "20260517-cancel01")
        #expect(recovered?.status == .cancelled)
    }

    // MARK: - 7.10 RunTracker integration

    @Test("RunTracker with persistenceService writes api-output.json on submitRun")
    func runTrackerWritesOnSubmitRun() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let tracker = RunTracker(persistenceService: service)

        let runId = await tracker.submitRun(task: "test task", options: RunOptions(task: "test task"))

        let loaded = service.loadRecord(runId: runId)
        #expect(loaded != nil)
        #expect(loaded?.task == "test task")
        #expect(loaded?.status == .running)
    }

    @Test("RunTracker with persistenceService writes api-output.json on updateRun")
    func runTrackerWritesOnUpdateRun() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        let runId = await tracker.submitRun(task: "test task", options: RunOptions(task: "test task"))
        await tracker.updateRun(
            runId: runId,
            status: .completed,
            steps: [StepSummary(index: 0, tool: "launch_app", purpose: "Launch", success: true)],
            durationMs: 3000,
            replanCount: 0
        )

        let loaded = service.loadRecord(runId: runId)
        #expect(loaded != nil)
        #expect(loaded?.status == .completed)
        #expect(loaded?.totalSteps == 1)
    }

    // MARK: - 7.11 EventBroadcaster integration

    @Test("EventBroadcaster with persistenceService writes api-events.jsonl on emit")
    func eventBroadcasterWritesOnEmit() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)

        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        await broadcaster.emit(runId: "20260517-evtest01", event: event)

        let events = service.loadEvents(runId: "20260517-evtest01")
        #expect(events.count == 1)

        if case let .stepStarted(data) = events[0] {
            #expect(data.stepIndex == 0)
            #expect(data.tool == "launch_app")
        } else {
            Issue.record("Expected stepStarted event")
        }
    }

    // MARK: - 7.12 SSE history replay from disk

    @Test("restoreReplayBuffer restores events and subscribeWithReplay yields them")
    func restoreReplayBufferAndReplay() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)

        // Persist events to disk
        let runId = "20260517-replay01"
        try service.persistEvent(runId: runId, event: .stepStarted(StepStartedData(stepIndex: 0, tool: "click")))
        try service.persistEvent(runId: runId, event: .stepCompleted(StepCompletedData(
            stepIndex: 0, tool: "click", purpose: "Click button", success: true, durationMs: 200
        )))

        // Load events from disk and restore to broadcaster replay buffer
        let diskEvents = service.loadEvents(runId: runId)
        await broadcaster.restoreReplayBuffer(runId: runId, events: diskEvents)

        // Subscribe with replay should yield the restored events
        let stream = await broadcaster.subscribeWithReplay(runId: runId)
        var iterator = stream.makeAsyncIterator()

        let event1 = await iterator.next()
        let event2 = await iterator.next()

        #expect(event1 != nil)
        #expect(event2 != nil)

        if case let .stepStarted(data) = event1! {
            #expect(data.tool == "click")
        } else {
            Issue.record("First replayed event should be stepStarted")
        }
    }

    @Test("subscribeWithReplay falls back to disk when memory buffer is empty")
    func subscribeWithReplayFallsBackToDisk() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)

        // Write events directly to disk (no in-memory emit)
        let runId = "20260517-diskreplay01"
        try service.persistEvent(runId: runId, event: .stepStarted(StepStartedData(stepIndex: 0, tool: "type_text")))

        // subscribeWithReplay should load from disk since memory buffer is empty
        let stream = await broadcaster.subscribeWithReplay(runId: runId)
        var iterator = stream.makeAsyncIterator()

        let event = await iterator.next()
        #expect(event != nil)

        if case let .stepStarted(data) = event! {
            #expect(data.tool == "type_text")
        } else {
            Issue.record("Expected stepStarted from disk fallback")
        }
    }

    @Test("Recovery restores events to broadcaster replay buffer")
    func recoveryRestoresEventsToBroadcaster() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        // Persist a completed run with events
        let runId = "20260517-recovery01"
        let run = makeRun(runId: runId, status: .completed)
        try service.persistRecord(run)
        try service.persistEvent(runId: runId, event: .stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app")))
        try service.persistEvent(runId: runId, event: .runCompleted(RunCompletedData(
            runId: runId, finalStatus: "completed", totalSteps: 1, durationMs: 1000, replanCount: 0
        )))

        await RunRecoveryService.recover(from: tracker, persistenceService: service, eventBroadcaster: broadcaster)

        // Verify events are in replay buffer
        let replayBuffer = await broadcaster.getReplayBuffer(runId: runId)
        #expect(replayBuffer.count == 2)
    }

    // MARK: - RunTracker backward compatibility (no persistence service)

    @Test("RunTracker without persistenceService works as before")
    func runTrackerWithoutPersistenceServiceWorks() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "test", options: RunOptions(task: "test"))

        let run = await tracker.getRun(runId: runId)
        #expect(run != nil)
        #expect(run?.task == "test")
    }

    @Test("EventBroadcaster without persistenceService works as before")
    func eventBroadcasterWithoutPersistenceServiceWorks() async {
        let broadcaster = EventBroadcaster()
        let stream = await broadcaster.subscribe(runId: "test")

        await broadcaster.emit(runId: "test", event: .stepStarted(StepStartedData(stepIndex: 0, tool: "click")))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received != nil)
    }

    @Test("Recovery with empty directory does nothing")
    func recoveryWithEmptyDirectoryDoesNothing() async {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = RunPersistenceService(baseDirectory: tempDir)
        let broadcaster = EventBroadcaster(persistenceService: service)
        let tracker = RunTracker(eventBroadcaster: broadcaster, persistenceService: service)

        // Should not crash or add anything
        await RunRecoveryService.recover(from: tracker, persistenceService: service, eventBroadcaster: broadcaster)

        let runs = await tracker.listRuns()
        #expect(runs.isEmpty)
    }
}
