import XCTest
@testable import OpenAgentSDK

/// Sendable box for tracking async callback invocations.
private final class Flag: @unchecked Sendable {
    var value: Bool = false
}

final class EventBusBridgeTests: XCTestCase {

    // MARK: - AC1: Event forwarding

    func testAgentStartedEvent_forwardsRunStarted() async {
        let eventBus = EventBus()
        let broadcaster = EventBroadcaster()
        let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")
        let stream = await broadcaster.subscribe(runId: "run-1")

        await bridge.start {}

        await eventBus.publish(AgentStartedEvent(sessionId: "run-1", task: "do something"))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertNotNil(received)

        if case .runStarted(let data) = received {
            XCTAssertEqual(data.runId, "run-1")
            XCTAssertEqual(data.task, "do something")
        } else {
            XCTFail("Expected .runStarted, got \(String(describing: received))")
        }

        await bridge.stop()
    }

    func testToolStartedEvent_forwardsStepStarted() async {
        let eventBus = EventBus()
        let broadcaster = EventBroadcaster()
        let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")
        let stream = await broadcaster.subscribe(runId: "run-1")

        await bridge.start {}

        await eventBus.publish(ToolStartedEvent(sessionId: "run-1", toolName: "Bash", toolUseId: "tu-1", input: nil))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertNotNil(received)

        if case .stepStarted(let data) = received {
            XCTAssertEqual(data.stepIndex, 0)
            XCTAssertEqual(data.tool, "Bash")
        } else {
            XCTFail("Expected .stepStarted, got \(String(describing: received))")
        }

        await bridge.stop()
    }

    func testToolCompletedEvent_forwardsStepCompleted() async {
        let eventBus = EventBus()
        let broadcaster = EventBroadcaster()
        let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")
        let stream = await broadcaster.subscribe(runId: "run-1")

        await bridge.start {}

        await eventBus.publish(ToolCompletedEvent(
            sessionId: "run-1", toolUseId: "tu-1", toolName: "Read",
            durationMs: 100, isError: false
        ))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertNotNil(received)

        if case .stepCompleted(let data) = received {
            XCTAssertEqual(data.stepIndex, 0)
            XCTAssertEqual(data.tool, "Read")
            XCTAssertTrue(data.success)
        } else {
            XCTFail("Expected .stepCompleted, got \(String(describing: received))")
        }

        await bridge.stop()
    }

    // MARK: - AC7: LLMCostEvent → costUpdate

    func testLLMCostEvent_forwardsCostUpdate() async {
        let eventBus = EventBus()
        let broadcaster = EventBroadcaster()
        let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")
        let stream = await broadcaster.subscribe(runId: "run-1")

        await bridge.start {}

        await eventBus.publish(LLMCostEvent(
            sessionId: "run-1", model: "claude-sonnet-4-6",
            inputTokens: 100, outputTokens: 50,
            cacheCreationInputTokens: nil, cacheReadInputTokens: nil,
            estimatedCostUsd: 0.005
        ))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertNotNil(received)

        if case .costUpdate(let data) = received {
            XCTAssertEqual(data.model, "claude-sonnet-4-6")
            XCTAssertEqual(data.inputTokens, 100)
            XCTAssertEqual(data.outputTokens, 50)
            XCTAssertEqual(data.estimatedCostUsd, 0.005)
        } else {
            XCTFail("Expected .costUpdate, got \(String(describing: received))")
        }

        await bridge.stop()
    }

    func testAgentCompletedEvent_forwardsRunCompleted() async {
        let eventBus = EventBus()
        let broadcaster = EventBroadcaster()
        let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")
        let stream = await broadcaster.subscribe(runId: "run-1")

        await bridge.start {}

        await eventBus.publish(AgentCompletedEvent(
            sessionId: "run-1", totalSteps: 3, durationMs: 5000, resultText: "done"
        ))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        XCTAssertNotNil(received)

        if case .runCompleted(let data) = received {
            XCTAssertEqual(data.runId, "run-1")
            XCTAssertEqual(data.totalSteps, 3)
        } else {
            XCTFail("Expected .runCompleted, got \(String(describing: received))")
        }

        await bridge.stop()
    }

    // MARK: - AC3: stepIndex increments

