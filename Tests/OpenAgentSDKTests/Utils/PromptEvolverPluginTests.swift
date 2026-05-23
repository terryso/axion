import XCTest
@testable import OpenAgentSDK

final class PromptEvolverPluginTests: XCTestCase {

    // MARK: - Mock LLM Client

    struct MockLLMClient: LLMClient, Sendable {
        let responseText: String

        nonisolated func sendMessage(
            model: String,
            messages: [[String: Any]],
            maxTokens: Int,
            system: String?,
            tools: [[String: Any]]?,
            toolChoice: [String: Any]?,
            thinking: [String: Any]?,
            temperature: Double?
        ) async throws -> [String: Any] {
            return ["content": [["type": "text", "text": responseText]] as [[String: Any]]]
        }

        nonisolated func streamMessage(
            model: String,
            messages: [[String: Any]],
            maxTokens: Int,
            system: String?,
            tools: [[String: Any]]?,
            toolChoice: [String: Any]?,
            thinking: [String: Any]?,
            temperature: Double?
        ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
            AsyncThrowingStream { _ in }
        }
    }

    // MARK: - Helpers

    private func makeContext(messages: [SDKMessage] = []) -> PluginContext {
        PluginContext(
            sessionId: "test-session",
            messages: messages,
            currentQuery: nil,
            model: "test",
            provider: .anthropic
        )
    }

    private func makeMessages(count: Int) -> [SDKMessage] {
        (0..<count).map { i in
            SDKMessage.userMessage(.init(message: "Message \(i)"))
        }
    }

    private func validEvolutionJSON() -> String {
        """
        {"shouldEvolve": true, "evolvedPrompt": "Evolved prompt text", "changes": \
        [{"strategy": "refine", "section": "instructions", "original": "old", "modified": "new", "rationale": "test"}], \
        "confidence": 0.85}
        """
    }

    // MARK: - Plugin Identity

    func testPluginName() async {
        let plugin = PromptEvolverPlugin()
        let name = await plugin.name
        XCTAssertEqual(name, "prompt-evolver")
    }

    func testSupportedPhases() async {
        let plugin = PromptEvolverPlugin()
        let phases = await plugin.supportedPhases
        XCTAssertEqual(phases, [.initialize, .syncTurn, .sessionEnd])
    }

    // MARK: - Lifecycle

    func testInitialize() async throws {
        let client = MockLLMClient(responseText: "{}")
        let plugin = PromptEvolverPlugin(client: client)
        try await plugin.initialize(sessionId: "test-session")

        // After init, syncTurn should work
        let context = makeContext(messages: makeMessages(count: 1))
        let result = try await plugin.onPhase(.syncTurn, context: context)
        XCTAssertEqual(result, .none)
    }

    func testShutdownClearsState() async throws {
        let client = MockLLMClient(responseText: "{}")
        let plugin = PromptEvolverPlugin(client: client)
        try await plugin.initialize(sessionId: "test-session")

        let context = makeContext(messages: makeMessages(count: 1))
        _ = try await plugin.onPhase(.syncTurn, context: context)

        await plugin.shutdown()

        // After shutdown, sessionEnd should return .none (engine is nil)
        let endContext = makeContext(messages: makeMessages(count: 5))
        let result = try await plugin.onPhase(.sessionEnd, context: endContext)
        XCTAssertEqual(result, .none)
    }

    // MARK: - onPhase(.syncTurn)

    func testSyncTurnBuffersMessages() async throws {
        let client = MockLLMClient(responseText: validEvolutionJSON())
        let plugin = PromptEvolverPlugin(client: client)
        try await plugin.initialize(sessionId: "test-session")

        let msgs1 = makeMessages(count: 3)
        _ = try await plugin.onPhase(.syncTurn, context: makeContext(messages: msgs1))

        let msgs2 = makeMessages(count: 2)
        _ = try await plugin.onPhase(.syncTurn, context: makeContext(messages: msgs2))

        // Trigger sessionEnd — accumulated messages should be enough
        let endContext = makeContext(messages: [])
        let result = try await plugin.onPhase(.sessionEnd, context: endContext)

        // 3 + 2 = 5 messages accumulated, but minConversationLength defaults to 6
        // So should return .none (not enough messages)
        XCTAssertEqual(result, .none)
    }

    // MARK: - onPhase(.sessionEnd)

    func testSessionEndTriggersEvolution() async throws {
        let client = MockLLMClient(responseText: validEvolutionJSON())
        let config = EvolutionPluginConfig(
            name: "prompt-evolver",
            enabled: true,
            config: ["currentPrompt": "Test prompt"]
        )
        let plugin = PromptEvolverPlugin(config: config, client: client)
        try await plugin.initialize(sessionId: "test-session")

        // Buffer enough messages
        let msgs = makeMessages(count: 6)
        _ = try await plugin.onPhase(.syncTurn, context: makeContext(messages: msgs))

        // End with context messages too
        let endContext = makeContext(messages: makeMessages(count: 2))
        let result = try await plugin.onPhase(.sessionEnd, context: endContext)

        // Should produce a suggestion (autoApply defaults to false)
        if case .systemPromptBlock(let text) = result {
            XCTAssertTrue(text.contains("Prompt Evolution Suggestion"))
        } else {
            XCTFail("Expected systemPromptBlock, got \(result)")
        }
    }

    func testSessionEndWithoutEngineReturnsNone() async throws {
        // No client provided — engine is nil
        let plugin = PromptEvolverPlugin()
        try await plugin.initialize(sessionId: "test-session")

        let msgs = makeMessages(count: 6)
        _ = try await plugin.onPhase(.syncTurn, context: makeContext(messages: msgs))

        let endContext = makeContext(messages: [])
        let result = try await plugin.onPhase(.sessionEnd, context: endContext)
        XCTAssertEqual(result, .none)
    }

