import Foundation

/// Codex-inspired 启动提示系统。
///
/// Codex 的 `tooltips.rs` 在每次启动时随机显示一条提示，帮助用户发现功能。
/// Axion 适配为两个层次：
/// 1. **首次运行**（无历史记录文件）：显示欢迎消息 + 核心功能快速入门
/// 2. **后续运行**：随机显示一条功能提示，帮助用户发现 Axion 的各种能力
///
/// 纯函数 struct，无 I/O。所有方法返回格式化字符串，
/// 由调用方决定输出目标和时机。
struct StartupTipProvider {

    // MARK: - First-run Detection

    /// 检测是否为首次运行（历史记录文件不存在）。
    ///
    /// 使用 CommandHistoryStore 的历史文件路径作为判断依据：
    /// - 文件不存在 → 首次运行
    /// - 文件存在 → 非首次运行
    ///
    /// - Parameter historyFilePath: 历史记录文件路径
    /// - Parameter fileExists: 文件存在检查闭包（可注入用于测试）
    /// - Returns: true 表示首次运行
    static func isFirstRun(
        historyFilePath: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        !fileExists(historyFilePath)
    }

    // MARK: - Tip Selection

    /// 获取启动提示文本。
    ///
    /// 首次运行时返回欢迎消息，否则从提示池中随机选择一条。
    /// 每次调用使用不同的随机种子，确保跨会话的多样性。
    ///
    /// - Parameters:
    ///   - isFirstRun: 是否首次运行
    ///   - tipIndex: 提示索引（用于确定性地选择提示，可注入用于测试）
    ///   - randomRange: 随机数生成闭包（0..<max → Int），nil 时使用系统随机
    /// - Returns: 提示文本，固定返回非 nil
    static func getTip(
        isFirstRun: Bool,
        tipIndex: Int? = nil,
        randomRange: ((Int) -> Int)? = nil
    ) -> String {
        if isFirstRun {
            return firstRunWelcome
        }
        let tips = allTips
        let index: Int
        if let idx = tipIndex {
            index = idx % tips.count
        } else if let rng = randomRange {
            index = rng(tips.count)
        } else {
            index = Int.random(in: 0..<tips.count)
        }
        return tips[index]
    }

    // MARK: - Rendering

    /// 渲染提示为终端友好的格式化行。
    ///
    /// TTY 模式：dim 样式 + 💡 图标 + 提示文本
    /// 非 TTY：纯文本格式
    ///
    /// - Parameters:
    ///   - tip: 提示文本
    ///   - isTTY: 是否为 TTY 输出
    ///   - colorProfile: 终端颜色配置
    /// - Returns: 格式化的提示字符串（含换行），空提示时返回 nil
    static func renderTip(
        _ tip: String,
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        colorProfile: TerminalColorProfile = .detect()
    ) -> String? {
        guard !tip.isEmpty else { return nil }

        guard isTTY else {
            return "💡 \(tip)\n"
        }

        let dimCode: String
        let reset = "\u{1B}[0m"
        switch colorProfile {
        case .trueColor:
            dimCode = "\u{1B}[38;2;148;163;184m"  // slate-400
        case .ansi256:
            dimCode = "\u{1B}[38;5;145m"
        case .ansi16:
            dimCode = "\u{1B}[2m"  // dim/faint
        case .unknown:
            return "💡 \(tip)\n"
        }
        return "\(dimCode)💡 \(tip)\(reset)\n"
    }

    // MARK: - Tip Content

    /// 首次运行欢迎消息。
    static let firstRunWelcome = "欢迎使用 Axion！输入任务即可开始，Ctrl+C 中断，/help 查看全部命令。"

    /// 功能提示池 — 覆盖 Axion 的核心能力，帮助用户发现。
    ///
    /// 遵循 Codex tooltips.txt 的设计原则：
    /// - 每条提示简短（一句话）
    /// - 指向具体操作（命令/快捷键）
    /// - 不重复启动横幅已展示的键位提示
    static let allTips: [String] = [
        "/diff 查看 AI 修改了哪些文件，/compact 手动压缩上下文窗口。",
        "/model sonnet 或 /model opus 可在会话中切换模型。",
        "Ctrl+Q 将消息加入队列，AI 处理完当前任务后自动执行。",
        "Ctrl+G 打开外部编辑器编写长提示，适合复杂任务描述。",
        "/copy 将最后一条 AI 回复复制到剪贴板。",
        "/status 查看会话状态卡：时长、token 用量、工具调用统计。",
        "Tab 键自动补全文件路径，支持相对路径和模糊搜索。",
        "/cost 查看当前会话的详细 token 用量和预估成本。",
        "/skills 列出所有可用技能 — 技能是无 LLM 的确定性自动化操作。",
        "Shift+Enter 或行末反斜杠续行 — 支持多行输入。",
        "/new 开始全新会话，/fork 分叉当前会话继续探索。",
        "上下方向键浏览历史输入，支持跨会话记忆。",
    ]
}
