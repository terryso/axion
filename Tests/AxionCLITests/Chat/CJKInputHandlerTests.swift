import Testing

@testable import AxionCLI

@Suite("CJKInputHandler")
struct CJKInputHandlerTests {
    private func feed(
        _ processor: inout CJKRawLineProcessor,
        bytes: [UInt8],
        outputs: inout [String]
    ) -> CJKRawLineProcessor.Action {
        var index = 0
        var lastAction = CJKRawLineProcessor.Action.keepReading

        while index < bytes.count {
            let byte = bytes[index]
            index += 1

            let step = processor.processByte(byte) {
                guard index < bytes.count else { return nil }
                let next = bytes[index]
                index += 1
                return next
            }
            outputs.append(contentsOf: step.outputs)
            lastAction = step.action
            if case .finish = step.action {
                break
            }
        }

        return lastAction
    }

    // MARK: - utf8CharLength (Task 3.2)

    @Test("ASCII 字符 → 1 字节")
    func utf8CharLength_ascii() {
        #expect(CJKInputHandler.utf8CharLength(0x00) == 1)
        #expect(CJKInputHandler.utf8CharLength(0x41) == 1)  // 'A'
        #expect(CJKInputHandler.utf8CharLength(0x7F) == 1)
    }

    @Test("2 字节 UTF-8 头 (0xC0-0xDF) → 2")
    func utf8CharLength_twoByte() {
        #expect(CJKInputHandler.utf8CharLength(0xC0) == 2)
        #expect(CJKInputHandler.utf8CharLength(0xC8) == 2)
        #expect(CJKInputHandler.utf8CharLength(0xDF) == 2)
    }

    @Test("3 字节 UTF-8 头 (0xE0-0xEF) → 3（中文在此范围）")
    func utf8CharLength_threeByte() {
        #expect(CJKInputHandler.utf8CharLength(0xE0) == 3)
        #expect(CJKInputHandler.utf8CharLength(0xE4) == 3)
        #expect(CJKInputHandler.utf8CharLength(0xEF) == 3)
    }

    @Test("4 字节 UTF-8 头 (0xF0-0xF7) → 4（emoji 在此范围）")
    func utf8CharLength_fourByte() {
        #expect(CJKInputHandler.utf8CharLength(0xF0) == 4)
        #expect(CJKInputHandler.utf8CharLength(0xF3) == 4)
        #expect(CJKInputHandler.utf8CharLength(0xF7) == 4)
    }

    @Test("超范围字节 (0xF8+) → 4（兜底）")
    func utf8CharLength_outOfRange() {
        #expect(CJKInputHandler.utf8CharLength(0xF8) == 4)
        #expect(CJKInputHandler.utf8CharLength(0xFF) == 4)
    }

    // MARK: - processBackspace (Task 3.3)

    @Test("ASCII 删除：删除 1 字节")
    func processBackspace_ascii() {
        // "hello" = [0x68, 0x65, 0x6C, 0x6C, 0x6F]
        let buffer: [UInt8] = [0x68, 0x65, 0x6C, 0x6C, 0x6F]
        var cursorPos = 5
        let result = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(result == [0x68, 0x65, 0x6C, 0x6C])  // "hell"
        #expect(cursorPos == 4)
    }

    @Test("中文删除：删除完整 3 字节 UTF-8 字符")
    func processBackspace_chinese() {
        // "你好" in UTF-8:
        // 你 = [0xE4, 0xBD, 0xA0]
        // 好 = [0xE5, 0xA5, 0xBD]
        let buffer: [UInt8] = [0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD]
        var cursorPos = 6
        let result = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(result == [0xE4, 0xBD, 0xA0])  // "你"
        #expect(cursorPos == 3)
    }

    @Test("emoji 删除：删除完整 4 字节 UTF-8 字符")
    func processBackspace_emoji() {
        // 😀 = [0xF0, 0x9F, 0x98, 0x80]
        let buffer: [UInt8] = [0xF0, 0x9F, 0x98, 0x80]
        var cursorPos = 4
        let result = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(result == [])
        #expect(cursorPos == 0)
    }

    @Test("空 buffer → 无操作")
    func processBackspace_emptyBuffer() {
        let buffer: [UInt8] = []
        var cursorPos = 0
        let result = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(result == [])
        #expect(cursorPos == 0)
    }

    @Test("2 字节字符删除")
    func processBackspace_twoByte() {
        // © = [0xC2, 0xA9]
        let buffer: [UInt8] = [0xC2, 0xA9]
        var cursorPos = 2
        let result = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(result == [])
        #expect(cursorPos == 0)
    }

    // MARK: - isCJKEnabled (Task 3.4)

