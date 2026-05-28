// EventBusExample
//
// Demonstrates the Runtime Event Layer (Epic 26):
//   1. EventBus basics: publish / subscribe / unsubscribe
//   2. Type-filtered subscription — receive only specific event types
//   3. Multiple concurrent subscribers (CLI logger + cost monitor + tool tracer)
//   4. Buffering behavior — slow consumers don't block publishers
//
// Run: swift run EventBusExample
// No API key needed — this example publishes synthetic events.

import Foundation
import OpenAgentSDK

@main
struct EventBusExample {
    static func main() async throws {
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║  EventBus Example — Runtime Event Layer                     ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print()

        try await part1_BasicPublishSubscribe()
        try await part2_TypeFilteredSubscription()
        try await part3_MultipleSubscribers()
        try await part4_BufferingBehavior()
    }

    // MARK: - Part 1: Basic Publish / Subscribe

    static func part1_BasicPublishSubscribe() async throws {
        print("--- Part 1: Basic Publish / Subscribe ---")
        print()

        let bus = EventBus()

        // Subscribe to all events
        let (subId, stream) = await bus.subscribe()
        print("  Subscriber registered: \(subId)")
        print()

        // Publish a session lifecycle event
        let sessionEvent = SessionCreatedEvent(
            sessionId: "sess-001",
            task: "Analyze sales data",
            model: "claude-sonnet-4-6"
        )
        await bus.publish(sessionEvent)

        // Publish an agent lifecycle event
        let agentEvent = AgentStartedEvent(
            sessionId: "sess-001",
            task: "Analyze sales data"
        )
        await bus.publish(agentEvent)

        // Consume events
        var count = 0
        for await event in stream {
            count += 1
            describeEvent(event, prefix: "  Received")
            if count == 2 { break }
        }

        // Unsubscribe
        await bus.unsubscribe(subId)
        print()
        print("  Unsubscribed \(subId)")
        print()
    }

    // MARK: - Part 2: Type-Filtered Subscription

    static func part2_TypeFilteredSubscription() async throws {
        print("--- Part 2: Type-Filtered Subscription ---")
        print()

        let bus = EventBus()

        // Subscribe only to tool events
        let toolStream = await bus.subscribe(ToolStartedEvent.self)

        // Publish a mix of event types
        await bus.publish(AgentStartedEvent(sessionId: "sess-002", task: "Build dashboard"))
        await bus.publish(ToolStartedEvent(sessionId: "sess-002", toolName: "Read", toolUseId: "tu_01", input: "/data/sales.csv"))
        await bus.publish(AgentCompletedEvent(sessionId: "sess-002", totalSteps: 3, durationMs: 1200, resultText: "Done"))
        await bus.publish(ToolStartedEvent(sessionId: "sess-002", toolName: "Write", toolUseId: "tu_02", input: nil))

        // Only ToolStartedEvents should arrive
        print("  Listening for ToolStartedEvent only...")
        var toolCount = 0
        for await event in toolStream {
            toolCount += 1
            print("  [Tool] \(event.toolName) (id=\(event.toolUseId))")
            if toolCount == 2 { break }
        }
        print("  Received \(toolCount) tool events (filtered out 2 non-tool events)")
        print()
    }

    // MARK: - Part 3: Multiple Concurrent Subscribers

