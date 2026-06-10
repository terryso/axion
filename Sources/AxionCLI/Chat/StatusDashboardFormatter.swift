import Foundation

/// Codex-inspired rich session status dashboard formatter.
///
/// Renders a comprehensive /status card with visual progress bars,
/// session statistics, and color-coded metrics. Inspired by Codex's
/// `/status` TUI panel which shows rate limits, progress bars, and
/// usage summaries in a structured dashboard layout.
///
/// Design principles:
/// - Pure functions (static methods), no state, no I/O
/// - Full TerminalColorProfile degradation chain
/// - Non-TTY fallback to structured plain text
/// - Reuses existing helpers (BannerRenderer.formatTokenCount, ContextManager)
struct StatusDashboardFormatter {

    // MARK: - ANSI Constants

    private static let reset = "\u{1B}[0m"
    private static let bold = "\u{1B}[1m"
    private static let dim = "\u{1B}[2m"

    // MARK: - Progress Bar

    /// Context usage progress bar segment count.
    private static let progressBarSegments = 20
    private static let progressFilled = "█"
    private static let progressEmpty = "░"

    // MARK: - Public API

    /// Session statistics needed for the dashboard.
    struct SessionStats: Sendable {
        /// Model name (e.g. "claude-sonnet-4-20250514").
        let model: String
        /// Permission mode display name.
        let permissionMode: String
        /// Session ID (first 8 chars shown).
        let sessionId: String
        /// Session start time (for elapsed calculation).
        let sessionStartTime: ContinuousClock.Instant
        /// Total turns completed.
        let turnCount: Int
        /// Total tools invoked across all turns.
        let totalToolsUsed: Int
        /// Current context token count.
        let contextTokens: Int
        /// Maximum context window size.
        let contextWindow: Int
        /// Cumulative session token usage.
        let usage: TokenUsageEstimate
        /// Estimated session cost string (e.g. "$0.05").
        let estimatedCost: String?
        /// Working directory.
        let cwd: String
        /// Tool usage tracker for per-tool breakdown (Codex-inspired analytics).
        let toolUsage: ToolUsageTracker?
    }

    /// Lightweight token usage estimate (no SDK dependency).
    struct TokenUsageEstimate: Sendable {
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let totalTokens: Int
    }

    /// Formats a rich session status dashboard.
    ///
    /// TTY output includes ANSI colors, visual progress bar, and structured layout.
    /// Non-TTY output uses plain text with structured labels.
    ///
    /// - Parameters:
    ///   - stats: Session statistics to display
    ///   - isTTY: Whether output goes to a TTY
    ///   - profile: Terminal color profile
    /// - Returns: Formatted dashboard string (trailing newline)
    static func format(
        stats: SessionStats,
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        profile: TerminalColorProfile = .detect()
    ) -> String {
        let now = ContinuousClock.now
        let elapsed = now - stats.sessionStartTime
        let elapsedStr = formatElapsedDuration(elapsed)

        let contextPct: Double? = stats.contextWindow > 0
            ? min(Double(stats.contextTokens) / Double(stats.contextWindow), 1.0)
            : nil

        guard isTTY else {
            return formatPlain(
                stats: stats,
                elapsedStr: elapsedStr,
                contextPct: contextPct
            )
        }

        return formatTTY(
            stats: stats,
            elapsedStr: elapsedStr,
            contextPct: contextPct,
            profile: profile
        )
    }

    // MARK: - TTY Rendering