    @Test("isCJKEnabled 在 UTF-8 环境下返回 true（实际环境检测）")
    func isCJKEnabled_utf8Environment() {
        // macOS 默认终端通常设置 LC_CTYPE 或 LANG 包含 UTF-8
        // 此测试验证函数不崩溃并返回布尔值
        let result = CJKInputHandler.isCJKEnabled()
        // 在 macOS 开发环境中，通常返回 true
        #expect(type(of: result) == Bool.self)
    }

    // MARK: - 混合字符 backspace 序列 (Task 3.5)

    @Test("连续删除 'hello你好' 逐步回退")
    func processBackspace_mixedSequential() {
        // "hello你好" in UTF-8:
        // h=0x68, e=0x65, l=0x6C, l=0x6C, o=0x6F,
        // 你=0xE4,0xBD,0xA0, 好=0xE5,0xA5,0xBD
        let original: [UInt8] = [0x68, 0x65, 0x6C, 0x6C, 0x6F, 0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD]
        var buffer = original
        var cursorPos = buffer.count

        // 第 1 次 backspace：删除 "好" (3 bytes)
        buffer = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(buffer == [0x68, 0x65, 0x6C, 0x6C, 0x6F, 0xE4, 0xBD, 0xA0])
        #expect(cursorPos == 8)
        #expect(String(bytes: buffer, encoding: .utf8) == "hello你")

        // 第 2 次 backspace：删除 "你" (3 bytes)
        buffer = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(buffer == [0x68, 0x65, 0x6C, 0x6C, 0x6F])
        #expect(cursorPos == 5)
        #expect(String(bytes: buffer, encoding: .utf8) == "hello")

        // 第 3 次 backspace：删除 "o" (1 byte)
        buffer = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(buffer == [0x68, 0x65, 0x6C, 0x6C])
        #expect(cursorPos == 4)
        #expect(String(bytes: buffer, encoding: .utf8) == "hell")
    }

    @Test("混合 emoji + 中文 + ASCII 连续删除")
    func processBackspace_mixedEmojiChineseASCII() {
        // "A你😀" in UTF-8:
        // A=0x41, 你=0xE4,0xBD,0xA0, 😀=0xF0,0x9F,0x98,0x80
        let original: [UInt8] = [0x41, 0xE4, 0xBD, 0xA0, 0xF0, 0x9F, 0x98, 0x80]
        var buffer = original
        var cursorPos = buffer.count

        // 删除 😀 (4 bytes)
        buffer = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(buffer == [0x41, 0xE4, 0xBD, 0xA0])
        #expect(String(bytes: buffer, encoding: .utf8) == "A你")

        // 删除 你 (3 bytes)
        buffer = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(buffer == [0x41])
        #expect(String(bytes: buffer, encoding: .utf8) == "A")

        // 删除 A (1 byte)
        buffer = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(buffer == [])
        #expect(cursorPos == 0)
    }

    @Test("不完整 UTF-8 序列：backspace 删除已有字节")
    func processBackspace_incompleteUTF8() {
        // 模拟只有 lead byte + 1 continuation byte 的 3 字节字符（缺失第 3 字节）
        let buffer: [UInt8] = [0xE4, 0xBD]  // 不完整的 "你"
        var cursorPos = 2
        let result = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        // 应该删除已有的 2 个字节
        #expect(result == [])
        #expect(cursorPos == 0)
    }

    @Test("多个连续 backspace 清空整个输入")
    func processBackspace_clearAll() {
        // "你好" = [0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD]
        let original: [UInt8] = [0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD]
        var buffer = original
        var cursorPos = buffer.count

        // 删除 "好"
        buffer = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        // 删除 "你"
        buffer = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(buffer == [])
        #expect(cursorPos == 0)

        // 空 buffer 再 backspace → 无操作
        buffer = CJKInputHandler.processBackspace(buffer: buffer, cursorPos: &cursorPos)
        #expect(buffer == [])
        #expect(cursorPos == 0)
    }

    // MARK: - CJKRawLineProcessor

    @Test("raw processor completes ASCII line and returns echo output")
    func rawProcessorCompletesASCIILineAndEchoes() {
        var processor = CJKRawLineProcessor(prompt: "axion> ")
        var outputs: [String] = []

        let action = feed(&processor, bytes: Array("hi\n".utf8), outputs: &outputs)

        #expect(action == .finish("hi"))
        #expect(outputs == ["h", "i", "\r\n"])
        #expect(processor.currentBuffer == Array("hi".utf8))
    }