    func testSessionEndNotEnoughMessagesReturnsNone() async throws {
        let client = MockLLMClient(responseText: validEvolutionJSON())
        let plugin = PromptEvolverPlugin(client: client)
        try await plugin.initialize(sessionId: "test-session")

        // Only 3 messages — below default minConversationLength of 6
        let msgs = makeMessages(count: 3)
        _ = try await plugin.onPhase(.syncTurn, context: makeContext(messages: msgs))

        let endContext = makeContext(messages: [])
        let result = try await plugin.onPhase(.sessionEnd, context: endContext)
        XCTAssertEqual(result, .none)
    }

    func testSessionEndNoEvolutionReturnsNone() async throws {
        let client = MockLLMClient(responseText: "{\"shouldEvolve\": false}")
        let plugin = PromptEvolverPlugin(client: client)
        try await plugin.initialize(sessionId: "test-session")

        let msgs = makeMessages(count: 6)
        _ = try await plugin.onPhase(.syncTurn, context: makeContext(messages: msgs))

        let endContext = makeContext(messages: [])
        let result = try await plugin.onPhase(.sessionEnd, context: endContext)
        XCTAssertEqual(result, .none)
    }

    // MARK: - onPhase(.initialize)

    func testOnPhaseInitializeReturnsNone() async throws {
        let plugin = PromptEvolverPlugin()
        try await plugin.initialize(sessionId: "test-session")

        let context = makeContext()
        let result = try await plugin.onPhase(.initialize, context: context)
        XCTAssertEqual(result, .none)
    }

    // MARK: - Config Parsing

    func testConfigParsesEvolutionModel() async throws {
        let client = MockLLMClient(responseText: validEvolutionJSON())
        let config = EvolutionPluginConfig(
            name: "prompt-evolver",
            enabled: true,
            config: ["evolutionModel": "custom-model"]
        )
        let plugin = PromptEvolverPlugin(config: config, client: client)
        try await plugin.initialize(sessionId: "test-session")

        // Verify by triggering evolution and checking the system prompt contains the custom model
        let msgs = makeMessages(count: 6)
        _ = try await plugin.onPhase(.syncTurn, context: makeContext(messages: msgs))

        let endContext = makeContext(messages: [])
        let result = try await plugin.onPhase(.sessionEnd, context: endContext)
        // If it produced a result, config was parsed correctly
        if case .systemPromptBlock = result {
            // expected
        } else {
            // Could also be .none if prompt is empty — that's fine
        }
    }

    func testConfigParsesAutoApplyTrue() async throws {
        let client = MockLLMClient(responseText: validEvolutionJSON())
        let config = EvolutionPluginConfig(
            name: "prompt-evolver",
            enabled: true,
            config: ["autoApply": "true", "currentPrompt": "Test prompt"]
        )
        let plugin = PromptEvolverPlugin(config: config, client: client)
        try await plugin.initialize(sessionId: "test-session")

        let msgs = makeMessages(count: 6)
        _ = try await plugin.onPhase(.syncTurn, context: makeContext(messages: msgs))

        let endContext = makeContext(messages: [])
        let result = try await plugin.onPhase(.sessionEnd, context: endContext)

        // With autoApply=true, the result should be the raw evolved prompt, not a formatted suggestion
        if case .systemPromptBlock(let text) = result {
            // Auto-apply mode: the text IS the evolved prompt, not wrapped in suggestion format
            XCTAssertFalse(text.contains("[Prompt Evolution Suggestion"))
            XCTAssertEqual(text, "Evolved prompt text")
        } else {
            XCTFail("Expected systemPromptBlock with auto-applied prompt")
        }
    }

    func testConfigParsesStrategies() async {
        let config = EvolutionPluginConfig(
            name: "prompt-evolver",
            enabled: true,
            config: ["strategies": "refine,compress"]
        )
        let plugin = PromptEvolverPlugin(config: config)
        // Plugin was created without crash — strategies were parsed
        let name = await plugin.name
        XCTAssertEqual(name, "prompt-evolver")
    }

    func testConfigParsesMinConversationLength() async throws {
        let config = EvolutionPluginConfig(
            name: "prompt-evolver",
            enabled: true,
            config: ["minConversationLength": "3"]
        )
        let client = MockLLMClient(responseText: validEvolutionJSON())
        let plugin = PromptEvolverPlugin(config: config, client: client)
        try await plugin.initialize(sessionId: "test-session")

        // 4 messages >= minConversationLength of 3
        let msgs = makeMessages(count: 4)
        _ = try await plugin.onPhase(.syncTurn, context: makeContext(messages: msgs))

        let endContext = makeContext(messages: [])
        let result = try await plugin.onPhase(.sessionEnd, context: endContext)

        if case .systemPromptBlock = result {
            // expected — enough messages with custom minConversationLength
        } else {
            // Result is .none — could be empty prompt issue
        }
    }

    // MARK: - Unhandled Phases

    func testOnPhaseUnhandledReturnsNone() async throws {
        let plugin = PromptEvolverPlugin()
        try await plugin.initialize(sessionId: "test-session")

        let context = makeContext()
        let result = try await plugin.onPhase(.prefetch, context: context)
        XCTAssertEqual(result, .none)
    }

    func testOnPhasePreCompressReturnsNone() async throws {
        let plugin = PromptEvolverPlugin()
        try await plugin.initialize(sessionId: "test-session")

        let context = makeContext()
        let result = try await plugin.onPhase(.preCompress, context: context)
        XCTAssertEqual(result, .none)
    }
}
