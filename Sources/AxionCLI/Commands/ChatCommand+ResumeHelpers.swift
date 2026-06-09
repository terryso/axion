import Foundation
import OpenAgentSDK

import AxionCore

// MARK: - Interrupt helpers

/// Check if double Ctrl+C should trigger exit (AC2: within 2 seconds).
func chatShouldExit(
    lastInterrupt: ContinuousClock.Instant,
    now: ContinuousClock.Instant
) -> Bool {
    (now - lastInterrupt) < .seconds(2)
}

// MARK: - Resume helpers

/// 处理 /resume 无参数时列出可恢复的会话。返回会话列表供后续序号选择。
func handleResumeList(
    buildConfig: AgentBuilder.BuildConfig,
    sessionsDir: String,
    includeArchived: Bool = false
) async -> [SessionInfo] {
    guard let store = buildConfig.sessionStore else {
        fputs("[axion] 无法获取会话列表\n", stderr)
        return []
    }
    do {
        let metadataList = try await store.list(limit: 20)
        let sessions = metadataList.map { md in
            SessionInfo(
                sessionId: md.id,
                cwd: md.cwd,
                model: md.model,
                createdAt: md.createdAt,
                updatedAt: md.updatedAt,
                messageCount: md.messageCount,
                summary: md.summary ?? md.firstPrompt,
                status: "unknown",
                totalSteps: 0,
                durationMs: nil,
                tag: md.tag
            )
        }
        let resumable = Array(sessions.prefix(10))
        fputs(SessionResumeManager.formatSessionList(resumable, includeArchived: includeArchived), stderr)
        fputs(SessionResumeManager.formatResumeHint(), stderr)
        return resumable
    } catch {
        fputs(SessionResumeManager.formatResumeError(error), stderr)
        return []
    }
}

// MARK: - Resume target resolution

/// Resolve a raw `/resume` argument to a concrete session ID.
/// Supports index numbers (e.g. "1") or full/partial session IDs.
func resolveResumeTarget(
    rawArg: String,
    state: inout ChatREPLState,
    sessionsDir: String
) async -> String {
    // If list is empty and arg looks like a number, auto-load session list
    if state.lastResumeList.isEmpty, Int(rawArg.trimmingCharacters(in: .whitespaces)) != nil {
        state.lastResumeList = await handleResumeList(
            buildConfig: state.buildConfig,
            sessionsDir: sessionsDir
        )
    }

    if !state.lastResumeList.isEmpty,
       let resolved = SessionResumeManager.resolveSessionId(
           from: rawArg, sessions: state.lastResumeList
       ) {
        return resolved
    }

    // Not found in list — treat as raw session ID
    return rawArg
}
