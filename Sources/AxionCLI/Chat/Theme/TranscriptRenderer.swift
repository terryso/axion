
/// 对话角色枚举 — AC1/AC2/AC3
///
/// 四种角色对应四种视觉标识：
/// - user: 蓝色圆点 `●`（用户消息）
/// - assistant: 绿色圆点 `●`（AI 回复）
/// - tool: 黄色圆点 `●`（工具事件）
/// - warning: 红色圆点 `●`（警告/审批）
enum TranscriptRole: String, Sendable, Equatable, CaseIterable {
    case user
    case assistant
    case tool
    case warning
}

/// 对话渲染器 — AC1/AC2/AC3: 角色消息块渲染
///
/// 纯函数 struct，无 I/O。所有方法返回格式化字符串，
/// 由调用方决定输出目标（stdout/stderr）。
///
/// 每个方法接受 `ChatTheme` 参数，输出格式化字符串。
/// 增量添加角色圆点，不替换现有的 ⏳/✅/❌ 图标。
struct TranscriptRenderer: Sendable {
    let theme: ChatTheme

    // MARK: - 用户消息 (AC1)

    /// 渲染用户消息 — 蓝色圆点 + 用户消息文本
    func renderUserMessage(text: String) -> String {
        let dot = theme.formatRoleDot(role: .user)
        return "\(dot) \(text)\n"
    }

    // MARK: - Assistant Block (AC2)

    /// 渲染 assistant block 开始标记 — 绿色圆点
    /// 后续流式文本由 ChatOutputFormatter 直接输出（不加前缀）
    func renderAssistantBlockStart() -> String {
        let dot = theme.formatRoleDot(role: .assistant)
        return "\(dot) "
    }

    // MARK: - 警告/审批 (AC3)

    /// 渲染警告/审批消息 — 红色圆点 + 消息文本
    func renderWarning(message: String) -> String {
        let dot = theme.formatRoleDot(role: .warning)
        return "\(dot) \(message)\n"
    }
}
