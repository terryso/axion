import Foundation

// MARK: - AC7 Enhanced: 审批差异预览

/// 审批差异预览格式化器 — 在 Edit/Write 工具审批时显示 color-coded 的实际变更内容。
///
/// 替代原有的简单行数摘要（"文件: -3 行 / +5 行"），提供可视化的差异预览：
/// - Edit 工具：old_string → new_string 的逐行对比，红色删除 + 绿色新增
/// - Write 工具：新文件内容的前 N 行预览
/// - 最多显示 `maxPreviewLines` 行，超出截断并显示提示
///
/// 设计原则：
/// - 纯函数 + static 方法，无状态，无 I/O
/// - 支持所有 TerminalColorProfile 降级
/// - 非 TTY 环境下返回 plain-text 摘要（与原 renderDiffSummary 兼容）
/// - 直接注入 ApprovalRenderer，不需要修改 PermissionHandler 流程
struct ApprovalDiffPreview: Sendable {

    // MARK: - Types

    /// 预览配置
    struct Config: Sendable, Equatable {
        /// 最大预览行数（差异行数，不含头/尾）
        var maxPreviewLines: Int
        /// 是否为 TTY
        var isTTY: Bool
        /// 终端颜色 profile
        var profile: TerminalColorProfile

        init(
            maxPreviewLines: Int = 15,
            isTTY: Bool = isatty(STDERR_FILENO) != 0,
            profile: TerminalColorProfile = .detect()
        ) {
            self.maxPreviewLines = maxPreviewLines
            self.isTTY = isTTY
            self.profile = isTTY ? profile : .unknown
        }
    }

    // MARK: - Public API

    /// 生成 Edit 工具的差异预览。
    ///
    /// 将 old_string 和 new_string 逐行对比，生成 unified diff 风格的预览：
    /// ```
    ///   Sources/Foo.swift: -3 行 / +5 行
    ///   ── Changes ──
    ///   - removed line 1
    ///   - removed line 2
    ///   + added line 1
    ///   + added line 2
    ///   + added line 3
    ///   ⋮ 还有 8 行差异未显示
    /// ```
    ///
    /// - Parameters:
    ///   - filePath: 文件路径
    ///   - oldString: 原始文本
    ///   - newString: 新文本
    ///   - config: 预览配置
    /// - Returns: 格式化的差异预览字符串，或 nil（无内容可预览）
    static func renderEditPreview(
        filePath: String,
        oldString: String,
        newString: String,
        config: Config = Config()
    ) -> String? {
        let oldLines = oldString.components(separatedBy: "\n")
        let newLines = newString.components(separatedBy: "\n")

        // 去掉末尾空行（由 trailing newline 产生的空元素）
        let trimmedOld = trimTrailingEmpty(oldLines)
        let trimmedNew = trimTrailingEmpty(newLines)

        // 计算差异行
        let diffLines = computeSimpleDiff(
            oldLines: trimmedOld,
            newLines: trimmedNew
        )

        guard !diffLines.isEmpty else {
            // 完全相同的字符串 → 无变化，返回简单的行数摘要
            if trimmedOld.count == trimmedNew.count {
                return "  \(filePath): 替换 \(trimmedOld.count) 行\n"
            }
            let removed = max(0, trimmedOld.count - trimmedNew.count)
            let added = max(0, trimmedNew.count - trimmedOld.count)
            return renderEditSummaryLine(
                filePath: filePath,
                removed: removed,
                added: added
            )
        }

        // 从 diff 行中统计实际的 removed/added 行数
        let removed = diffLines.filter { $0.kind == .removed }.count
        let added = diffLines.filter { $0.kind == .added }.count

        // 统计摘要
        let summary = renderEditSummaryLine(
            filePath: filePath,
            removed: removed,
            added: added
        )

        let diffOutput = renderDiffLines(
            diffLines: diffLines,
            config: config
        )

        return summary + diffOutput
    }

