import Foundation

/// 终端标签页标题管理器 — 受 Codex terminal_title.rs 启发。
///
/// 纯函数 struct，通过 OSC 0 序列设置/清除终端窗口标题。
/// 让用户在终端标签页中看到 Axion 当前状态（空闲/思考中/工具执行等）。
///
/// 标题内容：
/// - 空闲：`Axion` （简洁）
/// - 思考中：`Axion ⏳ 思考中...`
/// - 工具执行：`Axion ⏳ 工具名...`
/// - 使用率高：`Axion ⚠️ 85% context`
///
/// 非 TTY 环境自动静默跳过（同 SpinnerRenderer 模式）。
struct TerminalTitleRenderer {
    private let isTTY: Bool
    private let writeStderr: (String) -> Void

    init(
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        writeStderr: @escaping (String) -> Void = { fputs($0, stderr); fflush(stderr) }
    ) {
        self.isTTY = isTTY
        self.writeStderr = writeStderr
    }

    /// 设置终端标题（OSC 0 序列）。
    ///
    /// 对输入进行安全清理：移除控制字符和不可见 Unicode，
    /// 限制长度防止终端截断问题。
    func setTitle(_ title: String) {
        guard isTTY else { return }
        let sanitized = Self.sanitize(title)
        guard !sanitized.isEmpty else { return }
        // OSC 0: \033]0;title\007
        writeStderr("\u{1B}]0;\(sanitized)\u{07}")
    }

    /// 设置空闲状态标题 — 简洁的 "Axion"。
    func setIdle() {
        setTitle("Axion")
    }

    /// 设置思考中状态标题。
    func setThinking(elapsed: String? = nil) {
        if let elapsed = elapsed {
            setTitle("Axion ⏳ 思考中 \(elapsed)")
        } else {
            setTitle("Axion ⏳ 思考中...")
        }
    }

    /// 设置工具执行状态标题。
    func setToolExecuting(_ toolName: String) {
        setTitle("Axion ⏳ \(toolName)")
    }

    /// 设置上下文使用率警告标题。
    func setContextWarning(pct: Int) {
        setTitle("Axion ⚠️ \(pct)% context")
    }

    /// 清除终端标题（恢复为空）。
    func clear() {
        guard isTTY else { return }
        writeStderr("\u{1B}]0;\u{07}")
    }

    // MARK: - Sanitization

    /// 清理标题文本：移除控制字符、不可见格式化码、折叠空白。
    ///
    /// 移除的内容与 Codex terminal_title.rs 一致：
    /// - ASCII 控制字符 (0x00-0x1F 除了空格)
    /// - C1 控制字符 (0x80-0x9F)
    /// - Bidi/不可见格式化码
    /// - 连续空白折叠为单个空格
    /// - 最大 120 字符
    static func sanitize(_ title: String) -> String {
        var result = String()
        result.reserveCapacity(title.count)

        var lastWasSpace = false
        for scalar in title.unicodeScalars {
            let val = scalar.value
            // Skip ASCII control chars (except space 0x20)
            if val < 0x20 { continue }
            // Skip C1 control chars
            if val >= 0x80 && val <= 0x9F { continue }
            // Skip Bidi/invisible formatting
            if val >= 0x200E && val <= 0x200F { continue }  // LRM/RLM
            if val >= 0x202A && val <= 0x202E { continue }  // Bidi controls
            if val >= 0x2066 && val <= 0x2069 { continue }  // Bidi isolates
            if val == 0xFEFF { continue }  // BOM

            // Collapse whitespace
            if CharacterSet.whitespaces.contains(scalar) {
                if lastWasSpace { continue }
                lastWasSpace = true
                result.append(" ")
            } else {
                lastWasSpace = false
                result.append(Character(scalar))
            }
        }

        // Trim and limit
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        if trimmed.count > 120 {
            return String(trimmed.prefix(120))
        }
        return trimmed
    }
}
