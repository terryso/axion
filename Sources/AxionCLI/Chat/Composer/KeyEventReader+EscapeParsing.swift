import Darwin

// MARK: - Escape Sequence Parsing

extension KeyEventReader {

    /// 解析 escape 序列 — 从 \x1B 后的第一个字节开始。
    ///
    /// 支持：
    /// - CSI 序列（\x1b[...）— 方向键、功能键、bracket paste
    /// - SS3 序列（\x1bO...）— 应用键区箭头键
    /// - 单独 Esc 键（无后续字节）
    func parseEscape() -> KeyEvent {
        // 读取超时检测：如果有待读字节才继续解析 escape sequence
        var nextByte: UInt8 = 0
        let bytesRead = read(STDIN_FILENO, &nextByte, 1)
        guard bytesRead == 1 else {
            // 单独 Esc 键（无后续字节或读取超时）
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

    /// 解析 CSI (Control Sequence Introducer) 序列。
    /// 格式：\x1b[ <中间字节> <终结字节>
    func parseCSI() -> KeyEvent {
        var params = [UInt8]()
        var byte: UInt8 = 0

        // 读取参数字节（0x30–0x3F: 数字和分号）
        while true {
            let bytesRead = read(STDIN_FILENO, &byte, 1)
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

    /// 解析 CSI ~ 序列（Delete、Home、End 等）
    func parseCSITilde(params: [UInt8]) -> KeyEvent {
        // 将参数字节转为数字
        let paramStr = params.map { Character(UnicodeScalar($0)) }.map { String($0) }.joined()
        guard let paramNum = Int(paramStr) else {
            return .unknown([0x1B, 0x5B] + params + [0x7E])
        }

        switch paramNum {
        case 3:
            return .delete
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
        let bytesRead = read(STDIN_FILENO, &byte, 1)
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
        default:
            return .unknown([0x1B, 0x4F, byte])
        }
    }
}
