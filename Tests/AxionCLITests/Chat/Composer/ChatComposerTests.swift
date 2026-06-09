import Testing
@testable import AxionCLI

// MARK: - Test Helpers

/// 捕获 writeStdout / writeStderr 输出，并提供可队列化的 readLine 结果。
final class OutputCapture: @unchecked Sendable {
    var stdout = ""
    var stderr = ""
    var queuedLines: [String] = []

    func nextLine() -> String? {
        guard !queuedLines.isEmpty else { return nil }
        return queuedLines.removeFirst()
    }
}

/// 测试上下文 — 持有可变 composer 和输出捕获。
struct ComposerCtx {
    var composer: ChatComposer
    let capture: OutputCapture
}

private func makeComposer(
    events: [KeyEvent]? = nil,
    isTTY: Bool = true
) -> ComposerCtx {
    let capture = OutputCapture()
    let keyReader = events.map { MockKeyReader($0) }
    let composer = ChatComposer(
        isTTY: isTTY,
        writeStdout: { capture.stdout += $0 },
        writeStderr: { capture.stderr += $0 },
        readLineFn: { capture.nextLine() },
        keyReader: keyReader
    )
    return ComposerCtx(composer: composer, capture: capture)
}

// MARK: - Tests

@Suite("ChatComposer")
struct ChatComposerTests {

    // MARK: - AC1: 基本文本输入

    @Test("AC1: 普通文本输入并提交")
    func normalTextInput() {
        var ctx = makeComposer(events: [
            .printable("h"), .printable("i"), .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "hi")
        #expect(ctx.capture.stdout.contains("hi"))
    }

    @Test("AC1: 中文输入正确处理")
    func chineseInput() {
        var ctx = makeComposer(events: [
            .printable("你"), .printable("好"), .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "你好")
    }

    @Test("AC1: Emoji 输入正确处理")
    func emojiInput() {
        var ctx = makeComposer(events: [
            .printable("👋"), .printable("🌍"), .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "👋🌍")
    }

    @Test("AC1: Backspace 删除 UTF-8 字符（中文 3 字节）")
    func backspaceCJKCharacter() {
        var ctx = makeComposer(events: [
            .printable("你"), .printable("好"), .backspace, .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "你")
        #expect(ctx.capture.stdout.contains("你"))
    }

    @Test("AC1: Backspace 删除 Emoji（4 字节）")
    func backspaceEmoji() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("👋"), .backspace, .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "a")
    }

    @Test("AC1: Backspace 在空 buffer 无操作")
    func backspaceEmptyBuffer() {
        var ctx = makeComposer(events: [
            .backspace, .printable("x"), .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "x")
    }

    // MARK: - AC2: 反斜杠续行

    @Test("AC2: 反斜杠续行 — 合并多行")
    func backslashContinuation() {
        var ctx = makeComposer(events: [
            .printable("h"), .printable("e"), .printable("l"), .printable("l"), .printable("o"),
            .printable("\\"),  // 反斜杠
            .enter,           // 触发续行
            .printable("w"), .printable("o"), .printable("r"), .printable("l"), .printable("d"),
            .enter            // 结束续行
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "hello\nworld")
    }

    @Test("AC2: 续行中 Bracket paste — 粘贴内容作为续行输入")
    func continuationBracketPaste() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("\\"), .enter,  // 触发续行
            .bracketPasteStart,
            .printable("p"), .printable("a"), .printable("s"), .printable("t"), .printable("e"), .printable("d"),
            .bracketPasteEnd,
            .enter  // 提交续行
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "a\npasted")
    }

    @Test("AC2: 续行取消 — 空行返回空字符串")
    func continuationCancelEmptyLine() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("\\"), .enter,  // 触发续行
            .enter  // 空行取消
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "")
    }

    // MARK: - AC3: Bracket Paste

