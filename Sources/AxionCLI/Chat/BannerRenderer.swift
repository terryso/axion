import Foundation

/// 交互模式横幅和提示符格式化。纯函数，不持有状态。
struct BannerRenderer {

    /// 格式化 token 数量为人类可读字符串。
    ///
    /// - 0 → "0"
    /// - 500 → "500"
    /// - 3200 → "3.2k"
    /// - 1_500_000 → "1.5m"
    static func formatTokenCount(_ tokens: Int) -> String {
        if tokens < 1_000 { return "\(tokens)" }
        // 999,950 is the threshold: %.1f of 999.95 rounds to 1000.0, so switch to m format
        if tokens < 999_950 {
            let k = Double(tokens) / 1_000.0
            return k == floor(k) ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        let m = Double(tokens) / 1_000_000.0
        return m == floor(m) ? "\(Int(m))m" : String(format: "%.1fm", m)
    }

    /// 生成启动横幅文本（简洁文本格式，无 Unicode box-drawing）。
    static func renderBanner(
        version: String,
        model: String,
        cwd: String,
        sessionId: String,
        contextWindow: Int,
        buildTimeMs: Int
    ) -> String {
        let contextMax = formatTokenCount(contextWindow)
        let duration = formatDurationMs(buildTimeMs)
        let displayCwd = truncatePath(cwd, maxLength: 60)
        return """
            Axion v\(version) · \(model) · \(displayCwd) [\(duration)]
            Session: \(sessionId) · Context: 0/\(contextMax)
            输入任务开始对话，/help 查看命令

            """
    }

    /// 生成带上下文用量的提示符。
    static func renderPrompt(usedTokens: Int, contextWindow: Int) -> String {
        let used = formatTokenCount(usedTokens)
        let max = formatTokenCount(contextWindow)
        return "axion [\(used)/\(max)]> "
    }

    /// 生成退出信息。
    static func renderExit(sessionId: String) -> String {
        "[axion] 会话 \(sessionId) 已保存，使用 /resume 可恢复\n"
    }

    /// 生成恢复会话横幅。
    static func renderResumeBanner(
        sessionId: String,
        messageCount: Int,
        model: String,
        contextWindow: Int
    ) -> String {
        let contextMax = formatTokenCount(contextWindow)
        return """
            [axion] 已恢复会话 \(sessionId) (\(messageCount) 条消息)
            Model: \(model) · Context: 0/\(contextMax)
            输入任务继续对话，/help 查看命令

            """
    }

    // MARK: - Private helpers

    /// 路径截断：超过 maxLength 时保留尾部并加 "…" 前缀。
    private static func truncatePath(_ path: String, maxLength: Int) -> String {
        guard path.count > maxLength else { return path }
        let truncated = path.suffix(maxLength - 1)
        return "…" + truncated
    }
}
