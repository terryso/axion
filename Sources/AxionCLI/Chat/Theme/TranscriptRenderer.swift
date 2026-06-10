
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

    // MARK: - 回合摘要

    /// 渲染回合完成摘要 — dim/灰色分隔线，显示 turn 统计信息。
    ///
    /// 基础格式：`── 3.2s · 2 tools · ↑1.2k ↓856 ──`
    /// 含速度：  `── 3.2s (think 0.8s · 86 tok/s) · 2 tools · ↑1.2k ↓856 ──`
    /// 含上下文：`── 3.2s (think 0.8s · 86 tok/s) · 2 tools · ↑1.2k ↓856 · [████░░░░░░] 45% ──`
    /// 含成本：  `── 3.2s (think 0.8s · 86 tok/s) · 2 tools · ↑1.2k ↓856 · $0.01 ──`
    /// 全部：    `── 3.2s (think 0.8s · 86 tok/s) · 2 tools · ↑1.2k ↓856 · [████░░░░░░] 45% · $0.01 ──`
    ///
    /// 非 TTY：`[turn: 3.2s (think 0.8s, 86 tok/s) · 2 tools · ↑1.2k ↓856 · ctx 45% · $0.01]`
    ///
    /// Codex-inspired: 显示 TTFT（Time To First Token）和生成速度，
    /// 帮助用户了解模型响应性能。
    ///
    /// - Parameters:
    ///   - duration: 格式化的时长字符串（如 "3.2s"）
    ///   - toolCount: 本轮工具调用次数
    ///   - inputTokens: 格式化的输入 token 数
    ///   - outputTokens: 格式化的输出 token 数
    ///   - contextPct: 可选的上下文窗口使用百分比（0-100）
    ///   - estimatedCost: 可选的预估成本字符串（如 "$0.01"）
    ///   - responseSpeed: 可选的响应速度分析结果
    func renderTurnSummary(
        duration: String,
        toolCount: Int,
        inputTokens: String,
        outputTokens: String,
        contextPct: Int? = nil,
        estimatedCost: String? = nil,
        responseSpeed: ResponseSpeed? = nil
    ) -> String {
        let toolStr = toolCount == 1 ? "1 tool" : "\(toolCount) tools"
        var stats = "\(duration)"

        // 添加响应速度指标 — Codex-inspired TTFT + tok/s
        if let speed = responseSpeed {
            if theme.isTTY {
                if let speedStr = speed.formatCompact() {
                    stats += " (\(speedStr))"
                }
            } else {
                if let speedStr = speed.formatPlain() {
                    stats += " (\(speedStr))"
                }
            }
        }

        stats += " · \(toolStr) · ↑\(inputTokens) ↓\(outputTokens)"

        // 添加上下文窗口使用率
        if let pct = contextPct {
            stats += " · \(formatContextSegment(pct: pct))"
        }

        // 添加预估成本
        if let cost = estimatedCost {
            stats += " · \(cost)"
        }

        guard theme.isTTY else {
            return "[turn: \(stats)]\n"
        }

        let dimCode: String
        switch theme.profile {
        case .trueColor:
            dimCode = "\u{1B}[38;2;120;120;120m"
        case .ansi256:
            dimCode = "\u{1B}[38;5;244m"
        case .ansi16:
            dimCode = "\u{1B}[2m"  // dim/faint attribute
        case .unknown:
            return "[turn: \(stats)]\n"
        }
        let reset = "\u{1B}[0m"
        return "\(dimCode)── \(stats) ──\(reset)\n"
    }

    // MARK: - 上下文进度条

    /// 渲染上下文窗口使用率的微型进度条段。
    ///
    /// TTY 模式：颜色编码进度条 `[████░░░░░░] 45%`
    /// 上下文颜色：绿(<50%) → 黄(50-80%) → 红(>80%)
    ///
    /// - Parameter pct: 使用百分比 (0-100)
    /// - Returns: 格式化的上下文段
    private func formatContextSegment(pct: Int) -> String {
        let clampedPct = max(0, min(pct, 200))
        let bar = BannerRenderer.renderContextBar(pct: clampedPct, width: 8)

        guard theme.isTTY else {
            return "ctx \(clampedPct)%"
        }

        let colorCode = BannerRenderer.contextBarColor(pct: clampedPct, profile: theme.profile)
        let reset = "\u{1B}[0m"
        return "\(colorCode)[\(bar)]\(reset) \(clampedPct)%"
    }
}
