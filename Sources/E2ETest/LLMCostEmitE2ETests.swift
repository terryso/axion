import Foundation
import OpenAgentSDK
import _Concurrency

// MARK: - Tests 150-152: LLM Cost Event Emit E2E Tests (Story 27.4)

/// E2E tests for LLM cost event emission through EventBus.
/// Uses real LLM calls + EventBus to verify LLMCostEvent values.
struct LLMCostEmitE2ETests {
    static func run(apiKey: String, model: String, baseURL: String?) async {
        section("150-152. LLM Cost Event Emit (E2E — Story 27.4)")
        await testPromptEmitsLLMCostEvent(apiKey: apiKey, model: model, baseURL: baseURL)
        await testStreamEmitsLLMCostEvent(apiKey: apiKey, model: model, baseURL: baseURL)
        await testPromptLLMCostEventContainsSessionId(apiKey: apiKey, model: model, baseURL: baseURL)
    }

    // MARK: Test 150: prompt() emits LLMCostEvent with inputTokens > 0, outputTokens > 0, estimatedCostUsd > 0

    static func testPromptEmitsLLMCostEvent(apiKey: String, model: String, baseURL: String?) async {
        let bus = EventBus()
        let (_, allStream) = await bus.subscribe()

        var opts = AgentOptions(
            apiKey: apiKey,
            model: model,
            systemPrompt: "Reply with exactly: hello"
        )
        if let baseURL { opts.baseURL = baseURL }
        opts.eventBus = bus

        let agent = Agent(options: opts)
        _ = await agent.prompt("say hello")

        let collected = await collectEvents(from: allStream, maxEvents: 10, timeoutSeconds: 5)

        let costEvents = collected.compactMap { $0 as? LLMCostEvent }
        guard !costEvents.isEmpty else {
            fail("150. Prompt emits LLMCostEvent", "no LLMCostEvent emitted, got \(collected.count) events")
            return
        }

        let totalInput = costEvents.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = costEvents.reduce(0) { $0 + $1.outputTokens }
        let totalCost = costEvents.reduce(0.0) { $0 + $1.estimatedCostUsd }

        guard totalInput > 0 else {
            fail("150. Prompt emits LLMCostEvent", "totalInputTokens should be > 0, got \(totalInput)")
            return
        }
        guard totalOutput > 0 else {
            fail("150. Prompt emits LLMCostEvent", "totalOutputTokens should be > 0, got \(totalOutput)")
            return
        }
        guard totalCost > 0 else {
            fail("150. Prompt emits LLMCostEvent", "totalCostUsd should be > 0, got \(totalCost)")
            return
        }

        pass("150. Prompt emits LLMCostEvent with inputTokens > 0, outputTokens > 0, estimatedCostUsd > 0")
    }

    // MARK: Test 151: stream() emits LLMCostEvent

    static func testStreamEmitsLLMCostEvent(apiKey: String, model: String, baseURL: String?) async {
        let bus = EventBus()
        let (_, allStream) = await bus.subscribe()

        var opts = AgentOptions(
            apiKey: apiKey,
            model: model,
            systemPrompt: "Reply with exactly: hello"
        )
        if let baseURL { opts.baseURL = baseURL }
        opts.eventBus = bus

        let agent = Agent(options: opts)
        let messageStream = agent.stream("say hello")
        for await _ in messageStream {}

        let collected = await collectEvents(from: allStream, maxEvents: 10, timeoutSeconds: 5)

        let costEvents = collected.compactMap { $0 as? LLMCostEvent }
        guard !costEvents.isEmpty else {
            fail("151. Stream emits LLMCostEvent", "no LLMCostEvent emitted, got \(collected.count) events")
            return
        }

        let totalInput = costEvents.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = costEvents.reduce(0) { $0 + $1.outputTokens }
        let totalCost = costEvents.reduce(0.0) { $0 + $1.estimatedCostUsd }

        guard totalInput > 0 else {
            fail("151. Stream emits LLMCostEvent", "totalInputTokens should be > 0, got \(totalInput)")
            return
        }
        guard totalOutput > 0 else {
            fail("151. Stream emits LLMCostEvent", "totalOutputTokens should be > 0, got \(totalOutput)")
            return
        }
        guard totalCost > 0 else {
            fail("151. Stream emits LLMCostEvent", "totalCostUsd should be > 0, got \(totalCost)")
            return
        }

        pass("151. Stream emits LLMCostEvent with inputTokens > 0, outputTokens > 0, estimatedCostUsd > 0")
    }

    // MARK: Test 152: prompt() LLMCostEvent contains sessionId

    static func testPromptLLMCostEventContainsSessionId(apiKey: String, model: String, baseURL: String?) async {
        let bus = EventBus()
        let (_, allStream) = await bus.subscribe()

        let explicitSessionId = "e2e-cost-session-\(UUID().uuidString.prefix(8))"

        var opts = AgentOptions(
            apiKey: apiKey,
            model: model,
            systemPrompt: "Reply with exactly: hello"
        )
        if let baseURL { opts.baseURL = baseURL }
        opts.eventBus = bus
        opts.sessionId = explicitSessionId

        let agent = Agent(options: opts)
        _ = await agent.prompt("say hello")

        let collected = await collectEvents(from: allStream, maxEvents: 10, timeoutSeconds: 5)

        let costEvents = collected.compactMap { $0 as? LLMCostEvent }
        guard !costEvents.isEmpty else {
            fail("152. LLMCostEvent contains sessionId", "no LLMCostEvent emitted")
            return
        }

        let costEvent = costEvents[0]
        guard costEvent.sessionId == explicitSessionId else {
            fail("152. LLMCostEvent contains sessionId", "sessionId mismatch: expected '\(explicitSessionId)', got '\(costEvent.sessionId ?? "nil")'")
            return
        }

        pass("152. Prompt LLMCostEvent contains correct sessionId")
    }

    // MARK: - Helper

    private static func collectEvents(
        from stream: AsyncStream<any AgentEvent>,
        maxEvents: Int,
        timeoutSeconds: UInt64
    ) async -> [any AgentEvent] {
        let deadline = UInt64(Date().timeIntervalSince1970 * 1_000_000_000) + timeoutSeconds * 1_000_000_000
        var collected: [any AgentEvent] = []
        for await event in stream {
            collected.append(event)
            if collected.count >= maxEvents { break }
            let now = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
            if now >= deadline { break }
        }
        return collected
    }
}
