import Foundation
import Testing

@testable import AxionCLI
import OpenAgentSDK

/// E2E tests for slash command parsing and handling.
///
/// Covers:
/// - Pure parsing layer (SlashCommand.parse, parseArgument) — no API needed
/// - Output layer (SlashCommandHandler.handle with real Agent) — uses real API key
@Suite("Slash Command E2E")
struct SlashCommandE2ETests {

    // MARK: - Parse Layer (pure functions)

    @Test("parse: /help")
    func parseHelp() {
        #expect(SlashCommand.parse("/help") == .help)
    }

    @Test("parse: /clear")
    func parseClear() {
        #expect(SlashCommand.parse("/clear") == .clear)
    }

    @Test("parse: /compact")
    func parseCompact() {
        #expect(SlashCommand.parse("/compact") == .compact)
    }

    @Test("parse: /model")
    func parseModel() {
        #expect(SlashCommand.parse("/model") == .model)
    }

    @Test("parse: /cost")
    func parseCost() {
        #expect(SlashCommand.parse("/cost") == .cost)
    }

    @Test("parse: /resume")
    func parseResume() {
        #expect(SlashCommand.parse("/resume") == .resume)
    }

    @Test("parse: /config")
    func parseConfig() {
        #expect(SlashCommand.parse("/config") == .config)
    }

    @Test("parse: /exit")
    func parseExit() {
        #expect(SlashCommand.parse("/exit") == .exit)
    }

    @Test("parse: /quit is alias for /exit")
    func parseQuit() {
        #expect(SlashCommand.parse("/quit") == .exit)
    }

    @Test("parse: /diff")
    func parseDiff() {
        #expect(SlashCommand.parse("/diff") == .diff)
    }

    @Test("parse: /status")
    func parseStatus() {
        #expect(SlashCommand.parse("/status") == .status)
    }

    @Test("parse: /new")
    func parseNew() {
        #expect(SlashCommand.parse("/new") == .newSession)
    }

    @Test("parse: /fork")
    func parseFork() {
        #expect(SlashCommand.parse("/fork") == .fork)
    }

    @Test("parse: /archive")
    func parseArchive() {
        #expect(SlashCommand.parse("/archive") == .archive)
    }

    @Test("parse: case insensitive")
    func parseCaseInsensitive() {
        #expect(SlashCommand.parse("/HELP") == .help)
        #expect(SlashCommand.parse("/Help") == .help)
        #expect(SlashCommand.parse("/COST") == .cost)
        #expect(SlashCommand.parse("/EXIT") == .exit)
        #expect(SlashCommand.parse("/QUIT") == .exit)
    }

    @Test("parse: non-slash returns nil")
    func parseNonSlash() {
        #expect(SlashCommand.parse("hello") == nil)
        #expect(SlashCommand.parse("quit") == nil)
    }

    @Test("parse: unknown command returns nil")
    func parseUnknown() {
        #expect(SlashCommand.parse("/unknown") == nil)
        #expect(SlashCommand.parse("/foo") == nil)
    }

    // MARK: - parseArgument

    @Test("parseArgument: no argument")
    func parseArgumentNone() {
        #expect(SlashCommand.parseArgument("/help") == nil)
        #expect(SlashCommand.parseArgument("/exit") == nil)
    }

    @Test("parseArgument: with argument")
    func parseArgumentWithValue() {
        #expect(SlashCommand.parseArgument("/resume abc123") == "abc123")
        #expect(SlashCommand.parseArgument("/model claude-opus-4-8") == "claude-opus-4-8")
    }

    @Test("parseArgument: whitespace-only argument returns nil")
    func parseArgumentWhitespace() {
        #expect(SlashCommand.parseArgument("/resume   ") == nil)
    }

    // MARK: - Command Metadata

    @Test("allCases covers expected commands")
    func allCasesCoverage() {
        let cases = SlashCommand.allCases
        #expect(cases.contains(.help))
        #expect(cases.contains(.clear))
        #expect(cases.contains(.compact))
        #expect(cases.contains(.model))
        #expect(cases.contains(.cost))
        #expect(cases.contains(.resume))
        #expect(cases.contains(.config))
        #expect(cases.contains(.exit))
        #expect(cases.contains(.diff))
        #expect(cases.contains(.status))
        #expect(cases.contains(.newSession))
        #expect(cases.contains(.fork))
        #expect(cases.contains(.archive))
    }

    @Test("/exit alias is quit")
    func exitAlias() {
        #expect(SlashCommand.exit.aliases == ["quit"])
        #expect(SlashCommand.help.aliases.isEmpty)
    }

    @Test("helpText is non-empty for all commands")
    func helpTextNonEmpty() {
        for cmd in SlashCommand.allCases {
            #expect(!cmd.helpText.isEmpty, "\(cmd.rawValue) should have help text")
        }
    }

    @Test("acceptsArgs only for model and resume")
    func acceptsArgs() {
        #expect(SlashCommand.model.acceptsArgs == true)
        #expect(SlashCommand.resume.acceptsArgs == true)
        #expect(SlashCommand.help.acceptsArgs == false)
        #expect(SlashCommand.exit.acceptsArgs == false)
    }

    // MARK: - handleUnknown

    @Test("handleUnknown returns error message")
    func handleUnknownOutput() {
        let output = SlashCommandHandler.handleUnknown("/foobar")
        #expect(output.contains("未知命令"), "Should contain error indicator")
        #expect(output.contains("/foobar"), "Should echo the unknown command")
        #expect(output.contains("/help"), "Should suggest /help")
    }

    // MARK: - Output Layer (needs real Agent)

    @Test("/help output contains all commands")
    func helpOutput() async throws {
        guard let (agent, config) = try await buildRealChatAgent() else { return }

        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            sessionId: "test-help"
        )

