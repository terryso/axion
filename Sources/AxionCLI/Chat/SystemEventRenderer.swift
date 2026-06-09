import Foundation
import OpenAgentSDK

/// 系统事件渲染器 — 受 Codex 的 "context compacted" / "warning:" / "model rerouted:" 模式启发，
/// 将 SDK 的系统级事件（上下文压缩、速率限制、状态变更）渲染为终端友好的样式化输出。
///
/// 设计原则：
/// - 纯函数（static methods），无状态，易于测试
/// - 完整颜色 profile 降级链（TrueColor → ANSI256 → ANSI16 → unknown/非 TTY 纯文本）
/// - 受 Codex 的 `EventProcessorWithHumanOutput` 中 `render_item_completed` 和
///   `process_server_notification` 的样式处理启发
struct SystemEventRenderer {

    // MARK: - ANSI Constants

    private static let reset = "\u{1B}[0m"
    private static let bold = "\u{1B}[1m"
    private static let dim = "\u{1B}[2m"
    private static let italic = "\u{1B}[3m"

    // MARK: - Compaction Event

    /// 渲染上下文压缩边界事件通知。
    ///
    /// Codex 风格：`📦 context compacted (15K→5K tokens, saved 67%)` dimmed 样式
    ///
    /// - Parameters:
    ///   - metadata: 压缩元数据（含 preTokens/postTokens/durationMs/trigger）
    ///   - isTTY: 是否为 TTY 输出
    ///   - colorProfile: 终端颜色能力
    /// - Returns: 格式化的压缩通知字符串（含换行），无元数据时返回 nil
    static func renderCompaction(
        metadata: SDKMessage.CompactMetadata?,
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        colorProfile: TerminalColorProfile = .detect()
    ) -> String? {
        guard let metadata = metadata else { return nil }

        let preTokens = metadata.preTokens
        let postTokens = metadata.postTokens

        // 构建核心信息
        var info = "context compacted"
        if let pre = preTokens, let post = postTokens, pre > 0 {
            let saved = pre - post
            let pct = Int(Double(saved) / Double(pre) * 100)
            let preStr = formatTokenCount(pre)
            let postStr = formatTokenCount(post)
            info += " (\(preStr)→\(postStr), saved \(pct)%)"
        }

        // 附加触发类型
        if let trigger = metadata.trigger {
            info += " [\(trigger.rawValue)]"
        }

        // 附加耗时
        if let duration = metadata.durationMs {
            info += " \(formatDurationMs(duration))"
        }

        guard isTTY else {
            return "📦 \(info)\n"
        }

        let dimCode = dimCode(for: colorProfile)
        return "\(dimCode)📦 \(info)\(reset)\n"
    }

    // MARK: - Status Event

    /// 渲染系统状态事件（compacting/requesting 等）。
    ///
    /// Codex 风格：`⏳ compacting...` 或 `⏳ requesting API...` dimmed 样式
    ///
    /// - Parameters:
    ///   - statusValue: 状态值（"compacting"/"requesting"）
    ///   - compactResult: 压缩结果（"success"/"failed"），仅 status 为 compacting 时有意义
    ///   - compactError: 压缩错误消息
    ///   - isTTY: 是否为 TTY 输出
    ///   - colorProfile: 终端颜色能力
    /// - Returns: 格式化的状态通知字符串（含换行），nil statusValue 时返回 nil
    static func renderStatus(
        statusValue: String?,
        compactResult: String?,
        compactError: String?,
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        colorProfile: TerminalColorProfile = .detect()
    ) -> String? {
        guard let status = statusValue, !status.isEmpty else { return nil }

        let message: String
        switch status {
        case "compacting":
            if let result = compactResult {
                if result == "success" {
                    message = "context compaction succeeded"
                } else {
                    var text = "context compaction failed"
                    if let error = compactError, !error.isEmpty {
                        text += ": \(error)"
                    }
                    message = text
                }
            } else {
                message = "compacting context..."
            }
        case "requesting":
            message = "requesting API..."
        default:
            message = "\(status)..."
        }

        guard isTTY else {
            return "⏳ \(message)\n"
        }

        let dimCode = self.dimCode(for: colorProfile)
        return "\(dimCode)⏳ \(message)\(reset)\n"
    }

    // MARK: - Rate Limit Event

