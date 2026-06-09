import Foundation

/// Git unified diff 彩色格式化器 — Codex 启发，增强 /diff 命令的可读性。
///
/// 将 `git diff` 的 unified diff 输出解析并渲染为带 ANSI 颜色的终端输出：
/// - 绿色：新增行（`+` 前缀）
/// - 红色：删除行（`-` 前缀）
/// - 青色/暗色：文件头（`diff --git`、`+++`、`---`）
/// - 暗灰色：hunk 头（`@@ ... @@`）
/// - 摘要统计（文件数、插入/删除行数）
///
/// 设计原则：
/// - 纯函数 + static 方法，无状态，无 I/O
/// - 支持所有 TerminalColorProfile 降级
/// - 非 TTY 环境下原样输出（无 ANSI 转义）
/// - 可配置最大行数，超出截断并显示提示
struct DiffFormatter: Sendable {

    // MARK: - Types

    /// 差异段类型
    private enum DiffSection {
        case fileHeader(String)      // diff --git a/... b/...
        case hunkHeader(String)      // @@ -l,s +l,s @@
        case addedLine(String)       // +text
        case removedLine(String)     // -text
        case contextLine(String)     //  text (unchanged)
        case oldFileHeader(String)   // --- a/...
        case newFileHeader(String)   // +++ b/...
        case binaryNote(String)      // Binary files differ
        case otherLine(String)       // anything else (mode changes, etc.)
    }

    /// 格式化配置
    struct Config: Sendable, Equatable {
        /// 最大显示行数（0 = 不限制）
        var maxLines: Int
        /// 上下文行数（hunk 中保留的 unchanged 行数）
        var contextLines: Int
        /// 是否为 TTY
        var isTTY: Bool
        /// 终端颜色 profile
        var profile: TerminalColorProfile

        init(
            maxLines: Int = 300,
            contextLines: Int = 3,
            isTTY: Bool = isatty(STDERR_FILENO) != 0,
            profile: TerminalColorProfile = .detect()
        ) {
            self.maxLines = maxLines
            self.contextLines = contextLines
            self.isTTY = isTTY
            self.profile = isTTY ? profile : .unknown
        }
    }

    // MARK: - Public API

    /// 格式化 git diff unified 输出为带颜色的终端输出。
    ///
    /// - Parameters:
    ///   - rawDiff: `git diff` 的原始输出
    ///   - config: 格式化配置
    /// - Returns: 带颜色（TTY）或原始文本（非 TTY）的格式化字符串
    static func format(_ rawDiff: String, config: Config = Config()) -> String {
        guard !rawDiff.isEmpty else { return "" }
        guard config.isTTY else { return rawDiff }

        let lines = rawDiff.components(separatedBy: "\n")
        let parsed = parseDiffLines(lines)
        let stats = computeStats(from: parsed)

        // 构建摘要头
        var output = renderStatsHeader(stats, profile: config.profile)

        // 渲染差异行（带行数限制）
        var lineCount = 0
        let maxLines = config.maxLines
        var truncated = false

        for section in parsed {
            let rendered = renderSection(section, profile: config.profile)
            // 计算渲染后的实际行数
            let renderedLines = rendered.components(separatedBy: "\n").count - (rendered.hasSuffix("\n") ? 1 : 0)

            if maxLines > 0 && lineCount + renderedLines > maxLines {
                truncated = true
                break
            }
            output += rendered
            lineCount += renderedLines
        }

        if truncated {
            output += renderTruncationNotice(
                remaining: parsed.count - lineCount,
                profile: config.profile
            )
        }

        return output
    }