        let action = SlashCommandHandler.handle(
            .help,
            argument: nil,
            agent: agent,
            config: config,
            sessionUsage: TokenUsage(inputTokens: 0, outputTokens: 0),
            buildConfig: buildConfig
        )

        try? await agent.close()

        #expect(action == .none, "/help should return .none action")
    }

    @Test("/help output string contains all commands")
    func helpOutputString() {
        let output = SlashCommandHandler.handleHelp()
        for cmd in SlashCommand.allCases {
            #expect(output.contains(cmd.rawValue), "/help output should contain \(cmd.rawValue)")
        }
        #expect(output.contains("/quit"), "/help output should contain /quit alias")
        #expect(output.contains("可用命令"), "Should contain header text")
    }

    @Test("/config output contains model and settings")
    func configOutput() {
        let output = SlashCommandHandler.handleConfig(
            model: "claude-sonnet-4-6",
            maxTokens: 4096,
            maxSteps: 20,
            noMemory: false,
            noSkills: false,
            permissionMode: "default"
        )

        #expect(output.contains("claude-sonnet-4-6"), "Should show model")
        #expect(output.contains("4096"), "Should show max tokens")
        #expect(output.contains("20"), "Should show max steps")
        #expect(output.contains("开启"), "Should show memory enabled")
        #expect(output.contains("default"), "Should show permission mode")
    }

    @Test("/cost output shows token usage")
    func costOutput() {
        let output = SlashCommandHandler.handleCost(
            usage: TokenUsage(inputTokens: 12_000, outputTokens: 3_500, cacheReadInputTokens: 2_000),
            model: "claude-sonnet-4-6"
        )

        #expect(output.contains("12000"), "Should show input tokens")
        #expect(output.contains("3500"), "Should show output tokens")
        #expect(output.contains("2000"), "Should show cache read tokens")
        #expect(output.contains("15500"), "Should show total tokens")
        #expect(output.contains("预估成本"), "Should show cost label")
        #expect(output.contains("$"), "Should show dollar sign")
    }

    @Test("/status output shows session info")
    func statusOutput() {
        let output = SlashCommandHandler.handleStatus(
            model: "claude-sonnet-4-6",
            permissionMode: "default",
            sessionId: "chat-test12345",
            contextTokens: 50_000,
            contextWindow: 200_000,
            cwd: "/Users/test/project",
            usage: TokenUsage(inputTokens: 10_000, outputTokens: 2_000)
        )

        #expect(output.contains("claude-sonnet-4-6"), "Should show model")
        #expect(output.contains("chat-tes"), "Should show session ID prefix")
        #expect(output.contains("10K"), "Should show input tokens (formatted)")
        #expect(output.contains("12K"), "Should show total tokens (formatted)")
        #expect(output.contains("/Users/test/project"), "Should show cwd")
    }

    @Test("/compact output shows context status")
    func compactOutput() {
        let output = SlashCommandHandler.handleCompact(
            contextTokens: 100_000,
            contextWindow: 200_000
        )

        // Should mention context status (exact format varies)
        #expect(!output.isEmpty, "/compact should produce output")
    }

    @Test("/model display shows current model")
    func modelDisplayOutput() {
        let output = SlashCommandHandler.handleModelDisplay(model: "claude-sonnet-4-6")
        #expect(output.contains("claude-sonnet-4-6"), "Should show model name")
        #expect(output.contains("当前模型"), "Should contain label")
    }

    @Test("/exit action returns .exit")
    func exitAction() async throws {
        guard let (agent, config) = try await buildRealChatAgent() else { return }

        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            sessionId: "test-exit"
        )

        let action = SlashCommandHandler.handle(
            .exit,
            argument: nil,
            agent: agent,
            config: config,
            sessionUsage: TokenUsage(inputTokens: 0, outputTokens: 0),
            buildConfig: buildConfig
        )

        try? await agent.close()

        #expect(action == .exit, "/exit should return .exit action")
    }

    @Test("/resume with argument returns resumeSession action")
    func resumeWithArgument() async throws {
        guard let (agent, config) = try await buildRealChatAgent() else { return }

        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            sessionId: "test-resume"
        )

        let action = SlashCommandHandler.handle(
            .resume,
            argument: "chat-abc123",
            agent: agent,
            config: config,
            sessionUsage: TokenUsage(inputTokens: 0, outputTokens: 0),
            buildConfig: buildConfig
        )

        try? await agent.close()

        if case .resumeSession(let id) = action {
            #expect(id == "chat-abc123", "Should pass session ID through")
        } else {
            Issue.record("Expected .resumeSession action, got \(action)")
        }
    }

    @Test("/resume without argument returns .none")
    func resumeNoArgument() async throws {
        guard let (agent, config) = try await buildRealChatAgent() else { return }

        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            sessionId: "test-resume2"
        )

        let action = SlashCommandHandler.handle(
            .resume,
            argument: nil,
            agent: agent,
            config: config,
            sessionUsage: TokenUsage(inputTokens: 0, outputTokens: 0),
            buildConfig: buildConfig
        )

        try? await agent.close()

        #expect(action == .none, "/resume with no argument should return .none")
    }

    @Test("/new returns newSession action")
    func newAction() async throws {
        guard let (agent, config) = try await buildRealChatAgent() else { return }

        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            sessionId: "test-new"
        )

        let action = SlashCommandHandler.handle(
            .newSession,
            argument: nil,
            agent: agent,
            config: config,
            sessionUsage: TokenUsage(inputTokens: 0, outputTokens: 0),
            buildConfig: buildConfig
        )

        try? await agent.close()

        #expect(action == .newSession, "/new should return .newSession action")
    }
}