    private static func formatTTY(
        stats: SessionStats,
        elapsedStr: String,
        contextPct: Double?,
        profile: TerminalColorProfile
    ) -> String {
        let dimC = dimCode(for: profile)
        let resetC = reset
        let boldC = bold
        let accentC = accentCode(for: profile)
        let valueC = valueCode(for: profile)
        let greenC = greenCode(for: profile)
        let yellowC = yellowCode(for: profile)

        var lines: [String] = []

        // Header line
        let shortId = String(stats.sessionId.prefix(8))
        lines.append("\(dimC)╭──────────────────────────────────────────╮\(resetC)")
        lines.append("\(dimC)│\(resetC) \(boldC)Axion Session\(resetC) \(dimC)·\(resetC) \(accentC)\(shortId)\(resetC) \(dimC)│\(resetC)")

        // Separator
        lines.append("\(dimC)├──────────────────────────────────────────┤\(resetC)")

        // Model + Permission
        lines.append(renderRow(
            label: "Model",
            value: stats.model,
            dimC: dimC, valueC: valueC, resetC: resetC
        ))
        lines.append(renderRow(
            label: "权限",
            value: stats.permissionMode,
            dimC: dimC, valueC: valueC, resetC: resetC
        ))

        // Session duration
        lines.append(renderRow(
            label: "Session",
            value: "\(elapsedStr) elapsed · \(stats.turnCount) turns · \(stats.totalToolsUsed) tools",
            dimC: dimC, valueC: valueC, resetC: resetC
        ))

        // Context usage with progress bar
        if let pct = contextPct {
            let bar = renderProgressBar(pct: pct, profile: profile)
            let pctStr = String(format: "%.0f%%", pct * 100)
            let contextStr = "\(formatTokenCount(stats.contextTokens))/\(formatTokenCount(stats.contextWindow)) \(bar) \(pctStr)"
            let contextValueColor = pct > 0.8 ? yellowC : valueC
            lines.append(renderRow(
                label: "Context",
                value: contextStr,
                dimC: dimC, valueC: contextValueColor, resetC: resetC,
                rawValue: true
            ))
        }

        // Token usage
        let tokenStr = "In \(formatTokenCount(stats.usage.inputTokens)) · Out \(formatTokenCount(stats.usage.outputTokens))"
            + (stats.usage.cacheReadTokens > 0 ? " · Cache \(formatTokenCount(stats.usage.cacheReadTokens))" : "")
            + " · Total \(formatTokenCount(stats.usage.totalTokens))"
        lines.append(renderRow(
            label: "Tokens",
            value: tokenStr,
            dimC: dimC, valueC: valueC, resetC: resetC
        ))

        // Cost
        if let cost = stats.estimatedCost {
            lines.append(renderRow(
                label: "Cost",
                value: cost,
                dimC: dimC, valueC: greenC, resetC: resetC
            ))
        }

        // Tool usage breakdown (Codex-inspired analytics)
        if let toolUsage = stats.toolUsage, toolUsage.totalCount > 0 {
            let tools = toolUsage.topTools(limit: 5)
            let toolParts = tools.map { "\($0.toolName) \($0.count)" }
            lines.append(renderRow(
                label: "Tools",
                value: toolParts.joined(separator: " · "),
                dimC: dimC, valueC: accentCode(for: profile), resetC: resetC
            ))
        }

        // Working directory
        lines.append(renderRow(
            label: "Dir",
            value: stats.cwd,
            dimC: dimC, valueC: dimC, resetC: resetC
        ))

        // Footer
        lines.append("\(dimC)╰──────────────────────────────────────────╯\(resetC)")

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Plain Text Rendering

    private static func formatPlain(
        stats: SessionStats,
        elapsedStr: String,
        contextPct: Double?
    ) -> String {
        let shortId = String(stats.sessionId.prefix(8))
        var lines: [String] = []

        lines.append("Session Status [\(shortId)]:")
        lines.append("  Model:    \(stats.model)")
        lines.append("  权限:     \(stats.permissionMode)")
        lines.append("  Duration: \(elapsedStr), \(stats.turnCount) turns, \(stats.totalToolsUsed) tools")

        if let pct = contextPct {
            let pctStr = String(format: "%.0f%%", pct * 100)
            lines.append("  Context:  \(formatTokenCount(stats.contextTokens))/\(formatTokenCount(stats.contextWindow)) (\(pctStr))")
        }

        lines.append("  Tokens:   In \(formatTokenCount(stats.usage.inputTokens)) / Out \(formatTokenCount(stats.usage.outputTokens)) / Total \(formatTokenCount(stats.usage.totalTokens))")

        if let cost = stats.estimatedCost {
            lines.append("  Cost:     \(cost)")
        }

        if let toolUsage = stats.toolUsage, toolUsage.totalCount > 0 {
            let tools = toolUsage.topTools(limit: 5)
            let toolParts = tools.map { "\($0.toolName) \($0.count)" }
            lines.append("  Tools:    \(toolParts.joined(separator: ", "))")
        }

        lines.append("  Dir:      \(stats.cwd)")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Row Rendering

    private static func renderRow(
        label: String,
        value: String,
        dimC: String,
        valueC: String,
        resetC: String,
        rawValue: Bool = false
    ) -> String {
        let labelPart = "\(dimC)│\(resetC) \(dimC)\(label):\(resetC)"
        let valuePart = rawValue ? value : "\(valueC)\(value)\(resetC)"
        let padding = String(repeating: " ", count: max(1, 10 - label.count))
        let endPad = String(repeating: " ", count: max(1, 41 - label.count - 3 - min(value.count, 40)))
        return "\(labelPart)\(padding)\(valuePart)\(endPad)\(dimC)│\(resetC)"
    }

    // MARK: - Progress Bar

    /// Renders a visual context usage progress bar.
    ///
    /// Color changes based on usage level:
    /// - < 50%: green
    /// - 50-80%: yellow
    /// - > 80%: red
    static func renderProgressBar(pct: Double, profile: TerminalColorProfile) -> String {
        var filled = Int((pct * Double(progressBarSegments)).rounded())
        filled = min(filled, progressBarSegments)
        let empty = progressBarSegments - filled

        let colorCode: String
        if pct > 0.8 {
            colorCode = redCode(for: profile)
        } else if pct > 0.5 {
            colorCode = yellowCode(for: profile)
        } else {
            colorCode = greenCode(for: profile)
        }

        let resetC = reset
        let dimC = dimCode(for: profile)

        return "\(colorCode)\(progressFilled.repeated(filled))\(resetC)\(dimC)\(progressEmpty.repeated(empty))\(resetC)"
    }

    // MARK: - Duration Formatting

    /// Formats a ContinuousClock.Duration as a compact human-readable string.
    static func formatElapsedDuration(_ duration: ContinuousClock.Duration) -> String {
        let totalSeconds = Int(duration.components.seconds)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes < 60 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        return "\(days)d \(remainingHours)h"
    }

    // MARK: - Token Formatting

    /// Formats token count as human-readable (e.g., "1.2K", "15K").
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

    // MARK: - ANSI Color Helpers

    private static func accentCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;129;140;248m"   // purple-blue
        case .ansi256: return "\u{1B}[38;5;111m"
        case .ansi16: return "\u{1B}[36m"
        case .unknown: return ""
        }
    }

    private static func valueCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;148;163;184m"   // gray-blue
        case .ansi256: return "\u{1B}[38;5;145m"
        case .ansi16: return "\u{1B}[37m"
        case .unknown: return ""
        }
    }

    private static func greenCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;76;175;80m"
        case .ansi256: return "\u{1B}[38;5;71m"
        case .ansi16: return "\u{1B}[32m"
        case .unknown: return ""
        }
    }

    private static func yellowCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;234;179;8m"
        case .ansi256: return "\u{1B}[38;5;220m"
        case .ansi16: return "\u{1B}[33m"
        case .unknown: return ""
        }
    }

    private static func redCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;244;67;54m"
        case .ansi256: return "\u{1B}[38;5;160m"
        case .ansi16: return "\u{1B}[31m"
        case .unknown: return ""
        }
    }

    private static func dimCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor, .ansi256, .ansi16:
            return dim
        case .unknown:
            return ""
        }
    }
}

// MARK: - String Extension

private extension String {
    func repeated(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
