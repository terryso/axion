
/// 对话视觉语义主题 — AC7: 颜色降级链统一适配
///
/// 纯 struct，无 I/O。接收 `TerminalColorProfile` + `isTTY`，
/// 提供角色圆点、纯文本前缀、消息块格式化等视觉方法。
///
/// 所有视觉输出组件通过 `ChatTheme` 获取一致的格式化结果，
/// 确保整场会话中颜色和图标含义保持一致。
struct ChatTheme: Sendable, Equatable {
    let profile: TerminalColorProfile
    let isTTY: Bool

    // MARK: - 角色圆点 (AC1/AC2/AC3)

    /// 格式化带颜色的角色圆点字符串。
    /// - TTY + 颜色 profile → `\033[3Xm●\033[0m`
    /// - 非 TTY 或 unknown → `[role]` 纯文本前缀
    func formatRoleDot(role: TranscriptRole) -> String {
        guard isTTY else { return formatPlainText(role: role) }

        let colorCode = profile.ansiColor(for: role)
        if colorCode.isEmpty {
            // unknown profile 回退纯文本
            return formatPlainText(role: role)
        }
        return "\(colorCode)●\u{1B}[0m"
    }

    // MARK: - 纯文本前缀 (AC4)

    /// 非 TTY / unknown profile 时的纯文本角色前缀
    func formatPlainText(role: TranscriptRole) -> String {
        switch role {
        case .user:       return "[user]"
        case .assistant:  return "[ai]"
        case .tool:       return "[tool]"
        case .warning:    return "[warn]"
        }
    }

}
