
/// 按键事件枚举 — 表示从终端读取的单个按键事件。
///
/// 封装 ANSI escape sequence 解析结果，将原始字节流转换为语义化按键事件。
/// 所有输入通过此枚举处理，不再是字符流，使得后续 Story 可以在同一个
/// 事件循环中拦截按键。
enum KeyEvent: Equatable {
    /// 可打印字符（含 UTF-8 多字节字符，如中文、emoji）
    case printable(String)
    /// Enter 键
    case enter
    /// Backspace 键（0x7F 或 0x08）
    case backspace
    /// Delete 键（\x1b[3~）
    case delete
    /// Esc 键（单独按下）
    case escape
    /// Up 箭头（\x1b[A 或 \x1bOA）
    case up
    /// Down 箭头（\x1b[B 或 \x1bOB）
    case down
    /// Left 箭头（\x1b[D 或 \x1bOD）
    case left
    /// Right 箭头（\x1b[C 或 \x1bOC）
    case right
    /// Tab 键
    case tab
    /// Ctrl 组合键（如 Ctrl+R = .ctrl("r")）
    case ctrl(Character)
    /// Home 键（\x1b[1~ 或 \x1bOH 或 CSI u keycode 72）
    case home
    /// End 键（\x1b[4~ 或 \x1bOF 或 CSI u keycode 76）
    case end
    /// Bracket Paste 开始标记（\x1b[200~）
    case bracketPasteStart
    /// Bracket Paste 结束标记（\x1b[201~）
    case bracketPasteEnd
    /// EOF（stdin 关闭）
    case eof
    /// 未知序列（无法识别的 escape sequence）
    case unknown([UInt8])
}

// MARK: - KeyReading Protocol

/// 按键读取协议 — 支持依赖注入。
///
/// 生产环境使用 `TerminalKeyReader`（真实 termios raw mode），
/// 测试环境使用 `MockKeyReader`（注入预定义 `KeyEvent` 序列）。
protocol KeyReading: Sendable {
    /// 读取下一个按键事件。返回 nil 表示 EOF。
    func readNext() -> KeyEvent?
}