    /// 渲染速率限制事件警告。
    ///
    /// Codex 风格：`warning: rate limit warning (75% utilized, resets in 2h)` 黄色加粗
    ///
    /// - Parameters:
    ///   - rateLimitInfo: 速率限制信息
    ///   - isTTY: 是否为 TTY 输出
    ///   - colorProfile: 终端颜色能力
    /// - Returns: 格式化的速率限制警告字符串（含换行），nil info 时返回 nil
    static func renderRateLimit(
        rateLimitInfo: SDKMessage.RateLimitInfo?,
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        colorProfile: TerminalColorProfile = .detect()
    ) -> String? {
        guard let info = rateLimitInfo else { return nil }

        var parts: [String] = []

        // 状态描述
        if let status = info.status {
            switch status {
            case .allowed:
                parts.append("rate limit: OK")
            case .allowedWarning:
                parts.append("⚠️ rate limit warning")
            case .rejected:
                parts.append("🚫 rate limit exceeded")
            }
        }

        // 利用率
        if let utilization = info.utilization {
            let pct = Int(utilization * 100)
            parts.append("\(pct)% utilized")
        }

        // 限制类型
        if let limitType = info.rateLimitType {
            parts.append("(\(formatRateLimitType(limitType)))")
        }

        // 重置时间
        if let resetsAt = info.resetsAt {
            let resetsDate = Date(timeIntervalSince1970: TimeInterval(resetsAt))
            let remaining = max(0, Int(resetsDate.timeIntervalSinceNow / 60))
            if remaining > 0 {
                parts.append("resets in \(formatMinutes(remaining))")
            }
        }

        // Overage 标记
        if info.isUsingOverage == true {
            parts.append("(overage)")
        }

        let message = parts.joined(separator: ", ")
        guard !message.isEmpty else { return nil }

        guard isTTY else {
            return "\(message)\n"
        }

        let warningColor = warningColorCode(for: colorProfile)
        let boldCode = bold
        return "\(boldCode)\(warningColor)warning:\(reset) \(warningColor)\(message)\(reset)\n"
    }

    // MARK: - Task Notification Event

    /// 渲染任务完成通知。
    ///
    /// Codex 风格：`📋 task completed (12 tools, 45s)` dimmed 样式
    ///
    /// - Parameters:
    ///   - taskInfo: 任务通知信息
    ///   - isTTY: 是否为 TTY 输出
    ///   - colorProfile: 终端颜色能力
    /// - Returns: 格式化的任务通知字符串（含换行），nil info 时返回 nil
    static func renderTaskNotification(
        taskInfo: SDKMessage.TaskNotificationInfo?,
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        colorProfile: TerminalColorProfile = .detect()
    ) -> String? {
        guard let info = taskInfo else { return nil }

        var parts: [String] = []
        let statusIcon: String
        if let status = info.status {
            switch status {
            case .completed:
                statusIcon = "✓"
                parts.append("completed")
            case .failed:
                statusIcon = "✗"
                parts.append("failed")
            case .stopped:
                statusIcon = "■"
                parts.append("stopped")
            }
        } else {
            statusIcon = "📋"
        }

        // 使用统计
        if let usage = info.usage {
            if usage.toolUses > 0 {
                parts.append("\(usage.toolUses) tools")
            }
            if usage.durationMs > 0 {
                parts.append(formatDurationMs(usage.durationMs))
            }
            if usage.totalTokens > 0 {
                parts.append(formatTokenCount(usage.totalTokens) + " tokens")
            }
        }

        // 摘要
        var summary: String?
        if let s = info.summary, !s.isEmpty {
            summary = s
        }

        let detailStr = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        let summaryStr = summary.map { " — \($0)" } ?? ""

        guard isTTY else {
            return "\(statusIcon) task\(detailStr)\(summaryStr)\n"
        }

        let dimCode = self.dimCode(for: colorProfile)
        return "\(dimCode)\(statusIcon) task\(detailStr)\(summaryStr)\(reset)\n"
    }

    // MARK: - Helper Methods

    /// 格式化 token 数量为人类可读格式。
    ///
    /// - < 1000 → "345"
    /// - ≥ 1000 → "1.2K", "15K"
    /// - ≥ 1_000_000 → "1.2M"
    static func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let m = Double(count) / 1_000_000.0
            return String(format: "%.1fM", m)
        }
        if count >= 1000 {
            let k = Double(count) / 1000.0
            if k < 10 {
                return String(format: "%.1fK", k)
            }
            return "\(Int(k.rounded()))K"
        }
        return "\(count)"
    }

    /// 格式化毫秒为紧凑的耗时字符串。
    static func formatDurationMs(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        }
        let seconds = Double(ms) / 1000.0
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%dm%02ds", mins, secs)
    }

    /// 格式化分钟为人类可读的时长。
    private static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(mins)m"
    }

    /// 格式化速率限制类型为人类可读描述。
    private static func formatRateLimitType(_ type: SDKMessage.RateLimitInfo.RateLimitType) -> String {
        switch type {
        case .fiveHour: return "5h window"
        case .sevenDay: return "7d window"
        case .sevenDayOpus: return "7d opus"
        case .sevenDaySonnet: return "7d sonnet"
        case .overage: return "overage"
        }
    }

    /// 获取 dim 样式码（按 profile 降级）。
    private static func dimCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor, .ansi256, .ansi16:
            return dim
        case .unknown:
            return ""
        }
    }

    /// 获取警告颜色码（黄色系）。
    private static func warningColorCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor:
            return "\u{1B}[38;2;234;179;8m"   // amber-yellow
        case .ansi256:
            return "\u{1B}[38;5;220m"          // yellow-orange
        case .ansi16:
            return "\u{1B}[33m"                // standard yellow
        case .unknown:
            return ""
        }
    }
}
