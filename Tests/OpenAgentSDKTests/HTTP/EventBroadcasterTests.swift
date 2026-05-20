import XCTest
@testable import OpenAgentSDK

final class EventBroadcasterTests: XCTestCase {

    private var broadcaster: EventBroadcaster!

    override func setUp() {
        broadcaster = EventBroadcaster()
    }

    // MARK: - Subscribe & Emit

    func testSubscribeAndEmit() async {
        let stream = await broadcaster.subscribe(runId: "run-1")
        let event = AgentSSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "Bash"))

        await broadcaster.emit(runId: "run-1", event: event)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertEqual(received, event)
    }

    func testMultiClientFanOut() async {
        let stream1 = await broadcaster.subscribe(runId: "run-1")
        let stream2 = await broadcaster.subscribe(runId: "run-1")

        let event = AgentSSEEvent.stepCompleted(StepCompletedData(stepIndex: 0, tool: "Read", success: true))
        await broadcaster.emit(runId: "run-1", event: event)

        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()
        let received1 = await iter1.next()
        let received2 = await iter2.next()
        XCTAssertEqual(received1, event)
        XCTAssertEqual(received2, event)
    }

    // MARK: - Replay Buffer

    func testReplayBufferDeliversHistoricalEvents() async {
        let event1 = AgentSSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "Bash"))
        let event2 = AgentSSEEvent.stepStarted(StepStartedData(stepIndex: 1, tool: "Read"))

        await broadcaster.emit(runId: "run-1", event: event1)
        await broadcaster.emit(runId: "run-1", event: event2)

        // Late subscriber should get replay
        let stream = await broadcaster.subscribeWithReplay(runId: "run-1")
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        XCTAssertEqual(first, event1)
        XCTAssertEqual(second, event2)
    }

    func testGetReplayBufferReturnsBufferedEvents() async {
        let event = AgentSSEEvent.runCompleted(RunCompletedData(runId: "run-1", finalStatus: "completed", totalSteps: 5))
        await broadcaster.emit(runId: "run-1", event: event)

        let buffer = await broadcaster.getReplayBuffer(runId: "run-1")
        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.first, event)
    }

    func testGetReplayBufferReturnsEmptyForUnknownRun() async {
        let buffer = await broadcaster.getReplayBuffer(runId: "unknown")
        XCTAssertTrue(buffer.isEmpty)
    }

    // MARK: - Complete

    func testCompleteFinishesStreams() async {
        let stream = await broadcaster.subscribe(runId: "run-1")
        await broadcaster.complete(runId: "run-1")

        var iterator = stream.makeAsyncIterator()
        let result = await iterator.next()
        XCTAssertNil(result) // Stream should be finished
    }

    // MARK: - Restore

    func testRestoreReplayBuffer() async {
        let events = [
            AgentSSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "Bash")),
            AgentSSEEvent.stepCompleted(StepCompletedData(stepIndex: 0, tool: "Bash", success: true)),
        ]
        await broadcaster.restoreReplayBuffer(runId: "run-1", events: events)

        let stream = await broadcaster.subscribeWithReplay(runId: "run-1")
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        XCTAssertEqual(first, events[0])
        XCTAssertEqual(second, events[1])
    }

    // MARK: - Edge Cases

    func testEmitToRunWithNoSubscribersDoesNotCrash() async {
        let event = AgentSSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "Bash"))
        // Should not crash — event just goes to replay buffer
        await broadcaster.emit(runId: "no-subs", event: event)

        let buffer = await broadcaster.getReplayBuffer(runId: "no-subs")
        XCTAssertEqual(buffer.count, 1)
    }

    func testMultipleEventsDeliveredInOrder() async {
        let stream = await broadcaster.subscribe(runId: "run-order")
        let events: [AgentSSEEvent] = (0..<5).map { i in
            .stepStarted(StepStartedData(stepIndex: i, tool: "Tool\(i)"))
        }

        for event in events {
            await broadcaster.emit(runId: "run-order", event: event)
        }

        var iterator = stream.makeAsyncIterator()
        for expected in events {
            let received = await iterator.next()
            XCTAssertEqual(received, expected)
        }
    }

    func testSubscribeWithReplayThenLiveEvents() async {
        // Pre-emit events
        await broadcaster.emit(runId: "run-replay", event: .stepStarted(
            StepStartedData(stepIndex: 0, tool: "Bash")
        ))

        // Subscribe with replay — should get buffered event + live events
        let stream = await broadcaster.subscribeWithReplay(runId: "run-replay")

        // Emit live event
        await broadcaster.emit(runId: "run-replay", event: .stepCompleted(
            StepCompletedData(stepIndex: 0, tool: "Bash", success: true)
        ))

        var iterator = stream.makeAsyncIterator()
        let replayEvent = await iterator.next()
        let liveEvent = await iterator.next()

        XCTAssertNotNil(replayEvent)
        XCTAssertEqual(replayEvent?.eventType, "step_started")
        XCTAssertNotNil(liveEvent)
        XCTAssertEqual(liveEvent?.eventType, "step_completed")
    }

    func testRemoveCompletedStreams() async {
        await broadcaster.emit(runId: "run-cleanup", event: .stepStarted(
            StepStartedData(stepIndex: 0, tool: "Bash")
        ))
        await broadcaster.complete(runId: "run-cleanup")
        await broadcaster.removeCompletedStreams(runId: "run-cleanup")

        let buffer = await broadcaster.getReplayBuffer(runId: "run-cleanup")
        XCTAssertTrue(buffer.isEmpty)
    }
}
