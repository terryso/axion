
// MARK: - AC1: 审批决策

/// 审批决策枚举 — 定义用户对工具执行权限的选择。
///
/// 每个决策携带快捷键和显示标签，用于 REPL 审批渲染。
/// 纯 enum，零外部依赖。
enum ApprovalDecision: Equatable, Sendable {
    /// 仅本次允许执行
    case once
    /// 本会话内允许相同命令
    case session
    /// 允许匹配前缀的所有命令（携带前缀预览文本）
    case prefix(String)
    /// 拒绝执行（含取消 — 两者功能相同，统一为拒绝）
    case decline

    // MARK: - 快捷键

    /// 决策对应的快捷键字符
    var shortcut: Character {
        switch self {
        case .once:    return "y"
        case .session: return "a"
        case .prefix:  return "p"
        case .decline: return "d"
        }
    }

    /// 决策对应的显示标签
    var label: String {
        switch self {
        case .once:              return "仅本次"
        case .session:           return "本会话"
        case .prefix(let text):  return "前缀: \(text)"
        case .decline:           return "拒绝"
        }
    }

    /// 快捷键的显示文本（用于渲染）
    var shortcutDisplay: String {
        return String(shortcut)
    }
}

// MARK: - AC1/AC2: 审批选项

/// 审批选项 — 一个决策 + 快捷键 + 标签的组合。
///
/// 根据工具类型动态生成可用选项列表。
/// 纯 struct，零外部依赖。
struct ApprovalOption: Equatable, Sendable {
    let decision: ApprovalDecision
    let shortcut: Character
    let label: String

    // MARK: - 动态选项生成 (AC2)

    /// 根据工具类型和操作内容动态生成可用选项列表。
    ///
    /// - Bash 命令 → 4 个选项（含 prefix，显示前缀预览）
    /// - Write/Edit → once/session/decline（无 prefix）
    /// - 其他非只读工具 → once/session/decline
    /// - 只读工具 → 空列表（直接放行，不弹审批）
    ///
    /// - Parameters:
    ///   - toolName: 工具名称（"Bash", "Write", "Edit" 等）
    ///   - input: 工具输入参数字典（用于提取命令内容生成前缀预览）
    /// - Returns: 可用的审批选项列表
    static func allOptions(toolName: String, input: [String: Any]? = nil) -> [ApprovalOption] {
        let once = ApprovalOption(decision: .once, shortcut: "y", label: "仅本次")
        let session = ApprovalOption(decision: .session, shortcut: "a", label: "本会话")
        let decline = ApprovalOption(decision: .decline, shortcut: "d", label: "拒绝")

        if toolName == "Bash" {
            // Bash 命令 → 包含 prefix 选项（仅当 ≥ 2 tokens 时）
            let command = (input?["command"] as? String) ?? ""
            let tokens = Self.tokenize(command)
            if tokens.count >= 2 {
                let preview = Self.prefixPreview(for: command)
                let prefix = ApprovalOption(
                    decision: .prefix(preview),
                    shortcut: "p",
                    label: "前缀: \(preview)"
                )
                return [once, session, prefix, decline]
            }
            // 单 token / 空命令 → prefix 等同 session，不单独显示
            return [once, session, decline]
        }

        // Write/Edit 及其他非只读工具 → 无 prefix 选项
        return [once, session, decline]
    }

    // MARK: - 前缀预览 (AC4)

    /// 生成前缀允许的预览文本。
    ///
    /// 将命令按空格拆分为 tokens，取前 N 个 token 作为前缀。
    /// 单 token 命令不显示 prefix 选项（等同于精确匹配）。
    ///
    /// - Parameter command: 完整命令字符串
    /// - Returns: 前缀预览文本（如 "git commit*"）
    /// 前缀预览最大长度（超出截断显示 `…*`）
    private static let prefixPreviewMaxLength = 40

    static func prefixPreview(for command: String) -> String {
        let tokens = Self.tokenize(command)
        guard !tokens.isEmpty else {
            return ""  // 空命令无前缀预览
        }
        guard tokens.count >= 2 else {
            return truncateForPreview(command) + "*"  // 单 token：等同精确匹配
        }
        // 取前 2 个 token 作为前缀
        let prefix = tokens.prefix(2).joined(separator: " ")
        return truncateForPreview(prefix) + "*"
    }

    /// 截断过长的预览文本（保留末尾 `…` 标记）。
    private static func truncateForPreview(_ text: String) -> String {
        guard text.count > prefixPreviewMaxLength else { return text }
        return String(text.prefix(prefixPreviewMaxLength)) + "…"
    }

    /// 将命令字符串按 shell 风格拆分为 tokens。
    ///
    /// 识别引号内的空格不拆分：
    /// `git commit -m "fix: bug"` → ["git", "commit", "-m", "fix: bug"]
    static func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote = false
        var quoteChar: Character = " "
        var prevChar: Character?

        for char in command {
            if prevChar == "\\" {
                // 反斜杠转义：保留当前字符，清除转义标记
                current.append(char)
                prevChar = nil
                continue
            }
            if inQuote {
                if char == quoteChar {
                    inQuote = false
                } else if char == "\\" {
                    prevChar = char  // 标记转义，下个字符保留
                } else {
                    current.append(char)
                }
            } else {
                switch char {
                case "\"", "'":
                    inQuote = true
                    quoteChar = char
                case " ", "\t":
                    if !current.isEmpty {
                        tokens.append(current)
                        current = ""
                    }
                case "\\":
                    prevChar = char  // 标记转义
                default:
                    current.append(char)
                }
            }
            if char != "\\" || prevChar == nil {
                prevChar = nil
            }
        }
        // 末尾反斜杠作为字面字符保留
        if prevChar == "\\" {
            current.append("\\")
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
