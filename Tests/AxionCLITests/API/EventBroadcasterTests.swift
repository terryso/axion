import Testing
@testable import AxionCLI

@Suite("EventBroadcaster")
struct EventBroadcasterTests {

    @Test("Subscribe returns async stream")
    func subscribeReturnsAsyncStream() async {
        let broadcaster = EventBroadcaster()
        let stream = await broadcaster.subscribe(runId: "test-run-1")

        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        await broadcaster.emit(runId: "test-run-1", event: event)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received != nil)
    }

    @Test("Emit pushes event to subscriber")
    func emitPushesEventToSubscriber() async throws {
        let broadcaster = EventBroadcaster()
        let stream = await broadcaster.subscribe(runId: "test-run-1")

        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        await broadcaster.emit(runId: "test-run-1", event: event)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()

        #expect(received != nil)

        if case let .stepStarted(data) = received! {
            #expect(data.stepIndex == 0)
            #expect(data.tool == "launch_app")
        } else {
            Issue.record("Expected .stepStarted event, got different event type")
        }
    }

    @Test("Emit multiple events preserves order")
    func emitMultipleEventsPreservesOrder() async throws {
        let broadcaster = EventBroadcaster()
        let stream = await broadcaster.subscribe(runId: "test-run-2")

        let event1 = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        let event2 = SSEEvent.stepCompleted(StepCompletedData(
            stepIndex: 0, tool: "launch_app", purpose: "Launch", success: true, durationMs: 100
        ))
        let event3 = SSEEvent.runCompleted(RunCompletedData(
            runId: "test-run-2", finalStatus: "done", totalSteps: 1, durationMs: 100, replanCount: 0
        ))

        await broadcaster.emit(runId: "test-run-2", event: event1)
        await broadcaster.emit(runId: "test-run-2", event: event2)
        await broadcaster.emit(runId: "test-run-2", event: event3)

        var iterator = stream.makeAsyncIterator()
        let received1 = await iterator.next()
        let received2 = await iterator.next()
        let received3 = await iterator.next()

        #expect(received1 != nil)
        #expect(received2 != nil)
        #expect(received3 != nil)

        if case .stepStarted = received1! {} else { Issue.record("First event should be stepStarted") }
        if case .stepCompleted = received2! {} else { Issue.record("Second event should be stepCompleted") }
        if case .runCompleted = received3! {} else { Issue.record("Third event should be runCompleted") }
    }

    @Test("Multiple subscribers receive same event")
    func emitMultipleSubscribersAllReceiveSameEvent() async throws {
        let broadcaster = EventBroadcaster()

        let stream1 = await broadcaster.subscribe(runId: "test-run-3")
        let stream2 = await broadcaster.subscribe(runId: "test-run-3")

        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        await broadcaster.emit(runId: "test-run-3", event: event)

        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()

        let received1 = await iter1.next()
        let received2 = await iter2.next()

        #expect(received1 != nil)
        #expect(received2 != nil)
        #expect(received1 == received2)
    }

    @Test("Events for different runIds are isolated")
    func emitDifferentRunIdsAreIsolated() async throws {
        let broadcaster = EventBroadcaster()

        let stream1 = await broadcaster.subscribe(runId: "run-A")
        let stream2 = await broadcaster.subscribe(runId: "run-B")

        let eventForA = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "click"))
        await broadcaster.emit(runId: "run-A", event: eventForA)

        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()

        let received1 = await iter1.next()
        #expect(received1 != nil)

        let eventForB = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        await broadcaster.emit(runId: "run-B", event: eventForB)
        let received2 = await iter2.next()
        #expect(received2 != nil)

        if case let .stepStarted(data1) = received1!,
           case let .stepStarted(data2) = received2! {
            #expect(data1.tool == "click")
            #expect(data2.tool == "launch_app")
        }
    }

    @Test("Complete closes subscriber streams")
    func completeClosesSubscriberStreams() async throws {
        let broadcaster = EventBroadcaster()
        let stream = await broadcaster.subscribe(runId: "test-run-4")

        await broadcaster.complete(runId: "test-run-4")

        var iterator = stream.makeAsyncIterator()
        let next = await iterator.next()
        #expect(next == nil)
    }

    @Test("Complete closes all subscribers for runId")
    func completeAllSubscribersForRunIdAreClosed() async throws {
        let broadcaster = EventBroadcaster()

        let stream1 = await broadcaster.subscribe(runId: "test-run-5")
        let stream2 = await broadcaster.subscribe(runId: "test-run-5")

        await broadcaster.complete(runId: "test-run-5")

        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()

        let next1 = await iter1.next()
        let next2 = await iter2.next()

        #expect(next1 == nil)
        #expect(next2 == nil)
    }

    @Test("Replay buffer stores events for runId")
    func replayBufferStoresEventsForRunId() async throws {
        let broadcaster = EventBroadcaster()

        let event1 = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        let event2 = SSEEvent.stepCompleted(StepCompletedData(
            stepIndex: 0, tool: "launch_app", purpose: "Launch", success: true, durationMs: 100
        ))

        await broadcaster.emit(runId: "replay-test", event: event1)
        await broadcaster.emit(runId: "replay-test", event: event2)

        let replay = await broadcaster.getReplayBuffer(runId: "replay-test")

        #expect(replay.count == 2)
    }

    @Test("Late subscriber receives replayed events")
    func lateSubscriberReceivesReplayedEvents() async throws {
        let broadcaster = EventBroadcaster()

        let event1 = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        let event2 = SSEEvent.stepCompleted(StepCompletedData(
            stepIndex: 0, tool: "launch_app", purpose: "Launch", success: true, durationMs: 100
        ))
        await broadcaster.emit(runId: "late-test", event: event1)
        await broadcaster.emit(runId: "late-test", event: event2)

        let replay = await broadcaster.getReplayBuffer(runId: "late-test")
        #expect(replay.count == 2)

        let stream = await broadcaster.subscribeWithReplay(runId: "late-test")
        var iterator = stream.makeAsyncIterator()

        let received1 = await iterator.next()
        let received2 = await iterator.next()

        #expect(received1 != nil)
        #expect(received2 != nil)
    }

    @Test("removeCompletedStreams clears replay buffer")
    func removeCompletedStreamsClearsReplayBuffer() async throws {
        let broadcaster = EventBroadcaster()

        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "click"))
        await broadcaster.emit(runId: "cleanup-test", event: event)

        await broadcaster.removeCompletedStreams(runId: "cleanup-test")

        let replay = await broadcaster.getReplayBuffer(runId: "cleanup-test")
        #expect(replay.isEmpty)
    }
}
