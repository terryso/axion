import XCTest
@testable import AxionCLI

// [P0] ATDD RED-PHASE — Story 5.2 AC1, AC4, AC5
// EventBroadcaster actor tests. These tests assert EXPECTED behavior.
// They will fail until EventBroadcaster is implemented.

final class EventBroadcasterTests: XCTestCase {

    // MARK: - AC1: subscribe returns valid AsyncStream

    func test_subscribe_returnsAsyncStream() async {
        let broadcaster = EventBroadcaster()
        let stream = await broadcaster.subscribe(runId: "test-run-1")

        // AsyncStream should be created without error.
        // Emit an event to verify the stream works, then complete to verify nil on finish.
        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        await broadcaster.emit(runId: "test-run-1", event: event)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertNotNil(received, "Subscribed stream should receive emitted events")
    }

    // MARK: - AC1: emit pushes events to subscribers

    func test_emit_pushesEventToSubscriber() async throws {
        let broadcaster = EventBroadcaster()
        let stream = await broadcaster.subscribe(runId: "test-run-1")

        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        await broadcaster.emit(runId: "test-run-1", event: event)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()

        XCTAssertNotNil(received, "Subscriber should receive the emitted event")

        if case let .stepStarted(data) = received! {
            XCTAssertEqual(data.stepIndex, 0)
            XCTAssertEqual(data.tool, "launch_app")
        } else {
            XCTFail("Expected .stepStarted event, got different event type")
        }
    }

    // MARK: - AC1: emit pushes multiple events in order

    func test_emit_multipleEvents_preservesOrder() async throws {
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

        XCTAssertNotNil(received1)
        XCTAssertNotNil(received2)
        XCTAssertNotNil(received3)

        if case .stepStarted = received1! {} else { XCTFail("First event should be stepStarted") }
        if case .stepCompleted = received2! {} else { XCTFail("Second event should be stepCompleted") }
        if case .runCompleted = received3! {} else { XCTFail("Third event should be runCompleted") }
    }

    // MARK: - AC5: multiple subscribers receive same events

    func test_emit_multipleSubscribers_allReceiveSameEvent() async throws {
        let broadcaster = EventBroadcaster()

        let stream1 = await broadcaster.subscribe(runId: "test-run-3")
        let stream2 = await broadcaster.subscribe(runId: "test-run-3")

        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        await broadcaster.emit(runId: "test-run-3", event: event)

        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()

        let received1 = await iter1.next()
        let received2 = await iter2.next()

        XCTAssertNotNil(received1, "Subscriber 1 should receive the event")
        XCTAssertNotNil(received2, "Subscriber 2 should receive the event")
        XCTAssertEqual(received1, received2, "Both subscribers should receive the same event")
    }

    // MARK: - AC5: events for different runIds are isolated

    func test_emit_differentRunIds_areIsolated() async throws {
        let broadcaster = EventBroadcaster()

        let stream1 = await broadcaster.subscribe(runId: "run-A")
        let stream2 = await broadcaster.subscribe(runId: "run-B")

        let eventForA = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "click"))
        await broadcaster.emit(runId: "run-A", event: eventForA)

        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()

        let received1 = await iter1.next()
        XCTAssertNotNil(received1, "Subscriber for run-A should receive its event")

        // Emit an event for run-B to verify stream2 works independently
        let eventForB = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        await broadcaster.emit(runId: "run-B", event: eventForB)
        let received2 = await iter2.next()
        XCTAssertNotNil(received2, "Subscriber for run-B should receive run-B events")

        // Verify they received different events
        if case let .stepStarted(data1) = received1!,
           case let .stepStarted(data2) = received2! {
            XCTAssertEqual(data1.tool, "click")
            XCTAssertEqual(data2.tool, "launch_app")
        }
    }

    // MARK: - complete closes subscriber streams

    func test_complete_closesSubscriberStreams() async throws {
        let broadcaster = EventBroadcaster()
        let stream = await broadcaster.subscribe(runId: "test-run-4")

        await broadcaster.complete(runId: "test-run-4")

        var iterator = stream.makeAsyncIterator()
        let next = await iterator.next()
        XCTAssertNil(next, "After complete(), stream should return nil (finished)")
    }

    func test_complete_allSubscribersForRunIdAreClosed() async throws {
        let broadcaster = EventBroadcaster()

        let stream1 = await broadcaster.subscribe(runId: "test-run-5")
        let stream2 = await broadcaster.subscribe(runId: "test-run-5")

        await broadcaster.complete(runId: "test-run-5")

        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()

        let next1 = await iter1.next()
        let next2 = await iter2.next()

        XCTAssertNil(next1, "Subscriber 1 stream should be closed after complete()")
        XCTAssertNil(next2, "Subscriber 2 stream should be closed after complete()")
    }

    // MARK: - AC4: replayBuffer caches events for completed runs

    func test_replayBuffer_storesEventsForRunId() async throws {
        let broadcaster = EventBroadcaster()

        let event1 = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        let event2 = SSEEvent.stepCompleted(StepCompletedData(
            stepIndex: 0, tool: "launch_app", purpose: "Launch", success: true, durationMs: 100
        ))

        await broadcaster.emit(runId: "replay-test", event: event1)
        await broadcaster.emit(runId: "replay-test", event: event2)

        let replay = await broadcaster.getReplayBuffer(runId: "replay-test")

        XCTAssertEqual(replay.count, 2, "Replay buffer should contain 2 events")
    }

    // MARK: - AC4: late subscriber receives replayed events

    func test_lateSubscriber_receivesReplayedEvents() async throws {
        let broadcaster = EventBroadcaster()

        // Emit events before subscribing
        let event1 = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        let event2 = SSEEvent.stepCompleted(StepCompletedData(
            stepIndex: 0, tool: "launch_app", purpose: "Launch", success: true, durationMs: 100
        ))
        await broadcaster.emit(runId: "late-test", event: event1)
        await broadcaster.emit(runId: "late-test", event: event2)

        // Now subscribe — should be able to get replayed events
        let replay = await broadcaster.getReplayBuffer(runId: "late-test")
        XCTAssertEqual(replay.count, 2, "Late subscriber should see replayed events")

        // Subscribe and verify replay delivery
        let stream = await broadcaster.subscribeWithReplay(runId: "late-test")
        var iterator = stream.makeAsyncIterator()

        let received1 = await iterator.next()
        let received2 = await iterator.next()

        XCTAssertNotNil(received1, "Late subscriber should receive first replayed event")
        XCTAssertNotNil(received2, "Late subscriber should receive second replayed event")
    }

    // MARK: - removeCompletedStreams cleans up resources

    func test_removeCompletedStreams_clearsReplayBuffer() async throws {
        let broadcaster = EventBroadcaster()

        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "click"))
        await broadcaster.emit(runId: "cleanup-test", event: event)

        await broadcaster.removeCompletedStreams(runId: "cleanup-test")

        let replay = await broadcaster.getReplayBuffer(runId: "cleanup-test")
        XCTAssertTrue(replay.isEmpty, "Replay buffer should be cleared after removeCompletedStreams()")
    }
}