    /// 生成 Write 工具的内容预览。
    ///
    /// 显示新文件内容的前 N 行（绿色高亮）：
    /// ```
    ///   Sources/Foo.swift: 42 行（新文件）
    ///   ── Preview ──
    ///   + import Foundation
    ///   + import OpenAgentSDK
    ///   + ...
    ///   ⋮ 还有 37 行未显示
    /// ```
    ///
    /// - Parameters:
    ///   - filePath: 文件路径
    ///   - content: 写入内容
    ///   - config: 预览配置
    /// - Returns: 格式化的内容预览字符串，或 nil（无内容）
    static func renderWritePreview(
        filePath: String,
        content: String,
        config: Config = Config()
    ) -> String? {
        guard !content.isEmpty else { return nil }

        let lines = content.components(separatedBy: "\n")
        let trimmed = trimTrailingEmpty(lines)
        let totalLines = trimmed.count

        // 统计摘要
        let summary: String
        if totalLines == 1 {
            summary = "  \(filePath): 1 行"
        } else {
            summary = "  \(filePath): \(totalLines) 行"
        }

        // 预览行（所有行都标记为新增）
        let previewLines = trimmed.map { DiffLine(kind: .added, text: $0) }
        let diffOutput = renderDiffLines(
            diffLines: previewLines,
            config: config
        )

        return summary + diffOutput
    }

    // MARK: - Diff Line Model

    private enum DiffKind: Sendable {
        case added
        case removed
        case context
    }

    private struct DiffLine: Sendable {
        let kind: DiffKind
        let text: String
    }

    // MARK: - Summary Rendering

    /// 渲染 Edit 统计摘要行
    private static func renderEditSummaryLine(
        filePath: String,
        removed: Int,
        added: Int
    ) -> String {
        if removed > 0 && added > 0 {
            return "  \(filePath): -\(removed) 行 / +\(added) 行\n"
        } else if removed > 0 {
            return "  \(filePath): -\(removed) 行\n"
        } else if added > 0 {
            return "  \(filePath): +\(added) 行\n"
        } else {
            return "  \(filePath): 替换 \(removed) 行\n"
        }
    }

    // MARK: - Simple Diff Algorithm

    /// 简单的逐行差异算法。
    ///
    /// 使用 LCS（最长公共子序列）风格的简化实现：
    /// 1. 先找 common prefix（行首匹配）
    /// 2. 再找 common suffix（行尾匹配）
    /// 3. 中间部分全部标记为 removed + added
    ///
    /// 这比完整的 Myers diff 简单得多，但对审批预览已经足够好 —
    /// 用户需要的是"大概改了什么"而非精确的字符级 diff。
    private static func computeSimpleDiff(
        oldLines: [String],
        newLines: [String]
    ) -> [DiffLine] {
        // Common prefix
        var prefixCount = 0
        let minCount = min(oldLines.count, newLines.count)
        while prefixCount < minCount && oldLines[prefixCount] == newLines[prefixCount] {
            prefixCount += 1
        }

        // Common suffix (only look beyond prefix)
        var suffixCount = 0
        let oldRemaining = oldLines.count - prefixCount
        let newRemaining = newLines.count - prefixCount
        let maxSuffix = min(oldRemaining, newRemaining)
        while suffixCount < maxSuffix &&
                oldLines[oldLines.count - 1 - suffixCount] == newLines[newLines.count - 1 - suffixCount] {
            suffixCount += 1
        }

        var result: [DiffLine] = []

        // Context prefix (unchanged at top)
        for i in 0..<prefixCount {
            result.append(DiffLine(kind: .context, text: oldLines[i]))
        }

        // Removed lines (middle of old)
        let oldMiddleStart = prefixCount
        let oldMiddleEnd = oldLines.count - suffixCount
        for i in oldMiddleStart..<oldMiddleEnd {
            result.append(DiffLine(kind: .removed, text: oldLines[i]))
        }

        // Added lines (middle of new)
        let newMiddleStart = prefixCount
        let newMiddleEnd = newLines.count - suffixCount
        for i in newMiddleStart..<newMiddleEnd {
            result.append(DiffLine(kind: .added, text: newLines[i]))
        }

        // Context suffix (unchanged at bottom)
        for i in (newLines.count - suffixCount)..<newLines.count {
            result.append(DiffLine(kind: .context, text: newLines[i]))
        }

        // Filter out pure context-only results (no actual changes)
        let hasChanges = result.contains { $0.kind != .context }
        guard hasChanges else { return [] }

        return result
    }

