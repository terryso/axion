import Foundation
import OpenAgentSDK

/// 会话工作流业务逻辑。纯函数 struct，不持有状态。
///
/// 处理 /new、/fork、/archive 命令的核心逻辑。
/// 外部依赖（SessionStore、确认输入）通过参数注入，便于测试。
struct SessionWorkflowHandler {

    // MARK: - /fork (AC2)

    /// /fork — 分叉当前会话。
    ///
    /// - Parameters:
    ///   - sessionId: 当前会话 ID
    ///   - sessionStore: SDK SessionStore 实例
    ///   - messageCount: 当前会话消息数（用于空会话保护）
    /// - Returns: `.forkSession(newId, sourceId)` 或 `.none`
    static func handleFork(
        sessionId: String,
        sessionStore: SessionStore,
        messageCount: Int
    ) async -> SlashCommandAction {
        // AC7: 空会话保护
        guard messageCount > 0 else {
            fputs(formatEmptySession("fork"), stderr)
            return .none
        }
        // 调用 SDK fork
        guard let newId = try? await sessionStore.fork(sourceSessionId: sessionId) else {
            fputs(formatForkError(), stderr)
            return .none
        }
        return .forkSession(newId: newId, sourceId: sessionId)
    }

    // MARK: - /archive (AC3)

    /// /archive — 确认后归档。
    ///
    /// - Parameters:
    ///   - sessionId: 当前会话 ID
    ///   - sessionStore: SDK SessionStore 实例
    ///   - messageCount: 当前会话消息数（用于空会话保护）
    ///   - confirmFn: 确认输入闭包（测试时注入 Mock）
    /// - Returns: `.archiveSession` 或 `.none`
    static func handleArchive(
        sessionId: String,
        sessionStore: SessionStore,
        messageCount: Int,
        confirmFn: () -> String? = { readLine() }
    ) async -> SlashCommandAction {
        // AC7: 空会话保护
        guard messageCount > 0 else {
            fputs(formatEmptySession("archive"), stderr)
            return .none
        }
        // AC3: 确认流程
        fputs(formatArchivePrompt(), stderr)
        guard let input = confirmFn(),
              input.lowercased() == "y" || input.lowercased() == "yes" else {
            // AC8: 非 TTY / 取消 — 安全默认
            fputs(formatArchiveCancelled(), stderr)
            return .none
        }
        // 标记归档：加载 → 修改 tag → 重新保存
        guard let data = try? await sessionStore.load(sessionId: sessionId) else {
            fputs(formatArchiveError(), stderr)
            return .none
        }
        let metadata = PartialSessionMetadata(
            cwd: data.metadata.cwd,
            model: data.metadata.model,
            summary: data.metadata.summary,
            tag: "archived"
        )
        try? await sessionStore.save(
            sessionId: sessionId,
            messages: data.messages,
            metadata: metadata
        )
        fputs(formatArchiveSuccess(sessionId: sessionId), stderr)
        return .archiveSession
    }

    // MARK: - Format helpers

    static func formatNewSuccess(sessionId: String) -> String {
        "[axion] ✅ 新会话已创建 (session: \(sessionId.prefix(8)))\n"
    }

    static func formatForkSuccess(newId: String, sourceId: String) -> String {
        "[axion] ✅ 已分叉会话 (新 session: \(newId.prefix(8)), 来源: \(sourceId.prefix(8)))\n"
    }

    static func formatForkError() -> String {
        "[axion] ❌ 分叉会话失败\n"
    }

    static func formatArchivePrompt() -> String {
        "确认归档当前会话? (y/N) "
    }

    static func formatArchiveCancelled() -> String {
        "[axion] 已取消归档\n"
    }

    static func formatArchiveSuccess(sessionId: String) -> String {
        "[axion] ✅ 会话已归档 (session: \(sessionId.prefix(8)))\n"
    }

    static func formatArchiveError() -> String {
        "[axion] ❌ 归档失败\n"
    }

    static func formatEmptySession(_ operation: String) -> String {
        "[axion] 当前会话无内容，无需\(operation)\n"
    }

    static func formatAgentBusy(_ operation: String) -> String {
        "[axion] 会话命令在 agent 执行时不可用，请等待当前任务完成\n"
    }
}
