import Darwin

/// CJK 输入处理器 — 在 raw mode 下正确处理 UTF-8 多字节字符的 backspace 删除。
///
/// 解决问题：macOS 终端 canonical mode 下，某些终端驱动对 UTF-8 多字节字符
/// （如中文 3 字节）只删除 1 字节，导致乱码。通过切换到 raw mode 自行处理
/// backspace，确保删除完整 UTF-8 字符。
///
/// 设计原则：
/// - 纯函数 struct + static methods（与 BannerRenderer、ContextManager 同模式）
/// - 只在 TTY + UTF-8 环境下启用 raw mode
/// - 每次读取一行后立即恢复终端模式，不长期保持 raw mode
/// - 不修改 ChatCommand（通过 MultiLineInputReader 间接使用）
struct CJKInputHandler {

    /// 最大单行输入长度（字节），防止超长行导致回显问题
    static let maxLineLength = 4096

    // MARK: - UTF-8 字符边界识别

    /// 根据 UTF-8 首字节判断字符字节长度。
    /// Delegates to KeyEventReader.utf8CharLength to avoid duplicated implementation.
    static func utf8CharLength(_ byte: UInt8) -> Int {
        KeyEventReader.utf8CharLength(byte)
    }

    // MARK: - Backspace 处理

    /// 从 buffer 末尾删除一个完整的 UTF-8 字符。
    ///
    /// 从 cursorPos 向前回溯，跳过 continuation bytes (0x80-0xBF)，
    /// 找到 lead byte，删除从 lead byte 到 cursorPos 的所有字节。
    ///
    /// - Parameters:
    ///   - buffer: 当前输入字节缓冲区
    ///   - cursorPos: 当前游标位置（也是 buffer 有效数据长度）
    /// - Returns: 删除后的新 buffer 和更新后的 cursorPos
    static func processBackspace(buffer: [UInt8], cursorPos: inout Int) -> [UInt8] {
        guard cursorPos > 0 else { return buffer }

        // 从 cursorPos 向前回溯，找到字符的 lead byte
        var pos = cursorPos - 1
        // 跳过 continuation bytes (0x80-0xBF)
        while pos > 0 && buffer[pos] >= 0x80 && buffer[pos] <= 0xBF {
            pos -= 1
        }
        // 现在 buffer[pos] 是 lead byte
        let charStart = pos

        // 删除从 charStart 到 cursorPos 的字节
        var newBuffer = buffer
        newBuffer.removeSubrange(charStart..<cursorPos)
        cursorPos = charStart
        return newBuffer
    }

    // MARK: - 环境检测

    /// 检测终端是否支持 UTF-8（LC_CTYPE / LANG 环境变量包含 "UTF-8"）。
    ///
    /// 只有在 UTF-8 终端下才需要使用 raw mode 处理 CJK 输入。
    static func isCJKEnabled() -> Bool {
        // 优先检查 LC_CTYPE
        if let lcCtype = getenv("LC_CTYPE") {
            let value = String(cString: lcCtype)
            if value.uppercased().contains("UTF-8") { return true }
        }
        // 回退检查 LANG
        if let lang = getenv("LANG") {
            let value = String(cString: lang)
            if value.uppercased().contains("UTF-8") { return true }
        }
        return false
    }

    // MARK: - Raw Mode 终端控制

    /// 将终端切换到 raw mode，返回原始 termios 设置用于后续恢复。
    ///
    /// 关闭 ICANON（行缓冲）和 ECHO（回显），启用 VMIN=1（至少读 1 字节）。
    private static func enterRawMode() -> termios? {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }

