import XCTest
@testable import OpenAgentSDK

/// Tests for Agent.executeSkillStream() — streaming direct skill execution.
final class ExecuteSkillStreamTests: XCTestCase {

    // MARK: - Helper: Create a test skill

    private func makeSkill(
        name: String = "test_skill",
        description: String = "A test skill",
        aliases: [String] = [],
        toolRestrictions: [ToolRestriction]? = nil,
        modelOverride: String? = nil,
        isAvailable: @escaping @Sendable () -> Bool = { true },
        promptTemplate: String = "Test prompt template"
    ) -> Skill {
        Skill(
            name: name,
            description: description,
            aliases: aliases,
            toolRestrictions: toolRestrictions,
            modelOverride: modelOverride,
            isAvailable: isAvailable,
            promptTemplate: promptTemplate
        )
    }

    // MARK: - Error Cases

    /// Returns error result when skill is not found in registry.
    func testExecuteSkillStream_notFound_returnsError() async {
        let registry = SkillRegistry()
        let agent = createAgent(options: AgentOptions(
            apiKey: "test-key",
            model: "claude-sonnet-4-6",
            tools: getAllBaseTools(tier: .core),
            skillRegistry: registry
        ))

        let stream = agent.executeSkillStream("nonexistent")
        var messages: [SDKMessage] = []
        for await message in stream {
            messages.append(message)
        }

        // Should yield exactly one .result message with errorDuringExecution
        let resultMessages = messages.compactMap { msg -> SDKMessage.ResultData? in
            if case .result(let data) = msg { return data }
            return nil
        }
        XCTAssertEqual(resultMessages.count, 1)
        XCTAssertEqual(resultMessages[0].subtype, .errorDuringExecution)
        XCTAssertTrue((resultMessages[0].errors?.first ?? "").contains("not found"))
    }

    /// Returns error result when skill is registered but not available.
    func testExecuteSkillStream_notAvailable_returnsError() async {
        let registry = SkillRegistry()
        registry.register(makeSkill(
            name: "unavailable",
            isAvailable: { false }
        ))

        let agent = createAgent(options: AgentOptions(
            apiKey: "test-key",
            model: "claude-sonnet-4-6",
            tools: getAllBaseTools(tier: .core),
            skillRegistry: registry
        ))

        let stream = agent.executeSkillStream("unavailable")
        var messages: [SDKMessage] = []
        for await message in stream {
            messages.append(message)
        }

        let resultMessages = messages.compactMap { msg -> SDKMessage.ResultData? in
            if case .result(let data) = msg { return data }
            return nil
        }
        XCTAssertEqual(resultMessages.count, 1)
        XCTAssertEqual(resultMessages[0].subtype, .errorDuringExecution)
        XCTAssertTrue((resultMessages[0].errors?.first ?? "").contains("not available"))
    }

    /// Returns empty stream when agent is closed.
    func testExecuteSkillStream_agentClosed_returnsEmpty() async {
        let registry = SkillRegistry()
        registry.register(makeSkill(name: "closed-test"))

        let agent = createAgent(options: AgentOptions(
            apiKey: "test-key",
            model: "claude-sonnet-4-6",
            tools: getAllBaseTools(tier: .core),
            skillRegistry: registry
        ))

        try? await agent.close()
        let stream = agent.executeSkillStream("closed-test")
        var messages: [SDKMessage] = []
        for await message in stream {
            messages.append(message)
        }

        XCTAssertTrue(messages.isEmpty)
    }

    // MARK: - State Restoration

    /// Restores allowedTools after streaming skill execution.
    func testExecuteSkillStream_restoresAllowedTools() async {
        let registry = SkillRegistry()
        registry.register(makeSkill(
            name: "restricted-skill",
            toolRestrictions: [.bash, .read],
            promptTemplate: "Do restricted things"
        ))

        let agent = createAgent(options: AgentOptions(
            apiKey: "test-key",
            model: "claude-sonnet-4-6",
            tools: getAllBaseTools(tier: .core),
            skillRegistry: registry,
            allowedTools: ["Bash", "Read", "Write"]
        ))

        XCTAssertEqual(agent.options.allowedTools, ["Bash", "Read", "Write"])

        // Consume stream (will fail with API error since key is fake, but state should still restore)
        let stream = agent.executeSkillStream("restricted-skill")
        for await _ in stream {}

        XCTAssertEqual(agent.options.allowedTools, ["Bash", "Read", "Write"])
    }

    /// Restores model after streaming skill execution when skill has modelOverride.
    func testExecuteSkillStream_restoresModel() async {
        let registry = SkillRegistry()
        registry.register(makeSkill(
            name: "opus-skill",
            modelOverride: "claude-opus-4-6",
            promptTemplate: "Do opus things"
        ))

        let agent = createAgent(options: AgentOptions(
            apiKey: "test-key",
            model: "claude-sonnet-4-6",
            tools: getAllBaseTools(tier: .core),
            skillRegistry: registry
        ))

        XCTAssertEqual(agent.model, "claude-sonnet-4-6")

        let stream = agent.executeSkillStream("opus-skill")
        for await _ in stream {}

        XCTAssertEqual(agent.model, "claude-sonnet-4-6")
    }

    /// Does not change model when skill has no modelOverride.
    func testExecuteSkillStream_noModelOverride_keepsModel() async {
        let registry = SkillRegistry()
        registry.register(makeSkill(
            name: "basic-skill",
            modelOverride: nil,
            promptTemplate: "Do basic things"
        ))

        let agent = createAgent(options: AgentOptions(
            apiKey: "test-key",
            model: "claude-sonnet-4-6",
            tools: getAllBaseTools(tier: .core),
            skillRegistry: registry
        ))

        XCTAssertEqual(agent.model, "claude-sonnet-4-6")
        let stream = agent.executeSkillStream("basic-skill")
        for await _ in stream {}
        XCTAssertEqual(agent.model, "claude-sonnet-4-6")
    }
}
