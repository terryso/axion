import Foundation

/// 追踪会话期间的工具使用情况，用于 /status 和退出摘要展示。
///
/// Codex-inspired: Codex 的 session analytics 展示工具使用频率分布，
/// 让用户直观了解 agent 在做什么。Axion 追踪每个工具的调用次数，
/// 并在 /status 和 exit summary 中渲染可视化的工具使用排行。
///
/// 纯值类型，无 I/O，通过注入闭包实现可测试性。
struct ToolUsageTracker: Sendable {

    /// 单个工具的使用记录。
    struct ToolRecord: Sendable, Equatable {
        let toolName: String
        let count: Int
    }

    /// 工具名 → 调用次数映射。
    private(set) var counts: [String: Int] = [:]

    /// 已记录的总工具调用次数。
    var totalCount: Int {
        counts.values.reduce(0, +)
    }

    /// 已记录的不同工具种类数。
    var uniqueToolCount: Int {
        counts.count
    }

    // MARK: - Recording

    /// 记录一次工具调用。
    mutating func record(toolName: String) {
        counts[toolName, default: 0] += 1
    }

    /// 重置所有记录。
    mutating func reset() {
        counts.removeAll()
    }

    // MARK: - Query

    /// 按调用次数降序排列的工具记录，最多返回 `limit` 个。
    func topTools(limit: Int = 5) -> [ToolRecord] {
        counts
            .map { ToolRecord(toolName: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Rendering

    /// 渲染工具使用排行 — 紧凑单行格式，适合嵌入 turn summary 或 status 卡片。
    ///
    /// TTY 格式: `🔧 12 tools · Bash 5 · Edit 4 · Read 3`
    /// 非 TTY:    `[tools: 12 calls (Bash 5, Edit 4, Read 3)]`
    ///
    /// - Parameters:
    ///   - topN: 显示前 N 个工具（默认 5）
    ///   - isTTY: 是否连接到 TTY
    ///   - profile: 终端颜色 profile
    /// - Returns: 格式化的工具排行字符串
    func renderCompact(
        topN: Int = 5,
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        profile: TerminalColorProfile = .detect()
    ) -> String {
        let total = totalCount
        guard total > 0 else {
            return isTTY ? "🔧 0 tools" : "[tools: 0]"
        }

        let tools = topTools(limit: topN)
        let reset = "\u{1B}[0m"
        let toolStr = total == 1 ? "1 tool" : "\(total) tools"

        if isTTY {
            let toolColor = toolLabelColor(for: profile)
            let dimColor = dimCode(for: profile)
            let parts = tools.map { record in
                "\(toolColor)\(record.toolName)\(reset) \(dimColor)\(record.count)\(reset)"
            }
            return "🔧 \(toolStr) · " + parts.joined(separator: " · ")
        } else {
            let parts = tools.map { "\($0.toolName) \($0.count)" }
            return "[tools: \(total) calls (\(parts.joined(separator: ", ")))]"
        }
    }

    /// 渲染工具使用排行 — 多行格式，适合 /status 仪表板。
    ///
    /// 每个工具一行，带可视化频率条和计数：
    /// ```
    /// 🔧 工具使用 (12 calls)
    ///   Bash  ████████████████  5
    ///   Edit   ████████████     4
    ///   Read   ████████         3
    /// ```
    ///
    /// - Parameters:
    ///   - maxBarWidth: 频率条最大宽度（字符数，默认 16）
    ///   - isTTY: 是否连接到 TTY
    ///   - profile: 终端颜色 profile
    /// - Returns: 格式化的工具排行字符串，无工具调用时返回 nil
    func renderDetailed(
        maxBarWidth: Int = 16,
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        profile: TerminalColorProfile = .detect()
    ) -> String? {
        let total = totalCount
        guard total > 0 else { return nil }

        let tools = topTools(limit: 8)
        let maxCount = tools.first?.count ?? 1
        let reset = "\u{1B}[0m"
        let callStr = total == 1 ? "1 call" : "\(total) calls"

        var lines: [String] = []

        if isTTY {
            let headerColor = sectionHeaderColor(for: profile)
            let barColor = barColor(for: profile)
            let countColor = dimCode(for: profile)
            let nameColor = toolLabelColor(for: profile)

            lines.append("\(headerColor)🔧 工具使用 (\(callStr))\(reset)")

            // 计算工具名最大宽度用于对齐
            let maxNameWidth = tools.map(\.toolName.count).max() ?? 0

            for record in tools {
                let barLen = max(1, Int(Double(record.count) / Double(maxCount) * Double(maxBarWidth)))
                let bar = String(repeating: "█", count: barLen)
                let padding = String(repeating: " ", count: maxBarWidth - barLen)
                let namePadding = String(repeating: " ", count: maxNameWidth - record.toolName.count)
                lines.append(
                    "  \(nameColor)\(record.toolName)\(reset)\(namePadding)  " +
                    "\(barColor)\(bar)\(reset)\(padding)  " +
                    "\(countColor)\(record.count)\(reset)"
                )
            }
        } else {
            lines.append("[tools: \(callStr)]")
            for record in tools {
                let barLen = max(1, Int(Double(record.count) / Double(maxCount) * Double(maxBarWidth)))
                let bar = String(repeating: "#", count: barLen)
                lines.append("  \(record.toolName) \(bar) \(record.count)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - ANSI Color Helpers

    private func toolLabelColor(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;139;157;207m"   // 薰衣草紫
        case .ansi256: return "\u{1B}[38;5;183m"
        case .ansi16: return "\u{1B}[36m"                     // cyan
        case .unknown: return ""
        }
    }

    private func dimCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;148;163;184m"
        case .ansi256: return "\u{1B}[38;5;145m"
        case .ansi16: return "\u{1B}[37m"
        case .unknown: return ""
        }
    }

    private func sectionHeaderColor(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;148;163;184m\u{1B}[4m"   // dim + underline
        case .ansi256: return "\u{1B}[38;5;145m\u{1B}[4m"
        case .ansi16: return "\u{1B}[37m\u{1B}[4m"
        case .unknown: return ""
        }
    }

    private func barColor(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;99;179;237m"   // 天蓝色
        case .ansi256: return "\u{1B}[38;5;117m"
        case .ansi16: return "\u{1B}[36m"
        case .unknown: return ""
        }
    }
}
