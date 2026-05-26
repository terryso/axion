import Foundation
import OpenAgentSDK
import _Concurrency

// MARK: - Tests 153-155: Session Lifecycle Event Emit E2E Tests (Story 27.5)

/// E2E tests for session lifecycle event emission through EventBus.
/// Uses real LLM calls + EventBus to verify SessionCreatedEvent and SessionClosedEvent.
struct SessionLifecycleEmitE2ETests {
    static func run(apiKey: String, model: String, baseURL: String?) async {
        section("153-157. Session Lifecycle Event Emit (E2E — Story 27.5)")
        await testStreamEmitsSessionCreatedEvent(apiKey: apiKey, model: model, baseURL: baseURL)
        await testPromptEmitsSessionCreatedEvent(apiKey: apiKey, model: model, baseURL: baseURL)
        await testStreamEmitsSessionAutoSavedEvent(apiKey: apiKey, model: model, baseURL: baseURL)
        await testPromptEmitsSessionAutoSavedEvent(apiKey: apiKey, model: model, baseURL: baseURL)
        await testCloseEmitsSessionClosedEvent(apiKey: apiKey, model: model, baseURL: baseURL)
    }

    // MARK: Test 153: stream() + SessionStore → SessionCreatedEvent via real LLM

    static func testStreamEmitsSessionCreatedEvent(apiKey: String, model: String, baseURL: String?) async {
        let bus = EventBus()
        let (_, eventStream) = await bus.subscribe()

        let tempDir = NSTemporaryDirectory() + "e2e-sess-created-\(UUID().uuidString.prefix(8))"
        let store = SessionStore(sessionsDir: tempDir)
        let sessionId = "e2e-sess-\(UUID().uuidString.prefix(8))"

        var opts = AgentOptions(
            apiKey: apiKey,
            model: model,
            systemPrompt: "Reply with exactly: hello"
        )
        if let baseURL { opts.baseURL = baseURL }
        opts.sessionStore = store
        opts.sessionId = sessionId
        opts.eventBus = bus

        let agent = Agent(options: opts)
        let messageStream = agent.stream("say hello session")

        for await _ in messageStream {}

        var collected: [any AgentEvent] = []
        for await event in eventStream {
            collected.append(event)
            if collected.count >= 4 { break }
        }

        let sessionCreated = collected.first { $0 is SessionCreatedEvent } as? SessionCreatedEvent
        guard sessionCreated != nil else {
            fail("153. Stream emits SessionCreatedEvent", "no SessionCreatedEvent found in \(collected.count) events")
            return
        }
        guard sessionCreated?.sessionId == sessionId else {
            fail("153. Stream emits SessionCreatedEvent", "sessionId mismatch: expected \(sessionId), got \(sessionCreated?.sessionId ?? "nil")")
            return
        }
        guard sessionCreated?.task == "say hello session" else {
            fail("153. Stream emits SessionCreatedEvent", "task mismatch: \(sessionCreated?.task ?? "nil")")
            return
        }

        pass("153. Stream emits SessionCreatedEvent with sessionId and task via real LLM")
    }

    // MARK: Test 154: prompt() + SessionStore → SessionCreatedEvent via real LLM

    static func testPromptEmitsSessionCreatedEvent(apiKey: String, model: String, baseURL: String?) async {
        let bus = EventBus()
        let (_, eventStream) = await bus.subscribe()

        let tempDir = NSTemporaryDirectory() + "e2e-sess-prompt-\(UUID().uuidString.prefix(8))"
        let store = SessionStore(sessionsDir: tempDir)
        let sessionId = "e2e-sess-prompt-\(UUID().uuidString.prefix(8))"

        var opts = AgentOptions(
            apiKey: apiKey,
            model: model,
            systemPrompt: "Reply with exactly: hello"
        )
        if let baseURL { opts.baseURL = baseURL }
        opts.sessionStore = store
        opts.sessionId = sessionId
        opts.eventBus = bus

        let agent = Agent(options: opts)
        _ = await agent.prompt("say hello session")

        var collected: [any AgentEvent] = []
        for await event in eventStream {
            collected.append(event)
            if collected.count >= 4 { break }
        }

        let sessionCreated = collected.first { $0 is SessionCreatedEvent } as? SessionCreatedEvent
        guard sessionCreated != nil else {
            fail("154. Prompt emits SessionCreatedEvent", "no SessionCreatedEvent found in \(collected.count) events")
            return
        }
        guard sessionCreated?.sessionId == sessionId else {
            fail("154. Prompt emits SessionCreatedEvent", "sessionId mismatch: expected \(sessionId), got \(sessionCreated?.sessionId ?? "nil")")
            return
        }
        guard sessionCreated?.task == "say hello session" else {
            fail("154. Prompt emits SessionCreatedEvent", "task mismatch: \(sessionCreated?.task ?? "nil")")
            return
        }

        pass("154. Prompt emits SessionCreatedEvent with sessionId and task via real LLM")
    }

    // MARK: Test 156: stream() + SessionStore + persistSession → SessionAutoSavedEvent

