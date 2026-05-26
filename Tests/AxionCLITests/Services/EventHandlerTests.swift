import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

// MARK: - Test Handlers

actor MockEventHandler: EventHandler {
    let identifier: String
    let subscribedEventTypes: [any AgentEvent.Type]
    private(set) var handledEvents: [any AgentEvent] = []

    init(identifier: String, subscribedEventTypes: [any AgentEvent.Type] = []) {
        self.identifier = identifier
        self.subscribedEventTypes = subscribedEventTypes
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        handledEvents.append(event)
    }

    func getHandledCount() -> Int {
        handledEvents.count
    }
}

// MARK: - Tests

@Suite("EventHandler Protocol")
struct EventHandlerTests {

    @Test("handler subscribed to ToolCompletedEvent receives matching event")
    func subscribedHandlerReceivesEvent() async throws {
        let bus = EventBus()
        let runtime = AxionRuntime(eventBus: bus)
        let handler = MockEventHandler(
            identifier: "tool-handler",
            subscribedEventTypes: [ToolCompletedEvent.self]
        )
        await runtime.registerHandler(handler)

        let event = ToolCompletedEvent(
            sessionId: "s1",
            toolUseId: "tu1",
            toolName: "screenshot",
            durationMs: 100,
            isError: false,
            output: nil
        )
        await bus.publish(event)

        try await _Concurrency.Task.sleep(for: .milliseconds(100))

        let count = await handler.getHandledCount()
        #expect(count == 1, "Handler should receive exactly 1 event")
    }

    @Test("handler subscribed to ToolCompletedEvent ignores AgentStartedEvent")
    func subscribedHandlerIgnoresNonMatchingEvent() async throws {
        let bus = EventBus()
        let runtime = AxionRuntime(eventBus: bus)
        let handler = MockEventHandler(
            identifier: "tool-handler",
            subscribedEventTypes: [ToolCompletedEvent.self]
        )
        await runtime.registerHandler(handler)

        await bus.publish(AgentStartedEvent(sessionId: "s1", task: "test"))

        try await _Concurrency.Task.sleep(for: .milliseconds(100))

        let count = await handler.getHandledCount()
        #expect(count == 0, "Handler should NOT receive non-matching event")
    }

    @Test("handler with empty subscribedEventTypes receives all events")
    func wildcardHandlerReceivesAll() async throws {
        let bus = EventBus()
        let runtime = AxionRuntime(eventBus: bus)
        let handler = MockEventHandler(identifier: "wildcard", subscribedEventTypes: [])
        await runtime.registerHandler(handler)

        await bus.publish(AgentStartedEvent(sessionId: "s1", task: "test"))
        await bus.publish(ToolCompletedEvent(
            sessionId: "s1", toolUseId: "tu1", toolName: "screenshot",
            durationMs: 50, isError: false, output: nil
        ))

        try await _Concurrency.Task.sleep(for: .milliseconds(100))

        let count = await handler.getHandledCount()
        #expect(count == 2, "Wildcard handler should receive all events")
    }

    @Test("multiple handlers all receive matching events")
    func multipleHandlersAllReceive() async throws {
        let bus = EventBus()
        let runtime = AxionRuntime(eventBus: bus)

        let handler1 = MockEventHandler(identifier: "h1", subscribedEventTypes: [])
        let handler2 = MockEventHandler(identifier: "h2", subscribedEventTypes: [])
        let handler3 = MockEventHandler(
            identifier: "h3",
            subscribedEventTypes: [AgentStartedEvent.self]
        )

        await runtime.registerHandler(handler1)
        await runtime.registerHandler(handler2)
        await runtime.registerHandler(handler3)

        await bus.publish(AgentStartedEvent(sessionId: "s1", task: "test"))

        try await _Concurrency.Task.sleep(for: .milliseconds(100))

        let count1 = await handler1.getHandledCount()
        let count2 = await handler2.getHandledCount()
        let count3 = await handler3.getHandledCount()

        #expect(count1 == 1)
        #expect(count2 == 1)
        #expect(count3 == 1)
    }

    @Test("registerHandler stores handler and dispatch works")
    func registerAndDispatch() async throws {
        let bus = EventBus()
        let runtime = AxionRuntime(eventBus: bus)
        let handler = MockEventHandler(identifier: "test", subscribedEventTypes: [])
        await runtime.registerHandler(handler)

        await bus.publish(ToolCompletedEvent(
            sessionId: "s1", toolUseId: "tu1", toolName: "screenshot",
            durationMs: 100, isError: false, output: nil
        ))

        try await _Concurrency.Task.sleep(for: .milliseconds(100))

        let count = await handler.getHandledCount()
        #expect(count == 1)
    }
}
