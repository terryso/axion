import Foundation
import OpenAgentSDK

import AxionCore

// MARK: - ChatREPLState

/// Mutable state for the chat REPL loop.
///
/// Groups all session-related state so session-switch operations (new, fork,
/// resume) can update everything in one place instead of repeating 10+ variable
/// assignments at each call site.
struct ChatREPLState: Sendable {
    var buildResult: AgentBuildResult
    var buildConfig: AgentBuilder.BuildConfig
    var sessionId: String
    var sessionUsage: TokenUsage
    var contextTokens: Int
    var contextWindow: Int
    var sessionUserMessages: [String]
    var resumedMessageBaseCount: Int
    var lastInterruptTime: ContinuousClock.Instant?
    var lastResumeList: [SessionInfo]
    var consecutiveCompactFailures: Int

    /// Immutable parameters needed to build a new agent for a session switch.
    struct BuildParams: Sendable {
        let config: AxionConfig
        let noMemory: Bool
        let noSkills: Bool
        let maxSteps: Int?
        let verbose: Bool
        let permissionMode: PermissionMode
        let canUseTool: CanUseToolFn
    }

    /// Result of a successful session switch — caller uses this to update the
    /// interrupt target held by the installed signal handler.
    struct SwitchResult: Sendable {
        let newAgent: Agent
    }
}

// MARK: - Session Switch

extension ChatREPLState {
    /// Rebuild the agent for `targetSessionId`, close the old agent, and update
    /// all session state.  Returns the new agent for signal-handler wiring.
    ///
    /// - Parameters:
    ///   - targetSessionId: Session ID to switch to.
    ///   - params: Immutable build parameters.
    ///   - resetMessages: Clear `sessionUserMessages` (true for new/resume, false
    ///     when you'll set `resumedMessageBaseCount` manually).
    ///   - resetBaseCount: Reset `resumedMessageBaseCount` to 0.  Set false for
    ///     fork (inherits history).
    mutating func switchToSession(
        _ targetSessionId: String,
        params: BuildParams,
        resetMessages: Bool = true,
        resetBaseCount: Bool = true
    ) async throws -> SwitchResult {
        let oldAgent = buildResult.agent

        let newConfig = AgentBuilder.BuildConfig.forChat(
            config: params.config,
            noMemory: params.noMemory,
            noSkills: params.noSkills,
            maxSteps: params.maxSteps,
            verbose: params.verbose,
            sessionId: targetSessionId,
            sessionStore: buildConfig.sessionStore,
            permissionMode: params.permissionMode,
            canUseTool: params.canUseTool
        )

        let newBuildResult = try await AgentBuilder.build(newConfig)
        try? await oldAgent.close()

        self.buildResult = newBuildResult
        self.buildConfig = newConfig
        self.sessionId = targetSessionId
        self.sessionUsage = TokenUsage(inputTokens: 0, outputTokens: 0)
        self.contextTokens = 0
        self.contextWindow = getContextWindowSize(model: newBuildResult.agent.model)
        if resetMessages {
            self.sessionUserMessages = []
        }
        if resetBaseCount {
            self.resumedMessageBaseCount = 0
        }
        self.lastInterruptTime = nil
        self.lastResumeList = []

        return SwitchResult(newAgent: newBuildResult.agent)
    }
}

// MARK: - Resume Session

extension ChatREPLState {
    /// Resume a session by ID — shared between slash command and direct-number paths.
    /// Validates the target, switches the session, updates base count, and prints
    /// the resume banner.  Returns the new agent on success, nil on failure (error
    /// already printed to stderr).
    mutating func resumeSession(
        targetSessionId: String,
        params: BuildParams
    ) async -> SwitchResult? {
        guard let resumedCount = await ResumeValidator.validate(
            targetSessionId: targetSessionId,
            currentSessionId: sessionId,
            sessionStore: buildConfig.sessionStore
        ) else {
            return nil
        }

        do {
            let result = try await switchToSession(
                targetSessionId,
                params: params
            )
            resumedMessageBaseCount = resumedCount
            fputs(
                BannerRenderer.renderResumeBanner(
                    sessionId: targetSessionId,
                    messageCount: resumedCount,
                    model: result.newAgent.model,
                    contextWindow: contextWindow
                ),
                stderr
            )
            return result
        } catch {
            fputs(SessionResumeManager.formatResumeError(error), stderr)
            return nil
        }
    }
}

// MARK: - Resume Validation

/// Common validation logic shared between the `/resume <id>` slash-command
/// handler and the direct-number-selection path.
enum ResumeValidator {
    /// Validate that a resume target is feasible.  On success returns the
    /// loaded session's message count.  On failure prints a message to stderr
    /// and returns `nil`.
    static func validate(
        targetSessionId: String,
        currentSessionId: String,
        sessionStore: SessionStore?
    ) async -> Int? {
        guard let store = sessionStore else {
            fputs("[axion] 无法访问会话存储\n", stderr)
            return nil
        }
        guard targetSessionId != currentSessionId else {
            fputs(SessionResumeManager.formatSessionAlreadyRunning(targetSessionId), stderr)
            return nil
        }
        guard let sessionData = try? await store.load(sessionId: targetSessionId) else {
            fputs(SessionResumeManager.formatSessionNotFound(targetSessionId), stderr)
            return nil
        }
        return sessionData.metadata.messageCount
    }
}