    func testStepIndexIncrementsAcrossMultipleToolCalls() async {
        let eventBus = EventBus()
        let broadcaster = EventBroadcaster()
        let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")
        let stream = await broadcaster.subscribe(runId: "run-1")

        await bridge.start {}

        // 3 tool calls: start → complete → start → complete → start → complete
        for i in 0..<3 {
            await eventBus.publish(ToolStartedEvent(
                sessionId: "run-1", toolName: "Tool\(i)", toolUseId: "tu-\(i)", input: nil
            ))
            await eventBus.publish(ToolCompletedEvent(
                sessionId: "run-1", toolUseId: "tu-\(i)", toolName: "Tool\(i)",
                durationMs: 100, isError: false
            ))
        }

        var iterator = stream.makeAsyncIterator()
        // Expected stepIndex pattern: 0,0,1,1,2,2
        let expectedIndices = [0, 0, 1, 1, 2, 2]
        for expected in expectedIndices {
            let event = await iterator.next()
            XCTAssertNotNil(event)
            switch event {
            case .stepStarted(let data):
                XCTAssertEqual(data.stepIndex, expected, "stepStarted at wrong index")
            case .stepCompleted(let data):
                XCTAssertEqual(data.stepIndex, expected, "stepCompleted at wrong index")
            default:
                XCTFail("Unexpected event type at index \(expected)")
            }
        }

        await bridge.stop()
    }

    // MARK: - AC4: Bridge stops on terminal events

    func testBridgeStopsAfterAgentCompletedEvent() async {
        let eventBus = EventBus()
        let broadcaster = EventBroadcaster()
        let flag = Flag()
        let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")

        await bridge.start {
            flag.value = true
        }

        await eventBus.publish(AgentCompletedEvent(
            sessionId: "run-1", totalSteps: 1, durationMs: 100, resultText: "ok"
        ))

        // Small sleep to let bridge process the terminal event
        try? await _Concurrency.Task.sleep(for: .milliseconds(200))

        let buffer = await broadcaster.getReplayBuffer(runId: "run-1")
        XCTAssertEqual(buffer.count, 1, "Should have exactly 1 event from the AgentCompletedEvent")

        XCTAssertTrue(flag.value, "onComplete should have been called")
        await bridge.stop()
    }

    // MARK: - Unmapped events ignored

    func testUnmappedEvent_doesNotForward() async {
        let eventBus = EventBus()
        let broadcaster = EventBroadcaster()
        let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")
        let stream = await broadcaster.subscribe(runId: "run-1")

        await bridge.start {}

        // SessionCreatedEvent is not mapped by AgentEventSSEMapping
        await eventBus.publish(SessionCreatedEvent(
            sessionId: "run-1", task: "test", model: "claude"
        ))

        // Publish a mapped event to verify bridge is working
        await eventBus.publish(ToolStartedEvent(
            sessionId: "run-1", toolName: "Bash", toolUseId: "tu-1", input: nil
        ))

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()

        // Should only get the ToolStartedEvent, not the SessionCreatedEvent
        if case .stepStarted = first {
            // correct
        } else {
            XCTFail("Expected first event to be stepStarted, got \(String(describing: first))")
        }

        await bridge.stop()
    }

    // MARK: - AC4: AgentFailedEvent and AgentInterruptedEvent trigger onComplete

    func testAgentFailedEvent_triggersOnComplete() async {
        let eventBus = EventBus()
        let broadcaster = EventBroadcaster()
        let flag = Flag()
        let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")

        await bridge.start {
            flag.value = true
        }

        await eventBus.publish(AgentFailedEvent(
            sessionId: "run-1", error: "something went wrong", stepsCompleted: 2
        ))

        try? await _Concurrency.Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(flag.value, "onComplete should be called on AgentFailedEvent")
        await bridge.stop()
    }

    func testAgentInterruptedEvent_triggersOnComplete() async {
        let eventBus = EventBus()
        let broadcaster = EventBroadcaster()
        let flag = Flag()
        let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")

        await bridge.start {
            flag.value = true
        }

        await eventBus.publish(AgentInterruptedEvent(
            sessionId: "run-1", stepsCompleted: 1
        ))

        try? await _Concurrency.Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(flag.value, "onComplete should be called on AgentInterruptedEvent")
        await bridge.stop()
    }
}
