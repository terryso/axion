import Darwin

// MARK: - Escape Sequence Parsing

extension KeyEventReader {
    static let escapeSequenceTimeoutMilliseconds: Int32 = 30

    /// 解析 escape 序列 — 从 \x1B 后的第一个字节开始。
    ///
    /// 支持：
    /// - CSI 序列（\x1b[...）— 方向键、功能键、bracket paste、CSI u (Kitty keyboard protocol)
    /// - SS3 序列（\x1bO...）— 应用键区箭头键、Home/End
    /// - 单独 Esc 键（无后续字节）
    func parseEscape() -> KeyEvent {
        // 单独 Esc 没有后续字节；先短超时探测，避免阻塞等待 escape sequence。
        guard hasPendingInput(timeoutMilliseconds: Self.escapeSequenceTimeoutMilliseconds) else {
            return .escape
        }

        var nextByte: UInt8 = 0
        let bytesRead = read(inputFD, &nextByte, 1)
        guard bytesRead == 1 else {
            return .escape
        }

        // CSI 序列（\x1b[）
        if nextByte == 0x5B {  // '['
            return parseCSI()
        }

        // SS3 序列（\x1bO）— 应用键区箭头键
        if nextByte == 0x4F {  // 'O'
            return parseSS3()
        }

        // 其他 escape 序列 — 作为未知处理
        return .unknown([0x1B, nextByte])
    }

    func hasPendingInput(timeoutMilliseconds: Int32) -> Bool {
        var descriptor = pollfd(fd: inputFD, events: Int16(POLLIN), revents: 0)
        let result = poll(&descriptor, nfds_t(1), timeoutMilliseconds)
        return result > 0 && (descriptor.revents & Int16(POLLIN)) != 0
    }

    /// 解析 CSI (Control Sequence Introducer) 序列。
    /// 格式：\x1b[ <中间字节> <终结字节>
    func parseCSI() -> KeyEvent {
        var params = [UInt8]()
        var byte: UInt8 = 0

        // 读取参数字节（0x30–0x3F: 数字和分号）
        while true {
            let bytesRead = read(inputFD, &byte, 1)
            guard bytesRead == 1 else { return .unknown([0x1B, 0x5B]) }

            if byte >= 0x30 && byte <= 0x3F {
                params.append(byte)
            } else {
                break
            }
        }

        // byte 现在是终结字节（0x40–0x7E）
        switch byte {
        case 0x41:  // 'A' — Up
            return .up
        case 0x42:  // 'B' — Down
            return .down
        case 0x43:  // 'C' — Right
            return .right
        case 0x44:  // 'D' — Left
            return .left
        case 0x48:  // 'H' — Home (CSI H, also used in some terminals)
            return .home
        case 0x46:  // 'F' — End (CSI F, also used in some terminals)
            return .end
        case 0x75:  // 'u' — CSI u (Kitty keyboard protocol)
            return parseCSIU(params: params)
        case 0x7E:  // '~' — 功能键
            return parseCSITilde(params: params)
        default:
            // 未知 CSI 序列
            var seq = [UInt8]([0x1B, 0x5B])
            seq.append(contentsOf: params)
            seq.append(byte)
            return .unknown(seq)
        }
    }

