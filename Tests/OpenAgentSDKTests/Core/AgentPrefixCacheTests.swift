import XCTest
@testable import OpenAgentSDK

final class AgentPrefixCacheTests: XCTestCase {

    // MARK: - Helpers

    private struct MockLLMClient: LLMClient, Sendable {
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
            return [
                "content": [["type": "text", "text": "response"]],
                "stop_reason": "end_turn",
                "usage": ["input_tokens": 10, "output_tokens": 5],
            ]
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
            AsyncThrowingStream { $0.finish() }
        }
    }

    private func makeAgent(systemPrompt: String? = "You are a helper.") -> Agent {
        Agent(
            options: AgentOptions(
                apiKey: "test-key",
                model: "claude-sonnet-4-6",
                systemPrompt: systemPrompt,
                gitCacheTTL: 0
            ),
            client: MockLLMClient()
        )
    }

    // MARK: - cachedSystemPrompt before first prompt

    func testCachedSystemPromptReturnsBuiltPromptBeforeFirstAPICall() {
        let agent = makeAgent(systemPrompt: "You are a helper.")
        let cached = agent.cachedSystemPrompt
        XCTAssertNotNil(cached)
        XCTAssertTrue(cached?.contains("You are a helper.") == true)
    }

    func testCachedSystemPromptReturnsNilWithRawModeAndNoPrompt() {
        // With _rawSystemPromptMode and no systemPrompt, buildSystemPrompt() returns nil
        let agent = Agent(
            options: {
                var opts = AgentOptions(
                    apiKey: "test-key",
                    model: "claude-sonnet-4-6",
                    systemPrompt: nil
                )
                opts._rawSystemPromptMode = true
                return opts
            }(),
            client: MockLLMClient()
        )
        XCTAssertNil(agent.cachedSystemPrompt)
    }

    // MARK: - cachedSystemPrompt after first prompt

    func testCachedSystemPromptPopulatedAfterPromptCall() async {
        let agent = makeAgent(systemPrompt: "Test prompt.")
        _ = await agent.prompt("hello")
        let cached = agent.cachedSystemPrompt
        XCTAssertNotNil(cached)
        XCTAssertTrue(cached?.contains("Test prompt.") == true)
    }

    func testCachedSystemPromptStableAcrossMultipleReads() async {
        let agent = makeAgent(systemPrompt: "Stability check.")
        _ = await agent.prompt("hello")
        let first = agent.cachedSystemPrompt
        let second = agent.cachedSystemPrompt
        XCTAssertEqual(first, second)
    }

    // MARK: - Review agent reuses cached prompt

    func testReviewAgentUsesCachedSystemPrompt() {
        let parent = makeAgent(systemPrompt: "Parent system prompt.")
        let parentCached = parent.cachedSystemPrompt

        let review = parent.createReviewAgent(config: ReviewAgentConfig())

        XCTAssertEqual(review.systemPrompt, parentCached)
        XCTAssertNil(review.options.cwd)
        XCTAssertNil(review.options.projectRoot)
        XCTAssertEqual(review.options.gitCacheTTL, 0)
        XCTAssertNil(review.options.systemPromptConfig)
        XCTAssertTrue(review.options._rawSystemPromptMode)
    }

    func testReviewAgentBuildsIdenticalSystemPrompt() {
        let parent = makeAgent(systemPrompt: "Exact match test.")
        let parentPrompt = parent.cachedSystemPrompt

        let review = parent.createReviewAgent(config: ReviewAgentConfig())
        // With _rawSystemPromptMode, buildSystemPrompt() returns systemPrompt verbatim
        let reviewPrompt = review.buildSystemPrompt()
        XCTAssertEqual(reviewPrompt, parentPrompt)
    }

    // MARK: - agentLabel

    func testAgentLabelDefaultsToNil() {
        let agent = makeAgent()
        XCTAssertNil(agent.options.agentLabel)
    }

    func testReviewAgentLabelIsSetToReview() {
        let parent = makeAgent()
        let review = parent.createReviewAgent(config: ReviewAgentConfig())
        XCTAssertEqual(review.options.agentLabel, "review")
    }
}
