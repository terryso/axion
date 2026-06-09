import Foundation

/// 键盘快捷键提示格式化器。
///
/// Codex-inspired: 在 TUI 中显示可发现的键盘快捷键提示行，
/// 帮助用户了解可用操作而无需阅读文档。
///
/// 与 Codex 的 bottom_pane 快捷键显示不同，Axion 使用行式输出
/// （非 TUI 框架），因此采用简洁的 `[key] description` 分组格式。
///
/// 两种输出模式：
/// - **单行模式** (renderInline)：适合启动横幅，一行紧凑展示核心快捷键
/// - **多行模式** (renderFull)：适合 /help 命令，分组展示全部快捷键
struct KeyHintsFormatter {

    // MARK: - KeyHint Definition

    /// 单个快捷键提示。
    struct KeyHint: Equatable {
        let key: String
        let description: String

        /// 渲染为 `[key] description` 格式（无颜色）。
        var plain: String {
            return "[\(key)] \(description)"
        }

        /// 渲染为 ANSI 彩色格式：键名高亮 + 描述暗色。
        ///
        /// - Parameters:
        ///   - profile: 终端颜色配置
        ///   - separator: 键名和描述之间的分隔符（默认空格）
        func colored(profile: TerminalColorProfile, separator: String = " ") -> String {
            let reset = "\u{1B}[0m"
            let keyColor: String
            let descColor: String
            switch profile {
            case .trueColor:
                keyColor = "\u{1B}[38;2;129;140;248m"    // 紫蓝（键名）
                descColor = "\u{1B}[38;2;148;163;184m"    // 灰蓝（描述）
            case .ansi256:
                keyColor = "\u{1B}[38;5;111m"             // 淡紫
                descColor = "\u{1B}[38;5;145m"            // 灰
            case .ansi16:
                keyColor = "\u{1B}[36m"                   // cyan
                descColor = "\u{1B}[37m"                  // white (dim)
            case .unknown:
                return "[\(key)] \(description)"
            }
            return "\(keyColor)[\(key)]\(reset)\(separator)\(descColor)\(description)\(reset)"
        }
    }

    // MARK: - Hint Groups

    /// 快捷键分组。
    struct HintGroup: Equatable {
        let label: String
        let hints: [KeyHint]
    }

    // MARK: - Core Hints

    /// 核心交互快捷键（启动横幅显示）。
    static let coreHints: [KeyHint] = [
        KeyHint(key: "Enter", description: "发送"),
        KeyHint(key: "Esc", description: "清空/取消"),
        KeyHint(key: "Ctrl+C", description: "中断"),
        KeyHint(key: "Ctrl+R", description: "搜索历史"),
        KeyHint(key: "/help", description: "命令列表"),
    ]

    /// 全部快捷键分组（/help 命令显示）。
    static let allGroups: [HintGroup] = [
        HintGroup(label: "输入", hints: [
            KeyHint(key: "Enter", description: "发送消息"),
            KeyHint(key: "Shift+Enter / \\", description: "续行"),
            KeyHint(key: "Esc", description: "清空输入"),
            KeyHint(key: "Ctrl+C", description: "中断/退出"),
        ]),
        HintGroup(label: "导航", hints: [
            KeyHint(key: "↑/↓", description: "历史导航"),
            KeyHint(key: "Ctrl+R", description: "搜索历史"),
            KeyHint(key: "Tab", description: "文件补全"),
        ]),
        HintGroup(label: "编辑", hints: [
            KeyHint(key: "Ctrl+A", description: "行首"),
            KeyHint(key: "Ctrl+E", description: "行尾"),
            KeyHint(key: "Ctrl+W", description: "删除单词"),
            KeyHint(key: "Ctrl+U", description: "删除整行"),
            KeyHint(key: "Ctrl+K", description: "删除至行尾"),
            KeyHint(key: "Ctrl+G", description: "外部编辑器"),
        ]),
        HintGroup(label: "队列", hints: [
            KeyHint(key: "Ctrl+Q", description: "入队消息"),
            KeyHint(key: "Ctrl+E", description: "编辑队首"),
        ]),
        HintGroup(label: "斜杠命令", hints: [
            KeyHint(key: "/help", description: "命令列表"),
            KeyHint(key: "/cost", description: "Token 用量"),
            KeyHint(key: "/compact", description: "压缩上下文"),
            KeyHint(key: "/diff", description: "Git diff"),
            KeyHint(key: "/status", description: "会话状态"),
            KeyHint(key: "/model", description: "切换模型"),
            KeyHint(key: "/clear", description: "清屏"),
            KeyHint(key: "/exit", description: "退出（/quit 同义）"),
        ]),
    ]

    // MARK: - Rendering

    /// 渲染单行快捷键提示（适合启动横幅）。
    ///
    /// 将核心快捷键渲染为一行紧凑格式，用 `·` 分隔。
    /// 非 TTY 环境返回纯文本，TTY 环境添加颜色。
    ///
    /// - Parameters:
    ///   - isTTY: 是否连接到 TTY
    ///   - colorProfile: 终端颜色配置
    ///   - hints: 自定义提示列表（默认使用 coreHints）
    /// - Returns: 单行快捷键提示字符串
    static func renderInline(
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        colorProfile: TerminalColorProfile = .detect(),
        hints: [KeyHint] = coreHints
    ) -> String {
        if isTTY {
            let parts = hints.map { $0.colored(profile: colorProfile) }
            return parts.joined(separator: "  ·  ")
        } else {
            let parts = hints.map { $0.plain }
            return parts.joined(separator: " · ")
        }
    }

    /// 渲染多行快捷键提示（适合 /help 命令）。
    ///
    /// 按分组渲染，每组一个标题行 + 提示列表。
    /// 组标题使用暗色下划线样式。
    ///
    /// - Parameters:
    ///   - isTTY: 是否连接到 TTY
    ///   - colorProfile: 终端颜色配置
    ///   - groups: 自定义分组列表（默认使用 allGroups）
    /// - Returns: 多行快捷键提示字符串
    static func renderFull(
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        colorProfile: TerminalColorProfile = .detect(),
        groups: [HintGroup] = allGroups
    ) -> String {
        let reset = "\u{1B}[0m"
        let dimColor: String
        let labelColor: String

        switch colorProfile {
        case .trueColor:
            dimColor = "\u{1B}[38;2;148;163;184m"
            labelColor = "\u{1B}[38;2;148;163;184m\u{1B}[4m"  // dim + underline
        case .ansi256:
            dimColor = "\u{1B}[38;5;145m"
            labelColor = "\u{1B}[38;5;145m\u{1B}[4m"
        case .ansi16:
            dimColor = "\u{1B}[37m"
            labelColor = "\u{1B}[37m\u{1B}[4m"
        case .unknown:
            dimColor = ""
            labelColor = ""
        }

        var lines: [String] = []

        for group in groups {
            // Group label with separator
            if isTTY {
                lines.append("\(labelColor)\(group.label)\(reset) \(dimColor)\(String(repeating: "─", count: max(1, 40 - group.label.count)))\(reset)")
            } else {
                lines.append("\(group.label) \(String(repeating: "-", count: max(1, 40 - group.label.count)))")
            }

            // Hints
            for hint in group.hints {
                if isTTY {
                    lines.append("  \(hint.colored(profile: colorProfile, separator: "  "))")
                } else {
                    lines.append("  \(hint.plain)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
