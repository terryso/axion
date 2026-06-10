import Foundation

/// 上下文压缩结果的可视化格式化器 — Codex 启发。
///
/// 将压缩前后的 token 变化渲染为带进度条的直观展示：
/// - TTY: 双进度条（before → after）+ 节省百分比 + 空间回收指标
/// - 非 TTY: 纯文本格式（与原 formatCompactMessage 一致）
///
/// 设计原则：
/// - 纯函数 + static 方法，无状态，无 I/O
/// - 复用 BannerRenderer.renderContextBar 和 contextBarColor
/// - 支持所有 TerminalColorProfile 降级
/// - contextWindow 为 0 时降级为纯文本
struct CompactionDisplayFormatter: Sendable {

    // MARK: - Public API

    /// 格式化压缩结果的可视化展示。
    ///
    /// - Parameters:
    ///   - beforeTokens: 压缩前 token 数
    ///   - afterTokens: 压缩后 token 数
    ///   - contextWindow: 上下文窗口大小（用于计算进度条）
    ///   - isTTY: 是否连接到 TTY
    ///   - profile: 终端颜色 profile
    /// - Returns: 格式化的压缩结果字符串
    ///
    /// TTY 示例：
    /// ```
    /// [axion] ✂ 上下文已自动压缩 (90k → 8k tokens)
    ///   [█████████░] 90% → [█░░░░░░░░░] 8% · 节省 82k (91%)
    /// ```
    ///
    /// 非 TTY 示例：
    /// ```
    /// [axion] 上下文已自动压缩 (90k → 8k tokens)
    /// ```
    static func format(
        beforeTokens: Int,
        afterTokens: Int,
        contextWindow: Int = 0,
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        profile: TerminalColorProfile = .detect()
    ) -> String {
        let before = BannerRenderer.formatTokenCount(beforeTokens)
        let after = BannerRenderer.formatTokenCount(afterTokens)
        let header = "[axion] 上下文已自动压缩 (\(before) → \(after) tokens)\n"

        // 非 TTY 或无 contextWindow → 仅显示头部
        guard isTTY, contextWindow > 0 else {
            return header
        }

        // 计算百分比
        let beforePct = contextWindow > 0
            ? Int(Double(beforeTokens) / Double(contextWindow) * 100)
            : 0
        let afterPct = contextWindow > 0
            ? Int(Double(afterTokens) / Double(contextWindow) * 100)
            : 0
        let saved = beforeTokens - afterTokens
        let savedPct = beforeTokens > 0
            ? Int(Double(saved) / Double(beforeTokens) * 100)
            : 0

        // 颜色码
        let reset = "\u{1B}[0m"
        let beforeColor = BannerRenderer.contextBarColor(pct: beforePct, profile: profile)
        let afterColor = BannerRenderer.contextBarColor(pct: afterPct, profile: profile)
        let dimCode = Self.dimCode(for: profile)
        let savedColor = Self.savedColor(for: profile)

        // 进度条
        let barWidth = 10
        let beforeBar = BannerRenderer.renderContextBar(pct: beforePct, width: barWidth)
        let afterBar = BannerRenderer.renderContextBar(pct: afterPct, width: barWidth)

        let savedStr = BannerRenderer.formatTokenCount(saved)

        // 构建视觉行
        let scissors = "\(dimCode)✂\(reset) "
        let detailLine =
            "  \(beforeColor)[\(beforeBar)]\(reset) \(beforeColor)\(clamped(beforePct))%\(reset)"
            + " \(dimCode)→\(reset) "
            + "\(afterColor)[\(afterBar)]\(reset) \(afterColor)\(clamped(afterPct))%\(reset)"
            + " \(dimCode)·\(reset) \(savedColor)节省 \(savedStr) (\(clamped(savedPct))%)\(reset)\n"

        return "\(scissors)\(header)\(detailLine)"
    }

    // MARK: - Internal Helpers

    /// 将百分比限制在 0-200 范围内。
    private static func clamped(_ pct: Int) -> Int {
        max(0, min(pct, 200))
    }

    /// 节省空间的颜色（青绿色，表示正面结果）。
    private static func savedColor(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;52;211;153m"   // emerald-400
        case .ansi256: return "\u{1B}[38;5;77m"
        case .ansi16: return "\u{1B}[36m"                    // cyan
        case .unknown: return ""
        }
    }

    /// dim 样式颜色码。
    private static func dimCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;148;163;184m"   // slate-400
        case .ansi256: return "\u{1B}[38;5;145m"
        case .ansi16: return "\u{1B}[37m"
        case .unknown: return ""
        }
    }
}