    static func testStreamEmitsSessionAutoSavedEvent(apiKey: String, model: String, baseURL: String?) async {
        let bus = EventBus()
        let (_, eventStream) = await bus.subscribe()

        let tempDir = NSTemporaryDirectory() + "e2e-sess-autosave-stream-\(UUID().uuidString.prefix(8))"
        let store = SessionStore(sessionsDir: tempDir)
        let sessionId = "e2e-autosave-stream-\(UUID().uuidString.prefix(8))"

        var opts = AgentOptions(
            apiKey: apiKey,
            model: model,
            systemPrompt: "Reply with exactly: hello"
        )
        if let baseURL { opts.baseURL = baseURL }
        opts.sessionStore = store
        opts.sessionId = sessionId
        opts.persistSession = true
        opts.eventBus = bus

        let agent = Agent(options: opts)
        let messageStream = agent.stream("say hello auto-save")
        for await _ in messageStream {}

        var collected: [any AgentEvent] = []
        for await event in eventStream {
            collected.append(event)
            if collected.count >= 6 { break }
        }

        let autoSaved = collected.first { $0 is SessionAutoSavedEvent } as? SessionAutoSavedEvent
        guard autoSaved != nil else {
            fail("156. Stream emits SessionAutoSavedEvent", "no SessionAutoSavedEvent found in \(collected.count) events")
            return
        }
        guard autoSaved?.sessionId == sessionId else {
            fail("156. Stream emits SessionAutoSavedEvent", "sessionId mismatch: expected \(sessionId), got \(autoSaved?.sessionId ?? "nil")")
            return
        }
        guard (autoSaved?.messageCount ?? 0) >= 1 else {
            fail("156. Stream emits SessionAutoSavedEvent", "messageCount should be >= 1, got \(autoSaved?.messageCount ?? 0)")
            return
        }

        pass("156. Stream emits SessionAutoSavedEvent with sessionId and messageCount >= 1 via real LLM")
    }

    // MARK: Test 157: prompt() + SessionStore + persistSession → SessionAutoSavedEvent

    static func testPromptEmitsSessionAutoSavedEvent(apiKey: String, model: String, baseURL: String?) async {
        let bus = EventBus()
        let (_, eventStream) = await bus.subscribe()

        let tempDir = NSTemporaryDirectory() + "e2e-sess-autosave-prompt-\(UUID().uuidString.prefix(8))"
        let store = SessionStore(sessionsDir: tempDir)
        let sessionId = "e2e-autosave-prompt-\(UUID().uuidString.prefix(8))"

        var opts = AgentOptions(
            apiKey: apiKey,
            model: model,
            systemPrompt: "Reply with exactly: hello"
        )
        if let baseURL { opts.baseURL = baseURL }
        opts.sessionStore = store
        opts.sessionId = sessionId
        opts.persistSession = true
        opts.eventBus = bus

        let agent = Agent(options: opts)
        _ = await agent.prompt("say hello auto-save")

        var collected: [any AgentEvent] = []
        for await event in eventStream {
            collected.append(event)
            if collected.count >= 6 { break }
        }

        let autoSaved = collected.first { $0 is SessionAutoSavedEvent } as? SessionAutoSavedEvent
        guard autoSaved != nil else {
            fail("157. Prompt emits SessionAutoSavedEvent", "no SessionAutoSavedEvent found in \(collected.count) events")
            return
        }
        guard autoSaved?.sessionId == sessionId else {
            fail("157. Prompt emits SessionAutoSavedEvent", "sessionId mismatch: expected \(sessionId), got \(autoSaved?.sessionId ?? "nil")")
            return
        }
        guard (autoSaved?.messageCount ?? 0) >= 1 else {
            fail("157. Prompt emits SessionAutoSavedEvent", "messageCount should be >= 1, got \(autoSaved?.messageCount ?? 0)")
            return
        }

        pass("157. Prompt emits SessionAutoSavedEvent with sessionId and messageCount >= 1 via real LLM")
    }

    // MARK: Test 155: close() + EventBus → SessionClosedEvent

    static func testCloseEmitsSessionClosedEvent(apiKey: String, model: String, baseURL: String?) async {
        let bus = EventBus()
        let (_, eventStream) = await bus.subscribe()

        let sessionId = "e2e-sess-close-\(UUID().uuidString.prefix(8))"

        var opts = AgentOptions(
            apiKey: apiKey,
            model: model,
            systemPrompt: "You are a helper."
        )
        if let baseURL { opts.baseURL = baseURL }
        opts.sessionId = sessionId
        opts.eventBus = bus

        let agent = Agent(options: opts)

        do {
            try await agent.close()
        } catch {
            fail("155. Close emits SessionClosedEvent", "close() threw: \(error)")
            return
        }

        var collected: [any AgentEvent] = []
        for await event in eventStream {
            collected.append(event)
            if collected.count >= 1 { break }
        }

        guard collected.count >= 1 else {
            fail("155. Close emits SessionClosedEvent", "no events received")
            return
        }
        guard let closed = collected[0] as? SessionClosedEvent else {
            fail("155. Close emits SessionClosedEvent", "event is not SessionClosedEvent, got \(type(of: collected[0]))")
            return
        }
        guard closed.sessionId == sessionId else {
            fail("155. Close emits SessionClosedEvent", "sessionId mismatch: expected \(sessionId), got \(closed.sessionId ?? "nil")")
            return
        }
        guard closed.finalStatus == .completed else {
            fail("155. Close emits SessionClosedEvent", "finalStatus mismatch: expected .completed, got \(closed.finalStatus)")
            return
        }

        pass("155. Close emits SessionClosedEvent with sessionId and finalStatus=.completed")
    }
}