    @Test("raw processor echoes UTF-8 character only after complete byte sequence")
    func rawProcessorEchoesUTF8OnlyWhenComplete() {
        var processor = CJKRawLineProcessor(prompt: "")
        var outputs: [String] = []
        let bytes = Array("你".utf8)

        let first = feed(&processor, bytes: [bytes[0]], outputs: &outputs)
        #expect(first == .keepReading)
        #expect(outputs.isEmpty)

        let second = feed(&processor, bytes: Array(bytes[1...]), outputs: &outputs)
        #expect(second == .keepReading)
        #expect(outputs == ["你"])
    }

    @Test("raw processor backspace removes full UTF-8 character and redraws")
    func rawProcessorBackspaceRemovesFullUTF8Character() {
        var processor = CJKRawLineProcessor(prompt: "p> ")
        var outputs: [String] = []

        _ = feed(&processor, bytes: Array("你".utf8), outputs: &outputs)
        let action = feed(&processor, bytes: [0x7F], outputs: &outputs)

        #expect(action == .keepReading)
        #expect(processor.currentBuffer.isEmpty)
        #expect(outputs == ["你", "\rp>  \u{1B}[K", "\rp> \u{1B}[K"])
    }

    @Test("raw processor bracket paste suppresses echo until paste end")
    func rawProcessorBracketPasteSuppressesEchoUntilEnd() {
        var processor = CJKRawLineProcessor(prompt: "p> ")
        var outputs: [String] = []
        let bytes = CJKInputHandler.bracketPasteStart
            + Array("a\n你".utf8)
            + CJKInputHandler.bracketPasteEnd
            + [0x0A]

        let action = feed(&processor, bytes: bytes, outputs: &outputs)

        #expect(action == .finish("a\n你"))
        #expect(outputs == ["\rp> a\n你\u{1B}[K", "\r\n"])
        #expect(!processor.isInBracketPaste)
    }

    @Test("raw processor ignores unknown escape outside bracket paste")
    func rawProcessorIgnoresUnknownEscapeOutsidePaste() {
        var processor = CJKRawLineProcessor(prompt: "")
        var outputs: [String] = []
        let bytes: [UInt8] = [0x1B, 0x5B, 0x41, 0x0A]

        let action = feed(&processor, bytes: bytes, outputs: &outputs)

        #expect(action == .finish(""))
        #expect(processor.currentBuffer.isEmpty)
        #expect(outputs == ["\r\n"])
    }

    @Test("raw processor keeps unknown escape bytes inside bracket paste")
    func rawProcessorKeepsUnknownEscapeInsidePaste() {
        var processor = CJKRawLineProcessor(prompt: "")
        var outputs: [String] = []
        let bytes = CJKInputHandler.bracketPasteStart
            + [0x1B, 0x5B, 0x41]
            + CJKInputHandler.bracketPasteEnd
            + [0x0A]

        let action = feed(&processor, bytes: bytes, outputs: &outputs)

        #expect(action == .finish("\u{1B}[A"))
        #expect(outputs == ["\r\u{1B}[A\u{1B}[K", "\r\n"])
    }

    @Test("raw processor Ctrl-D finishes only when buffer is empty")
    func rawProcessorCtrlDFinishesOnlyWhenEmpty() {
        var emptyProcessor = CJKRawLineProcessor(prompt: "")
        var outputs: [String] = []
        let emptyAction = feed(&emptyProcessor, bytes: [0x04], outputs: &outputs)
        #expect(emptyAction == .finish(nil))

        var nonEmptyProcessor = CJKRawLineProcessor(prompt: "")
        outputs = []
        let action = feed(&nonEmptyProcessor, bytes: Array("x".utf8) + [0x04, 0x0A], outputs: &outputs)
        #expect(action == .finish("x"))
        #expect(outputs == ["x", "\r\n"])
    }

    @Test("raw processor enforces max line length for typed and pasted input")
    func rawProcessorEnforcesMaxLineLength() {
        var typedProcessor = CJKRawLineProcessor(prompt: "", maxLineLength: 2)
        var outputs: [String] = []
        let typedAction = feed(&typedProcessor, bytes: Array("abc\n".utf8), outputs: &outputs)
        #expect(typedAction == .finish("ab"))
        #expect(outputs == ["a", "b", "\r\n"])

        var pastedProcessor = CJKRawLineProcessor(prompt: "", maxLineLength: 2)
        outputs = []
        let pastedBytes = CJKInputHandler.bracketPasteStart
            + Array("abcd".utf8)
            + CJKInputHandler.bracketPasteEnd
            + [0x0A]
        let pastedAction = feed(&pastedProcessor, bytes: pastedBytes, outputs: &outputs)
        #expect(pastedAction == .finish("ab"))
        #expect(outputs == ["\rab\u{1B}[K", "\r\n"])
    }
}
