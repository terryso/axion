import XCTest
@testable import OpenAgentSDK

final class PromptEvolverEngineTests: XCTestCase {

    // MARK: - Mock LLM Client

    private static let sharedState = SharedMockState()

    final class SharedMockState: @unchecked Sendable {
        var capturedModel: String?
        var capturedSystem: String?
        var capturedTemperature: Double?
        private let lock = NSLock()

        func record(model: String, system: String?, temperature: Double?) {
            lock.lock()
            capturedModel = model
            capturedSystem = system
            capturedTemperature = temperature
            lock.unlock()
        }

        func reset() {
            lock.lock()
            capturedModel = nil
            capturedSystem = nil
            capturedTemperature = nil
            lock.unlock()
        }
    }

    struct MockLLMClient: LLMClient, Sendable {
        let responseText: String
        let shouldThrow: Bool

        init(responseText: String = "{}", shouldThrow: Bool = false) {
            self.responseText = responseText
            self.shouldThrow = shouldThrow
        }

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
            if shouldThrow {
                throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "LLM call failed"])
            }
            PromptEvolverEngineTests.sharedState.record(
                model: model, system: system, temperature: temperature
            )
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

    private func makeMessages(count: Int) -> [SDKMessage] {
        (0..<count).map { i in
            SDKMessage.userMessage(.init(message: "Message \(i)"))
        }
    }

    private func validEvolutionJSON(
        shouldEvolve: Bool = true,
        evolvedPrompt: String = "Evolved prompt",
        changes: [[String: String]] = [["strategy": "refine", "section": "instructions", "original": "old", "modified": "new", "rationale": "test"]],
        confidence: Double = 0.85
    ) -> String {
        let changesArray = changes.map { change -> String in
            let pairs = change.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
            return "{ \(pairs) }"
        }.joined(separator: ", ")

        var json = "{\"shouldEvolve\": \(shouldEvolve)"
        if shouldEvolve {
            json += ", \"evolvedPrompt\": \"\(evolvedPrompt)\""
        }
        json += ", \"changes\": [\(changesArray)], \"confidence\": \(confidence)}"
        return json
    }

    override func setUp() {
        super.setUp()
        Self.sharedState.reset()
    }

    // MARK: - Evolution Tests

    func testEvolveWithValidResponse() async throws {
        let jsonText = validEvolutionJSON()
        let client = MockLLMClient(responseText: jsonText)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertTrue(result.shouldEvolve)
        XCTAssertEqual(result.evolvedPrompt, "Evolved prompt")
        XCTAssertEqual(result.changes.count, 1)
        XCTAssertEqual(result.changes[0].strategy, .refine)
        XCTAssertEqual(result.confidence, 0.85, accuracy: 0.001)
    }

    func testEvolveBelowMinConversationLength() async throws {
        let client = MockLLMClient(responseText: validEvolutionJSON())
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 6)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertFalse(result.shouldEvolve)
        XCTAssertTrue(result.changes.isEmpty)
    }

    func testEvolveMalformedJSON() async throws {
        let client = MockLLMClient(responseText: "not valid json {{{")
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertFalse(result.shouldEvolve)
    }

    func testEvolveEmptyResponse() async throws {
        let client = MockLLMClient(responseText: "")
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertFalse(result.shouldEvolve)
    }

    func testEvolveShouldEvolveFalse() async throws {
        let jsonText = "{\"shouldEvolve\": false}"
        let client = MockLLMClient(responseText: jsonText)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertFalse(result.shouldEvolve)
    }

    func testEvolveConfidenceClampedHigh() async throws {
        let jsonText = validEvolutionJSON(confidence: 2.5)
        let client = MockLLMClient(responseText: jsonText)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertEqual(result.confidence, 1.0, accuracy: 0.001)
    }

    func testEvolveConfidenceClampedLow() async throws {
        let jsonText = validEvolutionJSON(confidence: -1.0)
        let client = MockLLMClient(responseText: jsonText)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertEqual(result.confidence, 0.0, accuracy: 0.001)
    }

    func testEvolveMaxChangesCapped() async throws {
        let changes = (0..<10).map { i in
            ["strategy": "refine", "section": "s\(i)", "original": "o\(i)", "modified": "m\(i)", "rationale": "r\(i)"]
        }
        let jsonText = validEvolutionJSON(changes: changes)
        let client = MockLLMClient(responseText: jsonText)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2, maxChangesPerEvolution: 3)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertEqual(result.changes.count, 3)
    }

    func testEvolveLLMCallFailure() async throws {
        let client = MockLLMClient(shouldThrow: true)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertFalse(result.shouldEvolve)
    }

    func testEvolvePassesCorrectModel() async throws {
        let jsonText = validEvolutionJSON()
        let client = MockLLMClient(responseText: jsonText)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(evolutionModel: "test-model-v2", minConversationLength: 2)

        _ = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertEqual(Self.sharedState.capturedModel, "test-model-v2")
    }

    func testEvolvePassesCorrectTemperature() async throws {
        let jsonText = validEvolutionJSON()
        let client = MockLLMClient(responseText: jsonText)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(temperature: 0.7, minConversationLength: 2)

        _ = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertEqual(Self.sharedState.capturedTemperature ?? 0, 0.7, accuracy: 0.001)
    }

    func testEvolveResponseWithCodeFences() async throws {
        let jsonText = "```json\n\(validEvolutionJSON())\n```"
        let client = MockLLMClient(responseText: jsonText)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertTrue(result.shouldEvolve)
    }

    func testEvolveUnknownStrategySkipped() async throws {
        let changes = [
            ["strategy": "unknown_strategy", "section": "s", "original": "o", "modified": "m", "rationale": "r"],
            ["strategy": "refine", "section": "s2", "original": "o2", "modified": "m2", "rationale": "r2"]
        ]
        let jsonText = validEvolutionJSON(changes: changes)
        let client = MockLLMClient(responseText: jsonText)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2)

        let result = try await engine.evolve(
            currentPrompt: "Test prompt",
            messages: makeMessages(count: 3),
            config: config
        )

        XCTAssertEqual(result.changes.count, 1)
        XCTAssertEqual(result.changes[0].strategy, .refine)
    }

    func testEvolveEmptyPromptStillProceeds() async throws {
        let jsonText = validEvolutionJSON()
        let client = MockLLMClient(responseText: jsonText)
        let engine = PromptEvolverEngine(client: client)
        let config = PromptEvolutionConfig(minConversationLength: 2)

        let result = try await engine.evolve(
            currentPrompt: "",
            messages: makeMessages(count: 3),
            config: config
        )

        // Empty prompt is allowed — engine sends it as-is to LLM
        XCTAssertTrue(result.shouldEvolve)
    }
}