    /// 解析 CSI u 序列（Kitty keyboard protocol）。
    /// 格式：\x1b[keycode;event_type;modifiers u
    /// 或简化：\x1b[keycode;modifiers u（省略 event_type）
    ///
    /// modifiers 位掩码：bit0=shift, bit1=alt, bit2=ctrl, bit3=super
    /// event_type: 1=press, 2=repeat, 3=release
    func parseCSIU(params: [UInt8]) -> KeyEvent {
        let paramStr = params.map { Character(UnicodeScalar($0)) }.map { String($0) }.joined()
        let parts = paramStr.split(separator: ";", omittingEmptySubsequences: false)
            .compactMap { Int($0) }

        guard let keycode = parts.first, parts.count >= 1 else {
            return .unknown([0x1B, 0x5B] + params + [0x75])
        }

        // 解析 modifiers（第2个或第3个参数，取决于是否有 event_type）
        let modifiers: Int
        if parts.count == 3 {
            // keycode;event_type;modifiers
            let eventType = parts[1]
            // 仅处理 key press (1)，忽略 repeat(2) 和 release(3)
            guard eventType == 1 else {
                return .unknown([0x1B, 0x5B] + params + [0x75])
            }
            modifiers = parts[2]
        } else if parts.count == 2 {
            // keycode;modifiers (省略 event_type，默认 press)
            modifiers = parts[1]
        } else {
            // keycode only, no modifiers
            modifiers = 0
        }

        let hasCtrl = (modifiers & 0x4) != 0

        switch keycode {
        case 13:  // Enter
            return .enter

        case 72:  // Home (kitty keycode for Home)
            return .home
        case 76:  // End (kitty keycode for End)
            return .end

        // Ctrl + 字母键 (keycode 97–122 对应 a–z 的 Unicode codepoint)
        case 97...122 where hasCtrl:
            let char = Character(UnicodeScalar(keycode)!)
            return .ctrl(char)

        // Ctrl + 特殊键
        case 32 where hasCtrl:   // Ctrl+Space
            return .ctrl(" ")

        // Escape (keycode 27)
        case 27:
            return .escape

        // Backspace (keycode 127 或 8)
        case 8, 127:
            return .backspace

        // Tab (keycode 9)
        case 9:
            return .tab

        // Delete (keycode 51 = '3' 在某些终端，或 57363 kitty)
        case 51:
            return .delete

        // 可打印字母 (a–z, 无 Ctrl 修饰)
        case 97...122 where !hasCtrl:
            return .printable(String(UnicodeScalar(keycode)!))

        // 空格 (keycode 32, 无修饰)
        case 32:
            return .printable(" ")

        // 数字 0–9 (keycode 48–57)
        case 48...57:
            return .printable(String(UnicodeScalar(keycode)!))

        // 可打印 ASCII 符号 (keycode 33–47, 58–64, 91–96, 123–126)
        case 33...47, 58...64, 91...96, 123...126:
            return .printable(String(UnicodeScalar(keycode)!))

        // Unicode 兜底：任何有效 codepoint 且无 Ctrl 修饰 → .printable
        // 覆盖中文 (0x4E00–0x9FFF)、日文、韩文、emoji 等所有非 ASCII 字符
        default:
            if !hasCtrl,
               keycode >= 0x20,
               let scalar = UnicodeScalar(keycode) {
                return .printable(String(scalar))
            }
            return .unknown([0x1B, 0x5B] + params + [0x75])
        }
    }

    /// 解析 CSI ~ 序列（Delete、Home、End 等）
    func parseCSITilde(params: [UInt8]) -> KeyEvent {
        // 将参数字节转为数字
        let paramStr = params.map { Character(UnicodeScalar($0)) }.map { String($0) }.joined()
        guard let paramNum = Int(paramStr) else {
            return .unknown([0x1B, 0x5B] + params + [0x7E])
        }

        switch paramNum {
        case 1:   // Home (\x1b[1~)
            return .home
        case 3:
            return .delete
        case 4:   // End (\x1b[4~)
            return .end
        case 200:
            return .bracketPasteStart
        case 201:
            return .bracketPasteEnd
        default:
            return .unknown([0x1B, 0x5B] + params + [0x7E])
        }
    }

    /// 解析 SS3 序列（\x1bO 终结键）
    func parseSS3() -> KeyEvent {
        var byte: UInt8 = 0
        let bytesRead = read(inputFD, &byte, 1)
        guard bytesRead == 1 else { return .unknown([0x1B, 0x4F]) }

        switch byte {
        case 0x41:  // 'A' — Up
            return .up
        case 0x42:  // 'B' — Down
            return .down
        case 0x43:  // 'C' — Right
            return .right
        case 0x44:  // 'D' — Left
            return .left
        case 0x48:  // 'H' — Home
            return .home
        case 0x46:  // 'F' — End
            return .end
        default:
            return .unknown([0x1B, 0x4F, byte])
        }
    }
}