    static func part3_MultipleSubscribers() async throws {
        print("--- Part 3: Multiple Concurrent Subscribers ---")
        print()

        let bus = EventBus()

        // Subscriber 1: CLI Logger (all events)
        let (_, loggerStream) = await bus.subscribe()

        // Subscriber 2: Cost Monitor (LLM events only)
        let costStream = await bus.subscribe(LLMCostEvent.self)

        // Subscriber 3: Tool Tracer (tool completed events only)
        let toolCompletedStream = await bus.subscribe(ToolCompletedEvent.self)

        // Simulate an agent run with multiple events
        print("  Publishing simulated agent run events...")
        print()

        await bus.publish(SessionCreatedEvent(sessionId: "sess-003", task: "Research task", model: "claude-sonnet-4-6"))
        await bus.publish(AgentStartedEvent(sessionId: "sess-003", task: "Research task"))
        await bus.publish(LLMRequestStartedEvent(sessionId: "sess-003", model: "claude-sonnet-4-6"))
        await bus.publish(ToolStartedEvent(sessionId: "sess-003", toolName: "WebSearch", toolUseId: "tu_10", input: "Swift concurrency"))
        await bus.publish(ToolCompletedEvent(sessionId: "sess-003", toolUseId: "tu_10", toolName: "WebSearch", durationMs: 850, isError: false))
        await bus.publish(LLMCostEvent(
            sessionId: "sess-003",
            model: "claude-sonnet-4-6",
            inputTokens: 2500,
            outputTokens: 800,
            cacheCreationInputTokens: 1200,
            cacheReadInputTokens: nil,
            estimatedCostUsd: 0.0123
        ))
        await bus.publish(AgentCompletedEvent(sessionId: "sess-003", totalSteps: 2, durationMs: 3200, resultText: "Research complete"))

        // Collect results from each subscriber concurrently
        async let loggerEvents = collectEvents(from: loggerStream, max: 7, label: "Logger")
        async let costEvents = collectEvents(from: costStream, max: 1, label: "CostMonitor")
        async let toolEvents = collectEvents(from: toolCompletedStream, max: 1, label: "ToolTracer")

        let (loggerResult, costResult, toolResult) = await (loggerEvents, costEvents, toolEvents)

        print("  Logger received:      \(loggerResult) events (all types)")
        print("  CostMonitor received: \(costResult) events (LLMCostEvent only)")
        print("  ToolTracer received:  \(toolResult) events (ToolCompletedEvent only)")
        print()
    }

    // MARK: - Part 4: Buffering Behavior

    static func part4_BufferingBehavior() async throws {
        print("--- Part 4: Buffering Behavior ---")
        print()

        let bus = EventBus()

        // Subscribe but don't consume immediately (slow subscriber)
        let (_, slowStream) = await bus.subscribe()

        // Publish 150 events rapidly
        print("  Publishing 150 events to a slow subscriber...")
        for i in 1...150 {
            await bus.publish(ToolStartedEvent(
                sessionId: "sess-004",
                toolName: "Tool-\(i)",
                toolUseId: "tu_\(i)",
                input: nil
            ))
        }

        // Slow subscriber should only have the latest 100 (buffer policy)
        print("  Slow subscriber is now reading events...")
        var received = 0
        var firstIndex = 0
        var lastIndex = 0
        for await event in slowStream {
            received += 1
            if let toolEvent = event as? ToolStartedEvent {
                let idx = Int(toolEvent.toolUseId.replacingOccurrences(of: "tu_", with: "")) ?? 0
                if received == 1 { firstIndex = idx }
                lastIndex = idx
            }
            if received == 100 { break }
        }

        print("  Received: \(received) events")
        print("  First event: Tool-\(firstIndex) (oldest buffered)")
        print("  Last event:  Tool-\(lastIndex) (newest)")
        print("  Buffer policy: .bufferingNewest(100) — oldest 50 were dropped")
        print()
    }

    // MARK: - Helpers

    static func collectEvents(from stream: AsyncStream<any AgentEvent>, max: Int, label: String) async -> Int {
        var count = 0
        for await _ in stream {
            count += 1
            if count == max { break }
        }
        return count
    }

    static func collectEvents<T: AgentEvent>(from stream: AsyncStream<T>, max: Int, label: String) async -> Int {
        var count = 0
        for await _ in stream {
            count += 1
            if count == max { break }
        }
        return count
    }

    static func describeEvent(_ event: any AgentEvent, prefix: String) {
        switch event {
        case let e as SessionCreatedEvent:
            print("\(prefix) SessionCreated: task=\"\(e.task)\", model=\(e.model)")
        case let e as AgentStartedEvent:
            print("\(prefix) AgentStarted: task=\"\(e.task)\"")
        case let e as AgentCompletedEvent:
            print("\(prefix) AgentCompleted: steps=\(e.totalSteps), duration=\(e.durationMs)ms")
        case let e as ToolStartedEvent:
            print("\(prefix) ToolStarted: \(e.toolName) (id=\(e.toolUseId))")
        case let e as ToolCompletedEvent:
            print("\(prefix) ToolCompleted: \(e.toolName), duration=\(e.durationMs)ms, error=\(e.isError)")
        case let e as LLMCostEvent:
            print("\(prefix) LLMCost: in=\(e.inputTokens), out=\(e.outputTokens), cost=$\(String(format: "%.4f", e.estimatedCostUsd))")
        case let e as LLMRequestStartedEvent:
            print("\(prefix) LLMRequestStarted: model=\(e.model)")
        default:
            print("\(prefix) \(type(of: event).self): id=\(event.id)")
        }
    }
}
