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

    /// 生成带上下文用量和可视化进度条的提示符。
    ///
    /// Codex-inspired: 显示上下文窗口使用百分比 + 微型进度条 + 颜色编码。
    /// 进度条使用 Unicode block 元素：█▓▒░
    /// 颜色随使用率变化：绿(<50%) → 黄(50-80%) → 红(>80%)
    ///
    /// - TTY 示例：`axion [12k/200k 6% ▏░░░░░░░░░]> `
    /// - 高使用率：`axion [180k/200k 90% ████████░░]> `（红色）
    /// - 非 TTY：  `axion [12k/200k 6%]> `（无进度条、无颜色）
    static func renderPrompt(
        usedTokens: Int,
        contextWindow: Int,
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        colorProfile: TerminalColorProfile = .detect()
    ) -> String {
        let used = formatTokenCount(usedTokens)
        let max = formatTokenCount(contextWindow)
        let pct = contextWindow > 0
            ? Int(Double(usedTokens) / Double(contextWindow) * 100)
            : 0

        guard isTTY else {
            return "axion [\(used)/\(max) \(pct)%]> "
        }

        let bar = renderContextBar(pct: pct, width: 10)
        let colorCode = contextBarColor(pct: pct, profile: colorProfile)
        let reset = "\u{1B}[0m"

        return "axion [\(used)/\(max) \(colorCode)\(pct)%\(reset) \(colorCode)\(bar)\(reset)]> "
    }

    // MARK: - Context Progress Bar

    /// 渲染上下文窗口使用率的微型进度条。
    ///
    /// 使用 Unicode block 元素表示进度：
    /// - `█` 已使用
    /// - `░` 未使用
    ///
    /// - Parameters:
    ///   - pct: 使用百分比 (0-100)
    ///   - width: 进度条宽度（字符数）
    /// - Returns: 进度条字符串，如 `███░░░░░░░`
    static func renderContextBar(pct: Int, width: Int = 10) -> String {
        let clampedPct = max(0, min(100, pct))
        let filled = Int(Double(clampedPct) / 100.0 * Double(width))
        let empty = width - filled
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }

    /// 根据上下文使用百分比返回颜色 ANSI 码。
    ///
    /// - < 50% → 绿色（充裕）
    /// - 50-80% → 黄色（注意）
    /// - > 80% → 红色（紧张）
    static func contextBarColor(pct: Int, profile: TerminalColorProfile) -> String {
        let clampedPct = max(0, min(100, pct))
        switch profile {
        case .trueColor:
            if clampedPct > 80 {
                return "\u{1B}[38;2;244;67;54m"   // 红
            } else if clampedPct >= 50 {
                return "\u{1B}[38;2;255;193;7m"   // 黄
            } else {
                return "\u{1B}[38;2;76;175;80m"   // 绿
            }
        case .ansi256:
            if clampedPct > 80 {
                return "\u{1B}[38;5;160m"   // 暗红
            } else if clampedPct >= 50 {
                return "\u{1B}[38;5;178m"   // 黄
            } else {
                return "\u{1B}[38;5;71m"    // 绿
            }
        case .ansi16:
            if clampedPct > 80 {
                return "\u{1B}[31m"  // red
            } else if clampedPct >= 50 {
                return "\u{1B}[33m"  // yellow
            } else {
                return "\u{1B}[32m"  // green
            }
        case .unknown:
            return ""
        }
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