    // MARK: - Diff Rendering

    /// 渲染差异行列表为终端输出。
    ///
    /// 使用 DiffFormatter 风格的 ANSI 颜色编码：
    /// - 绿色：新增行（+ 前缀）
    /// - 红色：删除行（- 前缀）
    /// - 暗灰色：上下文行（空格前缀）
    /// - 截断提示：超出 maxPreviewLines 时显示
    private static func renderDiffLines(
        diffLines: [DiffLine],
        config: Config
    ) -> String {
        let maxLines = config.maxPreviewLines
        let profile = config.profile
        let isTTY = config.isTTY

        var output = ""
        let reset = "\u{1B}[0m"
        let separator: String

        if isTTY {
            let dim = Self.dimCode(for: profile)
            separator = "\(dim)  ── Changes ──\(reset)\n"
        } else {
            separator = "  Changes:\n"
        }
        output += separator

        // 计算实际变化的行数（不含 context）
        let changedLines = diffLines.filter { $0.kind != .context }
        var shownCount = 0
        var truncated = false

        for line in diffLines {
            // Context 行不计入 maxLines 限制
            if line.kind == .context {
                if isTTY {
                    let dim = Self.dimCode(for: profile)
                    // 截断过长的上下文行
                    let truncated_text = Self.truncateLine(line.text, maxChars: 80)
                    output += "\(dim)  \(truncated_text)\(reset)\n"
                } else {
                    output += "  \(line.text)\n"
                }
                continue
            }

            if shownCount >= maxLines {
                truncated = true
                break
            }

            switch line.kind {
            case .added:
                if isTTY {
                    let green = Self.greenCode(for: profile)
                    let text = Self.truncateLine(line.text, maxChars: 78)
                    output += "\(green)  +\(text)\(reset)\n"
                } else {
                    output += "  +\(line.text)\n"
                }
            case .removed:
                if isTTY {
                    let red = Self.redCode(for: profile)
                    let text = Self.truncateLine(line.text, maxChars: 78)
                    output += "\(red)  -\(text)\(reset)\n"
                } else {
                    output += "  -\(line.text)\n"
                }
            case .context:
                break // handled above
            }
            shownCount += 1
        }

        if truncated {
            let remaining = changedLines.count - shownCount
            if isTTY {
                let dim = Self.dimCode(for: profile)
                let yellow = Self.yellowCode(for: profile)
                output += "\(yellow)  ⋮ \(dim)还有 \(remaining) 行差异未显示\(reset)\n"
            } else {
                output += "  ... 还有 \(remaining) 行差异未显示\n"
            }
        }

        return output
    }

    // MARK: - Helpers

    /// 去掉末尾空行
    private static func trimTrailingEmpty(_ lines: [String]) -> [String] {
        var result = lines
        while result.last == "" {
            result.removeLast()
        }
        return result
    }

    /// 截断过长行
    private static func truncateLine(_ line: String, maxChars: Int) -> String {
        guard line.count > maxChars else { return line }
        return String(line.prefix(maxChars - 1)) + "…"
    }

    // MARK: - ANSI Color Helpers (reuse DiffFormatter palette)

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

    private static func yellowCode(for profile: TerminalColorProfile) -> String {
        switch profile {
        case .trueColor: return "\u{1B}[38;2;250;204;21m"
        case .ansi256: return "\u{1B}[38;5;226m"
        case .ansi16: return "\u{1B}[33m"
        case .unknown: return ""
        }
    }
}
