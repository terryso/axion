import AxionCore

/// 会话恢复格式化与辅助逻辑。纯函数 struct，不持有状态。
///
/// 会话列表获取与 agent 重建由 ChatCommand 直接执行（需要 async/await
/// 和 SDK SessionStore 交互），本组件只负责格式化和消息生成。
struct SessionResumeManager {

    /// 格式化会话列表为文本表格（带序号，支持按序号恢复）。
    ///
    /// 格式：`#  SESSION TASK STATUS STEPS TAG CREATED`
    /// - Parameter sessions: 会话列表
    /// - Parameter includeArchived: 是否包含已归档会话（AC4: 默认不包含）
    static func formatSessionList(_ sessions: [SessionInfo], includeArchived: Bool = false) -> String {
        // AC4: 默认过滤归档会话
        let filtered = includeArchived ? sessions : sessions.filter { $0.tag != "archived" }
        guard !filtered.isEmpty else {
            return "无可恢复的会话\n"
        }

        let header = pad("#", to: 4) + pad("SESSION", to: 16) + pad("TASK", to: 26) + pad("STATUS", to: 12) + pad("STEPS", to: 6) + pad("TAG", to: 10) + "CREATED"

        var lines = [header]

        for (index, session) in filtered.enumerated() {
            let num = "\(index + 1)"
            let sessionId = truncate(session.sessionId, maxLength: 14)
            let task = truncate(session.summary ?? "-", maxLength: 23)
            let status = session.status
            let steps = "\(session.totalSteps)"
            let tag = session.tag ?? ""
            let created = session.createdAt.map { axionDateTimeFormatter.string(from: $0) } ?? "-"

            let line = pad(num, to: 4) + pad(sessionId, to: 16) + pad(task, to: 26) + pad(status, to: 12) + pad(steps, to: 6) + pad(tag, to: 10) + created
            lines.append(line)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// 格式化会话列表末尾提示。
    static func formatResumeHint() -> String {
        "\n输入序号（如 1）或 /resume <session-id> 恢复会话\n"
    }

    /// 从序号解析 session ID。
    ///
    /// 支持两种输入：
    /// - 纯数字（如 `1`、`3`）：按序号从列表中查找
    /// - Session ID（如 `chat-ABC123`）：直接使用
    ///
    /// - Returns: 匹配的 session ID，未匹配返回 nil
    static func resolveSessionId(from input: String, sessions: [SessionInfo]) -> String? {
        // 尝试按序号解析
        if let index = Int(input.trimmingCharacters(in: .whitespaces)) {
            let oneBased = index - 1
            guard oneBased >= 0, oneBased < sessions.count else {
                return nil
            }
            return sessions[oneBased].sessionId
        }
        // 直接使用 session ID（可能是不完整的 ID 前缀）
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        // 精确匹配
        if sessions.contains(where: { $0.sessionId == trimmed }) {
            return trimmed
        }
        // 前缀匹配
        let matches = sessions.filter { $0.sessionId.hasPrefix(trimmed) }
        if matches.count == 1 {
            return matches[0].sessionId
        }
        return nil
    }

    /// 格式化恢复错误消息。
    static func formatResumeError(_ error: Error) -> String {
        "[axion] 恢复失败: \(error.localizedDescription)\n"
    }

    /// 格式化 "会话未找到" 错误。
    static func formatSessionNotFound(_ sessionId: String) -> String {
        "[axion] 会话未找到: \(sessionId)\n"
    }

    /// 格式化 "会话正在运行" 错误。
    static func formatSessionAlreadyRunning(_ sessionId: String) -> String {
        "[axion] 会话正在运行: \(sessionId)\n"
    }
}

// MARK: - Shared String Formatting Helpers

/// 右填充字符串到指定宽度（用于表格对齐）。
func pad(_ string: String, to width: Int) -> String {
    if string.count >= width {
        return string
    }
    return string + String(repeating: " ", count: width - string.count)
}

/// 截断字符串到指定长度，超出部分用 "…" 表示。
func truncate(_ string: String, maxLength: Int) -> String {
    if string.count > maxLength {
        return String(string.prefix(maxLength)) + "..."
    }
    return string
}

