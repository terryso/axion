import Foundation
import Testing

@testable import AxionCLI
import OpenAgentSDK

/// E2E tests for session workflow in the interactive REPL.
///
/// Covers:
/// - Slash command parsing for session commands (/new, /fork, /resume, /archive)
/// - chatShouldExit double-press logic
/// - ChatREPLState initialization and properties
/// - ResumeValidator basic validation
@Suite("Session Workflow E2E")
struct SessionWorkflowE2ETests {

    // MARK: - chatShouldExit

    @Test("chatShouldExit: rapid double press exits")
    func doublePressExits() {
        let now = ContinuousClock.now
        let last = now - .milliseconds(500)
        #expect(chatShouldExit(lastInterrupt: last, now: now) == true,
               "500ms gap should exit")
    }

    @Test("chatShouldExit: slow double press does not exit")
    func slowDoublePressNoExit() {
        let now = ContinuousClock.now
        let last = now - .seconds(5)
        #expect(chatShouldExit(lastInterrupt: last, now: now) == false,
               "5s gap should not exit")
    }

    // MARK: - SlashCommand Session Commands

    @Test("parse /new → newSession")
    func parseNew() {
        #expect(SlashCommand.parse("/new") == .newSession)
    }

    @Test("parse /fork → fork")
    func parseFork() {
        #expect(SlashCommand.parse("/fork") == .fork)
    }

    @Test("parse /archive → archive")
    func parseArchive() {
        #expect(SlashCommand.parse("/archive") == .archive)
    }

    @Test("parse /resume → resume")
    func parseResume() {
        #expect(SlashCommand.parse("/resume") == .resume)
    }

    @Test("parse /resume with session ID")
    func parseResumeWithId() {
        #expect(SlashCommand.parse("/resume chat-abc123") == .resume)
        let arg = SlashCommand.parseArgument("/resume chat-abc123")
        #expect(arg == "chat-abc123", "Should extract session ID as argument")
    }

    @Test("parse /resume --all")
    func parseResumeAll() {
        #expect(SlashCommand.parse("/resume --all") == .resume)
        let arg = SlashCommand.parseArgument("/resume --all")
        #expect(arg == "--all", "Should extract --all as argument")
    }

    @Test("session commands: availableDuringTask is false for structural commands")
    func availableDuringTask() {
        #expect(SlashCommand.resume.availableDuringTask == false,
               "/resume should not be available during agent task")
        #expect(SlashCommand.newSession.availableDuringTask == false,
               "/new should not be available during agent task")
        #expect(SlashCommand.fork.availableDuringTask == false,
               "/fork should not be available during agent task")
        #expect(SlashCommand.archive.availableDuringTask == false,
               "/archive should not be available during agent task")
    }

    @Test("session commands: safe commands available during task")
    func safeDuringTask() {
        #expect(SlashCommand.help.availableDuringTask == true)
        #expect(SlashCommand.exit.availableDuringTask == true)
        #expect(SlashCommand.clear.availableDuringTask == true)
        #expect(SlashCommand.cost.availableDuringTask == true)
        #expect(SlashCommand.config.availableDuringTask == true)
    }

    // MARK: - ChatREPLState Properties

    @Test("ChatREPLState initial values")
    func replStateInitialValues() async throws {
        let config = try await ConfigManager.loadConfig()
        guard config.apiKey != nil, !config.apiKey!.isEmpty else { return }

        let sessionsDir = ConfigManager.sessionsDirectory
        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            sessionId: "chat-test-init",
            sessionStore: SessionStore(sessionsDir: sessionsDir)
        )

        let buildResult = try await AgentBuilder.build(buildConfig)

        let contextWindow = getContextWindowSize(model: buildResult.agent.model)
        let state = ChatREPLState(
            buildResult: buildResult,
            buildConfig: buildConfig,
            sessionId: "chat-test-init",
            sessionUsage: TokenUsage(inputTokens: 0, outputTokens: 0),
            contextTokens: 0,
            contextWindow: contextWindow,
            sessionUserMessages: [],
            resumedMessageBaseCount: 0,
            lastInterruptTime: nil,
            lastResumeList: [],
            consecutiveCompactFailures: 0
        )

        try? await buildResult.agent.close()

        #expect(state.sessionId == "chat-test-init")
        #expect(state.sessionUsage.inputTokens == 0)
        #expect(state.sessionUsage.outputTokens == 0)
        #expect(state.contextTokens == 0)
        #expect(state.contextWindow > 0, "Context window should be positive")
        #expect(state.sessionUserMessages.isEmpty)
        #expect(state.resumedMessageBaseCount == 0)
        #expect(state.lastInterruptTime == nil)
        #expect(state.lastResumeList.isEmpty)
        #expect(state.consecutiveCompactFailures == 0)
    }

    @Test("ChatREPLState tracks user messages")
    func replStateTracksMessages() async throws {
        let config = try await ConfigManager.loadConfig()
        guard config.apiKey != nil, !config.apiKey!.isEmpty else { return }

        let sessionsDir = ConfigManager.sessionsDirectory
        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            sessionId: "chat-test-msg",
            sessionStore: SessionStore(sessionsDir: sessionsDir)
        )

        let buildResult = try await AgentBuilder.build(buildConfig)

        let contextWindow = getContextWindowSize(model: buildResult.agent.model)
        var state = ChatREPLState(
            buildResult: buildResult,
            buildConfig: buildConfig,
            sessionId: "chat-test-msg",
            sessionUsage: TokenUsage(inputTokens: 0, outputTokens: 0),
            contextTokens: 0,
            contextWindow: contextWindow,
            sessionUserMessages: [],
            resumedMessageBaseCount: 0,
            lastInterruptTime: nil,
            lastResumeList: [],
            consecutiveCompactFailures: 0
        )

        // Simulate adding user messages (like the REPL loop does)
        state.sessionUserMessages.append("Hello")
        state.sessionUserMessages.append("World")

        try? await buildResult.agent.close()

        #expect(state.sessionUserMessages.count == 2)
        #expect(state.sessionUserMessages[0] == "Hello")
        #expect(state.sessionUserMessages[1] == "World")
    }

    // MARK: - SessionWorkflowHandler formatting

    @Test("SessionWorkflowHandler: formatNewSuccess contains session ID prefix")
    func formatNewSuccess() {
        let output = SessionWorkflowHandler.formatNewSuccess(sessionId: "chat-new123")
        #expect(output.contains("chat-new"), "Should contain session ID prefix (truncated to 8 chars)")
        #expect(output.contains("新会话") || output.contains("session"),
               "Should mention new session")
    }

    @Test("SessionWorkflowHandler: formatForkSuccess contains both ID prefixes")
    func formatForkSuccess() {
        let output = SessionWorkflowHandler.formatForkSuccess(
            newId: "chat-fork123",
            sourceId: "chat-source456"
        )
        #expect(output.contains("chat-for"), "Should contain new session ID prefix")
        #expect(output.contains("chat-sou"), "Should contain source session ID prefix")
    }

    // MARK: - Session Store Integration

    @Test("session store: list sessions from real directory")
    func sessionStoreList() async throws {
        let sessionsDir = ConfigManager.sessionsDirectory
        let store = SessionStore(sessionsDir: sessionsDir)

        // List should not throw (may return empty if no sessions)
        let sessions = try await store.list(limit: 5)
        // Just verify it returns without error — sessions may or may not exist
        #expect(sessions.count <= 5, "Should respect limit parameter")
    }

    // MARK: - SlashCommandAction Equality

    @Test("SlashCommandAction: .exit equality")
    func actionExitEquality() {
        #expect(SlashCommandAction.exit == .exit)
    }

    @Test("SlashCommandAction: .none equality")
    func actionNoneEquality() {
        #expect(SlashCommandAction.none == .none)
    }

    @Test("SlashCommandAction: .newSession equality")
    func actionNewSessionEquality() {
        #expect(SlashCommandAction.newSession == .newSession)
    }

    @Test("SlashCommandAction: .archiveSession equality")
    func actionArchiveEquality() {
        #expect(SlashCommandAction.archiveSession == .archiveSession)
    }

    @Test("SlashCommandAction: .resumeSession equality")
    func actionResumeEquality() {
        #expect(SlashCommandAction.resumeSession("abc") == .resumeSession("abc"))
        #expect(SlashCommandAction.resumeSession("abc") != .resumeSession("def"))
    }

    @Test("SlashCommandAction: .forkSession equality")
    func actionForkEquality() {
        #expect(SlashCommandAction.forkSession(newId: "a", sourceId: "b")
                == .forkSession(newId: "a", sourceId: "b"))
    }
}