    @Test("AC3: Bracket paste 多行粘贴")
    func bracketPaste() {
        var ctx = makeComposer(events: [
            .bracketPasteStart,
            .printable("l"), .printable("i"), .printable("n"), .printable("e"), .printable("1"),
            .printable("\n"),
            .printable("l"), .printable("i"), .printable("n"), .printable("e"), .printable("2"),
            .bracketPasteEnd,
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "line1\nline2")
    }

    @Test("AC3: Bracket paste 单行")
    func bracketPasteSingleLine() {
        var ctx = makeComposer(events: [
            .bracketPasteStart,
            .printable("hello"),
            .bracketPasteEnd,
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "hello")
    }

    // MARK: - AC4: 快捷键响应（不吞键）

    @Test("AC4: Up 键不吞键 — 事件处理后继续")
    func upKeyNotSwallowed() {
        var ctx = makeComposer(events: [
            .up,
            .printable("x"), .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "x")
    }

    @Test("AC4: Down 键不吞键")
    func downKeyNotSwallowed() {
        var ctx = makeComposer(events: [
            .down,
            .printable("y"), .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "y")
    }

    @Test("AC4: Ctrl+R 不吞键")
    func ctrlRNotSwallowed() {
        var ctx = makeComposer(events: [
            .ctrl("r"),
            .printable("z"), .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "z")
    }

    @Test("AC4: Tab 不吞键")
    func tabNotSwallowed() {
        var ctx = makeComposer(events: [
            .tab,
            .printable("t"), .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "t")
    }

    @Test("AC4: Ctrl+G 不吞键")
    func ctrlGNotSwallowed() {
        var ctx = makeComposer(events: [
            .ctrl("g"),
            .printable("g"), .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "g")
    }

    // MARK: - AC5: Esc 清空

    @Test("AC5: Esc 在 normal 模式清空当前输入")
    func escClearsNormalMode() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("b"), .printable("c"),
            .escape,
            .printable("x"), .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "x")
        #expect(ctx.capture.stdout.contains("abc"))
    }

    // MARK: - AC7: 非 TTY 降级

    @Test("AC7: 非 TTY 降级到 readLine")
    func nonTTYDegradedToReadLine() {
        let capture = OutputCapture()
        capture.queuedLines = ["hello from pipe"]
        var composer = ChatComposer(
            isTTY: false,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { capture.nextLine() },
            keyReader: nil
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "hello from pipe")
    }

    // MARK: - AC8: Raw mode 不可用降级

    @Test("AC8: keyReader 为 nil → 降级路径（测试环境无真实 TTY）")
    func rawModeUnavailableDegraded() {
        let capture = OutputCapture()
        capture.queuedLines = ["degraded input"]
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { capture.nextLine() },
            keyReader: nil
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "degraded input")
    }

    // MARK: - Ctrl+C / EOF

    @Test("Ctrl+C 返回 nil")
    func ctrlCReturnsNil() {
        var ctx = makeComposer(events: [
            .printable("a"), .ctrl("c")
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == nil)
    }

    @Test("EOF 在空 buffer 返回 nil")
    func eofEmptyBuffer() {
        var ctx = makeComposer(events: [
            .eof
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == nil)
    }

    @Test("EOF 在非空 buffer — 返回已输入内容")
    func eofNonEmptyBuffer() {
        var ctx = makeComposer(events: [
            .printable("x"), .eof
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "x")
    }

    // MARK: - Bracket Paste API

    @Test("enableBracketPaste 在 TTY 输出控制序列")
    func enableBracketPasteTTY() {
        let capture = OutputCapture()
        let composer = ChatComposer(
            isTTY: true,
            writeStdout: { _ in },
            writeStderr: { capture.stderr += $0 },
            keyReader: nil
        )
        composer.enableBracketPaste()
        #expect(capture.stderr.contains("\u{1B}[?2004h"))
    }

    @Test("disableBracketPaste 在 TTY 输出控制序列")
    func disableBracketPasteTTY() {
        let capture = OutputCapture()
        let composer = ChatComposer(
            isTTY: true,
            writeStdout: { _ in },
            writeStderr: { capture.stderr += $0 },
            keyReader: nil
        )
        composer.disableBracketPaste()
        #expect(capture.stderr.contains("\u{1B}[?2004l"))
    }

    @Test("enableBracketPaste 非 TTY 不输出")
    func enableBracketPasteNonTTY() {
        let capture = OutputCapture()
        let composer = ChatComposer(
            isTTY: false,
            writeStdout: { _ in },
            writeStderr: { capture.stderr += $0 },
            keyReader: nil
        )
        composer.enableBracketPaste()
        #expect(capture.stderr.isEmpty)
    }

    // MARK: - Multi-line Wrapping

    @Test("stripAnsi 剥离 ANSI 转义码")
    func stripAnsiRemovesCodes() {
        let input = "\u{1B}[32mgreen\u{1B}[0m text"
        let result = ChatComposer.stripAnsi(input)
        #expect(result == "green text")
    }

    @Test("stripAnsi 处理纯文本（无 ANSI）")
    func stripAnsiPlain() {
        let input = "hello world"
        let result = ChatComposer.stripAnsi(input)
        #expect(result == "hello world")
    }

    @Test("stripAnsi 处理 OSC 序列")
    func stripAnsiOSC() {
        let input = "\u{1B}]0;title\u{07}content"
        let result = ChatComposer.stripAnsi(input)
        #expect(result == "content")
    }

    @Test("displayWidth 计算 ASCII 宽度")
    func displayWidthASCII() {
        #expect(ChatComposer.displayWidth("hello") == 5)
        #expect(ChatComposer.displayWidth("") == 0)
    }

    @Test("displayWidth 计算 CJK 宽度（双宽字符）")
    func displayWidthCJK() {
        // 每个 CJK 字符占 2 列
        #expect(ChatComposer.displayWidth("你好") == 4)
        #expect(ChatComposer.displayWidth("a你b") == 4)  // 1 + 2 + 1
    }

    @Test("displayWidth 忽略 ANSI 转义码")
    func displayWidthIgnoresAnsi() {
        let colored = "\u{1B}[32mhello\u{1B}[0m"
        #expect(ChatComposer.displayWidth(colored) == 5)
    }

    @Test("长中文输入超过终端宽度 — 重绘使用多行感知")
    func longCJKInputWrapsCorrectly() {
        // 40 个中文字符 = 80 列显示宽度，正好超过一个 80 列终端行
        let longText = String(repeating: "测", count: 40)
        var ctx = makeComposer(events: [
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"), .printable("测"), .printable("测"),
            .printable("测"),
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == longText)
        // 验证重绘输出了光标上移和清除序列
        let output = ctx.capture.stdout
        // \e[J 用于清除旧内容（多行感知刷新的核心标志）
        #expect(output.contains("\u{1B}[J"))
    }

    @Test("长文本 backspace 重绘正确")
    func longTextBackspace() {
        // 输入长文本后 backspace，验证重绘正确
        var ctx = makeComposer(events: [
            .printable("你"), .printable("好"), .printable("世"), .printable("界"),
            .backspace, .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "你好世")
    }
}
