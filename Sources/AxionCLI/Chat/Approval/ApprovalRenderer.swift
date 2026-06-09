
// MARK: - AC5/AC7/AC9: 审批渲染器

/// 审批渲染器 — 纯函数，所有方法返回 String，零 I/O。
///
/// 复用 `ChatTheme` 的 `approvalColor` 和颜色降级链。
/// 选项列表格式：
/// ```
/// 🔴 Bash: swift test
///   [y] 仅本次  [a] 本会话  [p] 前缀: swift*  [d] 拒绝  [Esc] 取消
/// ```
struct ApprovalRenderer: Sendable {

    // MARK: - 审批提示渲染 (AC5)

    /// 渲染完整的审批提示 + 选项列表。
    ///
    /// - Parameters:
    ///   - toolName: 工具名称（"Bash", "Write", "Edit"）
    ///   - description: 操作描述（命令文本 / 文件路径）
    ///   - options: 可用审批选项列表
    ///   - theme: ChatTheme 用于颜色渲染
    /// - Returns: 格式化的审批提示字符串（以换行结尾）
    static func renderPrompt(
        toolName: String,
        description: String,
        options: [ApprovalOption],
        theme: ChatTheme
    ) -> String {
        // 第一行：红色圆点 + 工具名 + 操作描述
        let dot = theme.formatRoleDot(role: .warning)
        let header = "\(dot) \(toolName): \(description)"

        // 第二行：选项列表
        let optionsLine = renderOptionsList(options)

        return "\(header)\n\(optionsLine)\n"
    }

    /// 渲染选项列表（单行格式）。
    ///
    /// 格式：`  [y] 仅本次  [a] 本会话  [p] 前缀: git commit*  [d] 拒绝  [Esc] 取消`
    static func renderOptionsList(_ options: [ApprovalOption]) -> String {
        let parts = options.map { option in
            let shortcut = option.decision.shortcutDisplay
            return "[\(shortcut)] \(option.label)"
        }
        return "  " + parts.joined(separator: "  ")
    }

    // MARK: - Diff 摘要渲染 (AC7)

    /// 为 Write/Edit 工具生成变更摘要。
    ///
    /// 摘要不超过 5 行，包含：
    /// - Edit: 文件路径 + 新增行数 / 删除行数
    /// - Write: 文件路径 + 新文件行数
    /// - 其他工具: nil（不显示摘要）
    ///
    /// - Parameters:
    ///   - toolName: 工具名称
    ///   - input: 工具输入参数字典
    /// - Returns: 变更摘要字符串，或 nil（无需摘要）
    static func renderDiffSummary(toolName: String, input: [String: Any]) -> String? {
        switch toolName {
        case "Edit":
            return renderEditDiffSummary(input: input)
        case "Write":
            return renderWriteDiffSummary(input: input)
        default:
            return nil
        }
    }

    /// 渲染 Edit 工具的变更摘要。
    ///
    /// 统计 old_string 和 new_string 的行数差异。
    private static func renderEditDiffSummary(input: [String: Any]) -> String? {
        guard let oldString = input["old_string"] as? String,
              let newString = input["new_string"] as? String else {
            return nil
        }

        let filePath = input["file_path"] as? String ?? "文件"
        let oldLines = oldString.components(separatedBy: "\n").count
        let newLines = newString.components(separatedBy: "\n").count

        let removed = max(0, oldLines - newLines)
        let added = max(0, newLines - oldLines)

        if removed > 0 && added > 0 {
            return "  \(filePath): -\(removed) 行 / +\(added) 行"
        } else if removed > 0 {
            return "  \(filePath): -\(removed) 行"
        } else if added > 0 {
            return "  \(filePath): +\(added) 行"
        } else {
            return "  \(filePath): 替换 \(oldLines) 行"
        }
    }

    /// 渲染 Write 工具的变更摘要。
    ///
    /// 统计 content 的行数。
    private static func renderWriteDiffSummary(input: [String: Any]) -> String? {
        guard let content = input["content"] as? String else {
            return nil
        }

        let filePath = input["file_path"] as? String ?? "文件"
        let lineCount = content.components(separatedBy: "\n").count

        return "  \(filePath): \(lineCount) 行"
    }
}