    /// 从 git diff --stat 输出中提取摘要统计。
    ///
    /// 解析 `N files changed, M insertions(+), D deletions(-)` 格式。
    static func parseStatsFromStatOutput(_ statOutput: String) -> DiffStats {
        var stats = DiffStats()
        // 解析最后一行的统计摘要
        for line in statOutput.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("file") && trimmed.contains("changed") {
                // 提取数字
                let numbers = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .compactMap(Int.init)
                if numbers.count >= 1 { stats.fileCount = numbers[0] }
                if numbers.count >= 3 { stats.insertions = numbers[1]; stats.deletions = numbers[2] }
                else if numbers.count >= 2 { stats.insertions = numbers[1] }
                break
            }
        }
        return stats
    }

    // MARK: - Diff Stats

    struct DiffStats: Sendable, Equatable {
        var fileCount: Int = 0
        var insertions: Int = 0
        var deletions: Int = 0

        var isEmpty: Bool { fileCount == 0 && insertions == 0 && deletions == 0 }
    }

    // MARK: - Parsing

    /// 将原始 diff 行解析为语义化的段类型
    private static func parseDiffLines(_ lines: [String]) -> [DiffSection] {
        var sections: [DiffSection] = []

        for line in lines {
            if line.hasPrefix("diff --git") {
                sections.append(.fileHeader(line))
            } else if line.hasPrefix("--- ") {
                sections.append(.oldFileHeader(line))
            } else if line.hasPrefix("+++ ") {
                sections.append(.newFileHeader(line))
            } else if line.hasPrefix("@@") {
                sections.append(.hunkHeader(line))
            } else if line.hasPrefix("+") {
                sections.append(.addedLine(String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                sections.append(.removedLine(String(line.dropFirst())))
            } else if line.hasPrefix("Binary files") || line.hasPrefix("binary") {
                sections.append(.binaryNote(line))
            } else if line.hasPrefix(" ") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
                sections.append(.contextLine(String(line.dropFirst())))
            } else if !line.isEmpty {
                // mode changes, index lines, etc.
                sections.append(.otherLine(line))
            }
        }

        return sections
    }

    /// 从解析后的段中计算统计信息
    private static func computeStats(from sections: [DiffSection]) -> DiffStats {
        var stats = DiffStats()
        var inFile = false

        for section in sections {
            switch section {
            case .fileHeader:
                if inFile { /* already counting */ }
                stats.fileCount += 1
                inFile = true
            case .addedLine:
                stats.insertions += 1
            case .removedLine:
                stats.deletions += 1
            default:
                break
            }
        }

        return stats
    }

    // MARK: - Rendering

    /// 渲染统计摘要头
    private static func renderStatsHeader(_ stats: DiffStats, profile: TerminalColorProfile) -> String {
        if stats.isEmpty { return "" }

        let reset = "\u{1B}[0m"
        let dim = dimCode(for: profile)
        let green = greenCode(for: profile)
        let red = redCode(for: profile)
        let bold = "\u{1B}[1m"

        var parts: [String] = []
        parts.append("\(dim)\(stats.fileCount) file\(stats.fileCount == 1 ? "" : "s") changed\(reset)")

        if stats.insertions > 0 {
            parts.append("\(green)\(bold)+\(stats.insertions)\(reset)")
        }
        if stats.deletions > 0 {
            parts.append("\(red)\(bold)-\(stats.deletions)\(reset)")
        }

        return "\(dim)── \(parts.joined(separator: " \(dim)·\(reset) ")) ──\(reset)\n"
    }

    /// 渲染单个差异段
    private static func renderSection(_ section: DiffSection, profile: TerminalColorProfile) -> String {
        let reset = "\u{1B}[0m"

        switch section {
        case .fileHeader(let line):
            let cyan = cyanCode(for: profile)
            let bold = "\u{1B}[1m"
            return "\n\(cyan)\(bold)\(line)\(reset)\n"

        case .oldFileHeader(let line):
            let dim = dimCode(for: profile)
            return "\(dim)\(line)\(reset)\n"

        case .newFileHeader(let line):
            let dim = dimCode(for: profile)
            return "\(dim)\(line)\(reset)\n"

        case .hunkHeader(let line):
            let dim = dimCode(for: profile)
            return "\(dim)\(line)\(reset)\n"

        case .addedLine(let text):
            let green = greenCode(for: profile)
            return "\(green)+\(text)\(reset)\n"

        case .removedLine(let text):
            let red = redCode(for: profile)
            return "\(red)-\(text)\(reset)\n"

        case .contextLine(let text):
            let dim = dimCode(for: profile)
            return "\(dim) \(text)\(reset)\n"

        case .binaryNote(let line):
            let dim = dimCode(for: profile)
            return "\(dim)\(line)\(reset)\n"

        case .otherLine(let line):
            let dim = dimCode(for: profile)
            return "\(dim)\(line)\(reset)\n"
        }
    }

    /// 渲染截断提示
    private static func renderTruncationNotice(remaining: Int, profile: TerminalColorProfile) -> String {
        let dim = dimCode(for: profile)
        let reset = "\u{1B}[0m"
        let yellow = yellowCode(for: profile)
        return "\(yellow)⋮ \(dim)还有 \(remaining) 行差异未显示 — 使用 \(reset)\(yellow)git diff\(reset) \(dim)查看完整输出\(reset)\n"
    }

    // MARK: - ANSI Color Helpers

    private static func dimCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;120;120;140m"
        case .ansi256: return "\u{1B}[38;5;244m"
        case .ansi16: return "\u{1B}[2m"
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

    private static func redCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;244;67;54m"
        case .ansi256: return "\u{1B}[38;5;160m"
        case .ansi16: return "\u{1B}[31m"
        case .unknown: return ""
        }
    }

    private static func cyanCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;129;140;248m"  // 紫蓝（与标题 H1 一致）
        case .ansi256: return "\u{1B}[38;5;104m"
        case .ansi16: return "\u{1B}[36m"
        case .unknown: return ""
        }
    }

    private static func yellowCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;250;204;21m"
        case .ansi256: return "\u{1B}[38;5;226m"
        case .ansi16: return "\u{1B}[33m"
        case .unknown: return ""
        }
    }
}
