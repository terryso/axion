import Darwin

/// 终端按键读取器 — 封装 termios raw mode 生命周期和 ANSI escape sequence 解析。
///
/// 职责：
/// 1. termios raw mode 进入/恢复
/// 2. 逐字节读取 + ANSI escape sequence 解析（Up/Down 等）
/// 3. UTF-8 多字节字符边界处理
/// 4. Bracket paste 序列检测
/// 5. 非 TTY 检测（`isatty()` → 返回 `.eof`）
///
/// 如果 raw mode 设置失败，`create()` 返回 nil（降级路径由 ChatComposer 处理）。
struct KeyEventReader: KeyReading, Sendable {

    /// 原始 termios 设置，用于退出时恢复
    private let originalTermios: termios
    private let storedTermios: Bool
    let inputFD: Int32

    init(original: termios, inputFD: Int32 = STDIN_FILENO, storedTermios: Bool = true) {
        self.originalTermios = original
        self.inputFD = inputFD
        self.storedTermios = storedTermios
    }

    // MARK: - Factory

    /// 创建 KeyEventReader 实例。
    ///
    /// - Returns: 成功时返回实例；非 TTY 或 raw mode 设置失败时返回 nil。
    static func create() -> KeyEventReader? {
        // 非 TTY 检测
        guard isatty(STDIN_FILENO) != 0 else {
            return nil
        }

        // 保存当前 termios 设置
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            return nil
        }

        // 配置 raw mode
        var raw = original
        Self.applyRawMode(&raw)

        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
            return nil
        }

        let reader = KeyEventReader(original: original)
        return reader
    }

    // MARK: - KeyReading

    func readNext() -> KeyEvent? {
        var byte: UInt8 = 0
        let bytesRead = read(inputFD, &byte, 1)

        guard bytesRead == 1 else {
            return .eof
        }

        return parseByte(byte)
    }

    /// 恢复终端到原始设置。
    func restore() {
        guard storedTermios else { return }
        var restore = originalTermios
        tcsetattr(STDIN_FILENO, TCSANOW, &restore)
    }

    /// Apply raw mode settings to a termios structure.
    /// Shared between create(), reEnterRawMode(), and CJKInputHandler to avoid duplication.
    static func applyRawMode(_ raw: inout termios) {
        raw.c_iflag &= ~UInt(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_oflag &= ~UInt(OPOST)
        raw.c_cflag &= ~UInt(CSIZE | PARENB)
        raw.c_cflag |= UInt(CS8)
        raw.c_lflag &= ~UInt(ECHO | ICANON | IEXTEN | ISIG)
        raw.c_cc.16 = 1   // VMIN
        raw.c_cc.17 = 0   // VTIME
    }

    /// 重新进入 raw mode（外部编辑器关闭后恢复用）。
    ///
    /// 外部编辑器场景：先 `restore()` 恢复 normal mode → 启动编辑器 →
    /// 编辑器退出后调用 `reEnterRawMode()` 重新进入 raw mode。
    func reEnterRawMode() {
        guard storedTermios else { return }
        var raw = originalTermios
        Self.applyRawMode(&raw)
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    }

    // MARK: - Byte Parsing

    private func parseByte(_ byte: UInt8) -> KeyEvent {
        // Ctrl 组合键 (0x00–0x1F，排除特殊键)
        switch byte {
        case 0x0D, 0x0A:
            return .enter
        case 0x7F, 0x08:
            return .backspace
        case 0x09:
            return .tab
        case 0x1B:
            return parseEscape()
        case 0x03:
            return .ctrl("c")
        case 0x04:
            return .eof
        case 0x01:
            return .ctrl("a")
        case 0x05:
            return .ctrl("e")
        case 0x07:
            return .ctrl("g")
        case 0x0B:
            return .ctrl("k")
        case 0x0C:
            return .ctrl("l")
        case 0x0E:
            return .ctrl("n")
        case 0x10:
            return .ctrl("p")
        case 0x12:
            return .ctrl("r")
        case 0x15:
            return .ctrl("u")
        case 0x17:
            return .ctrl("w")
        case 0x18:
            return .ctrl("x")
        case 0x00, 0x02, 0x06, 0x0F, 0x11, 0x13, 0x14, 0x16, 0x19, 0x1A, 0x1C...0x1F:
            // 其他 Ctrl 组合键
            if byte >= 0x01, byte <= 0x1A {
                let char = Character(UnicodeScalar(UInt32(byte + 0x60))!)
                return .ctrl(char)
            }
            return .unknown([byte])
        default:
            break
        }

        // 可打印字符（含 UTF-8 多字节）
        if byte >= 0x20 && byte < 0x7F {
            // ASCII 可打印
            return .printable(String(UnicodeScalar(byte)))
        } else if byte >= 0x80 {
            // UTF-8 多字节字符 — 读取完整字符
            return readUTF8Char(firstByte: byte)
        }

        return .unknown([byte])
    }

    // MARK: - Escape Sequence Parsing (see KeyEventReader+EscapeParsing.swift)

    // MARK: - UTF-8 Multi-byte Character Reading

    /// 根据 UTF-8 首字节判断字符字节长度。
    ///
    /// - 0x00-0x7F: 1 字节 (ASCII)
    /// - 0xC0-0xDF: 2 字节
    /// - 0xE0-0xEF: 3 字节 (中文在此范围)
    /// - 0xF0-0xF7: 4 字节 (emoji 在此范围)
    static func utf8CharLength(_ byte: UInt8) -> Int {
        if byte < 0x80 { return 1 }
        if byte < 0xE0 { return 2 }
        if byte < 0xF0 { return 3 }
        return 4
    }

    /// 读取完整的 UTF-8 多字节字符。
    private func readUTF8Char(firstByte: UInt8) -> KeyEvent {
        let expectedLen = Self.utf8CharLength(firstByte)
        var bytes = [firstByte]

        for _ in 1..<expectedLen {
            var nextByte: UInt8 = 0
            let bytesRead = read(inputFD, &nextByte, 1)
            guard bytesRead == 1 else { break }
            bytes.append(nextByte)
        }

        if let str = String(bytes: bytes, encoding: .utf8) {
            return .printable(str)
        }

        return .unknown(bytes)
    }
}