        var raw = original
        KeyEventReader.applyRawMode(&raw)

        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { return nil }
        return original
    }

    /// 恢复终端到原始设置。
    private static func restoreMode(_ original: termios) {
        var restore = original
        tcsetattr(STDIN_FILENO, TCSANOW, &restore)
    }

    // MARK: - Bracket Paste Constants

    /// Bracket paste start sequence: \x1b[200~
    private static let bracketPasteStart: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
    /// Bracket paste end sequence: \x1b[201~
    private static let bracketPasteEnd: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]

    // MARK: - Escape Sequence Matching

    /// Reads subsequent bytes from stdin and compares against a target escape sequence.
    ///
    /// Given the first byte (0x1B), reads the remaining bytes of the target sequence
    /// one by one, comparing each against the expected value.
    ///
    /// - Parameters:
    ///   - firstByte: The initial byte (always 0x1B)
    ///   - target: The full expected sequence (including the first byte)
    /// - Returns: Tuple of (whether the full sequence matched, all bytes read including firstByte)
    private static func matchEscapeSequence(
        firstByte: UInt8,
        target: [UInt8]
    ) -> (matched: Bool, bytesRead: [UInt8]) {
        var seq = [UInt8]([firstByte])
        var matched = true
        for i in 1..<target.count {
            var nextByte: UInt8 = 0
            let n = read(STDIN_FILENO, &nextByte, 1)
            guard n == 1 else { matched = false; break }
            seq.append(nextByte)
            if nextByte != target[i] {
                matched = false
                break
            }
        }
        return (matched && seq.count == target.count, seq)
    }

    // MARK: - Raw Mode 行读取

    /// 在 raw mode 下读取一行输入，正确处理 UTF-8 backspace。
    ///
    /// - Parameters:
    ///   - prompt: 提示符文本（如 "axion> "）
    ///   - writeStdout: 输出到 stdout 的闭包
    /// - Returns:
    ///   - `String?` 非 nil = 用户输入内容
    ///   - `nil` = EOF 或 Ctrl+C（让 SignalHandler 处理）
    static func readRawLine(prompt: String, writeStdout: (String) -> Void) -> String? {
        // 进入 raw mode
        guard let original = enterRawMode() else {
            // 无法进入 raw mode，回退到标准 readLine
            writeStdout(prompt)
            return readLine(strippingNewline: true)
        }

        // 确保退出时恢复终端
        defer { restoreMode(original) }

        // 显示提示符
        writeStdout(prompt)

        var buffer = [UInt8]()
        buffer.reserveCapacity(256)

        // Bracket paste 状态
        var inBracketPaste = false

        while true {
            var byte: UInt8 = 0
            let bytesRead = read(STDIN_FILENO, &byte, 1)

            // 检查 SIGINT
            if SignalHandler.fireCount() > 0 {
                // Ctrl+C 信号已被触发 — 恢复终端并返回 nil
                writeStdout("\r\n")
                return nil
            }

            guard bytesRead == 1 else {
                // EOF
                if !buffer.isEmpty {
                    return String(bytes: buffer, encoding: .utf8) ?? ""
                }
                return nil
            }

            // Bracket paste 检测
            if byte == 0x1B {
                if !inBracketPaste {
                    let (matched, _) = matchEscapeSequence(firstByte: byte, target: bracketPasteStart)
                    if matched {
                        inBracketPaste = true
                        continue
                    }
                    // 不匹配的 escape sequence — 忽略
                    continue
                } else {
                    let (matched, seq) = matchEscapeSequence(firstByte: byte, target: bracketPasteEnd)
                    if matched {
                        inBracketPaste = false
                        let content = String(bytes: buffer, encoding: .utf8) ?? ""
                        writeStdout("\r\(prompt)\(content)\u{1B}[K")
                        continue
                    }
                    // 不是 paste end — 追加已读字节到 buffer
                    buffer.append(contentsOf: seq)
                    continue
                }
            }

            // Enter — 完成输入（bracket paste 模式下将换行加入 buffer）
            if byte == 0x0D || byte == 0x0A {
                if inBracketPaste {
                    // 在 bracket paste 中，换行符作为内容的一部分
                    if byte == 0x0A && buffer.count < maxLineLength {
                        buffer.append(0x0A)
                    }
                    continue
                }
                writeStdout("\r\n")
                return String(bytes: buffer, encoding: .utf8) ?? ""
            }

            // Ctrl+C — 返回 nil（让 SignalHandler 处理）
            if byte == 0x03 {
                writeStdout("\r\n")
                return nil
            }

            // Ctrl+D — buffer 空时返回 nil（EOF）
            if byte == 0x04 {
                if buffer.isEmpty {
                    return nil
                }
                continue
            }

            // Backspace / Delete（bracket paste 模式下不处理）
            if byte == 0x7F || byte == 0x08 {
                if buffer.isEmpty || inBracketPaste { continue }
                var cursorPos = buffer.count
                buffer = processBackspace(buffer: buffer, cursorPos: &cursorPos)
                // 回显：回车 + prompt + 当前内容 + 清除行尾
                let content = String(bytes: buffer, encoding: .utf8) ?? ""
                writeStdout("\r\(prompt)\(content) \u{1B}[K")
                // 重新定位光标到内容末尾（空格清除后需要回退一个位置）
                if buffer.isEmpty {
                    writeStdout("\r\(prompt)\u{1B}[K")
                }
                continue
            }

            // 普通输入 — 追加到 buffer
            if buffer.count < maxLineLength {
                buffer.append(byte)

                // 如果在 bracket paste 中，不逐字回显
                if !inBracketPaste {
                    // 回显当前字符
                    if byte >= 0x20 && byte < 0x7F {
                        // 可打印 ASCII
                        let char = byte
                        writeStdout(String(bytes: [char], encoding: .ascii) ?? "")
                    } else if byte >= 0x80 {
                        // UTF-8 多字节 — 等待完整字符后再回显
                        // 检查是否已读入完整 UTF-8 字符
                        var pos = buffer.count - 1
                        while pos > 0 && buffer[pos] >= 0x80 && buffer[pos] <= 0xBF {
                            pos -= 1
                        }
                        let leadByte = buffer[pos]
                        let expectedLen = utf8CharLength(leadByte)
                        let charLen = buffer.count - pos
                        if charLen == expectedLen {
                            // 完整字符已读入 — 回显
                            let charBytes = Array(buffer[pos...])
                            if let str = String(bytes: charBytes, encoding: .utf8) {
                                writeStdout(str)
                            }
                        }
                    }
                }
            }
        }
    }
}
