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

    @Test("AC2: 续行空行提交 — 有内容时空行直接提交")
    func continuationEmptyLineSubmits() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("\\"), .enter,  // 触发续行
            .enter  // 空行提交已有内容
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "a")
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

    @Test("AC3: Bracket paste 保留已有输入 — 先输入再粘贴不覆盖")
    func bracketPasteAppendsToExistingInput() {
        var ctx = makeComposer(events: [
            .printable("123"),
            .bracketPasteStart,
            .printable("pasted"),
            .bracketPasteEnd,
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "123pasted")
    }

    @Test("AC3: Bracket paste 插入到光标位置（非末尾）")
    func bracketPasteInsertsAtCursor() {
        // 输入 "abc"，光标左移到 'b' 之后，再粘贴 "XY"
        var ctx = makeComposer(events: [
            .printable("abc"),
            .left,          // cursor 从 3 → 2（在 'b' 后面）
            .bracketPasteStart,
            .printable("XY"),
            .bracketPasteEnd,
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "abXYc")
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

    // MARK: - 多行编辑（Bracket Paste / 续行产生的 \n）

    @Test("多行 Backspace 删除换行符")
    func multilineBackspaceRemovesNewline() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("\n"), .printable("b"),
            .backspace, .backspace,  // 删除 'b' 和 '\n'
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "a")
    }

    // MARK: - Up/Down 多行行间导航

    @Test("多行 Up 在行间移动光标")
    func multilineUpMovesBetweenLines() {
        var ctx = makeComposer(events: [
            .printable("l"), .printable("1"), .printable("\n"),
            .printable("l"), .printable("2"),
            .up,  // 光标从 line2 移到 line1
            .printable("X"),  // 在 line1 末尾插入
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "l1X\nl2")
    }

    @Test("多行 Down 在行间移动光标")
    func multilineDownMovesBetweenLines() {
        var ctx = makeComposer(events: [
            .printable("l"), .printable("1"), .printable("\n"),
            .printable("l"), .printable("2"),
            .up,   // 到 line1
            .down,  // 回到 line2
            .printable("X"),
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "l1\nl2X")
    }

    @Test("多行首行 Up 溢出到历史")
    func multilineFirstLineUpGoesToHistory() {
        var ctx = makeComposer(events: [
            .printable("l"), .printable("1"), .printable("\n"),
            .printable("l"), .printable("2"),
            .up,   // 到 line1
            .up,   // 溢出到历史 → 加载 history[0]
            .enter
        ])
        ctx.composer.history = ["past input"]
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "past input")
    }

    @Test("多行末行 Down 溢出到历史")
    func multilineLastLineDownGoesToHistory() {
        var ctx = makeComposer(events: [
            .printable("l"), .printable("1"), .printable("\n"),
            .printable("l"), .printable("2"),
            .up,   // 到 line1
            .up,   // 溢出到 history[1]
            .down, // newer 方向：回到浏览前状态 "l1\nl2"
            .enter
        ])
        ctx.composer.history = ["past1", "past2"]
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "l1\nl2")
    }

    @Test("多行末行 Down 溢出到历史 — 多步导航")
    func multilineLastLineDownMultiStepHistory() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("\n"), .printable("b"),
            .up,   // 到 line1
            .up,   // 溢出到 history[2] = "h3"
            .up,   // history[1] = "h2"
            .down, // history[2] = "h3"
            .enter
        ])
        ctx.composer.history = ["h1", "h2", "h3"]
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "h3")
    }

    @Test("单行 Up/Down 走历史导航（无回归）")
    func singleLineUpDownHistoryNoRegression() {
        var ctx = makeComposer(events: [
            .up,    // 加载 history[0]
            .enter
        ])
        ctx.composer.history = ["old message"]
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "old message")
    }

    // MARK: - Home/End

    @Test("Home 跳到当前行首")
    func homeJumpsToLineStart() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("b"), .printable("c"),
            .home,
            .printable("X"),  // 在行首插入
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "Xabc")
    }

    @Test("End 跳到当前行尾")
    func endJumpsToLineEnd() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("b"),
            .left, .left,  // 光标在 'a' 前
            .end,           // 跳到行尾
            .printable("X"),
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "abX")
    }

    @Test("多行 Home 跳到当前行首")
    func multilineHomeJumpsToCurrentLineStart() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("b"), .printable("\n"),
            .printable("c"), .printable("d"),
            .home,     // 跳到 "cd" 行首
            .printable("X"),  // 在 line2 行首插入
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "ab\nXcd")
    }

    @Test("多行 End 跳到当前行尾")
    func multilineEndJumpsToCurrentLineEnd() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("b"), .printable("\n"),
            .printable("c"), .printable("d"),
            .home,     // 跳到 line2 行首
            .end,      // 跳到 line2 行尾
            .printable("X"),
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "ab\ncdX")
    }

    // MARK: - Ctrl+A / Ctrl+E

    @Test("Ctrl+A 跳到当前行首")
    func ctrlAJumpsToLineStart() {
        var ctx = makeComposer(events: [
            .printable("h"), .printable("i"),
            .ctrl("a"),
            .printable("X"),
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "Xhi")
    }

    @Test("Ctrl+A 多行时只跳到当前行首")
    func ctrlAMultilineJumpsToCurrentLineStart() {
        var ctx = makeComposer(events: [
            .printable("a"), .printable("\n"),
            .printable("b"), .printable("c"),
            .ctrl("a"),    // 跳到 line2 行首
            .printable("X"),
            .enter
        ])
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "a\nXbc")
    }

    // MARK: - History Navigation Display

    @Test("历史导航 Up — 空buffer不应产生光标上移序列")
    func historyUpNoCursorUpOnEmptyBuffer() {
        var ctx = makeComposer(events: [.up, .enter])
        ctx.composer.history = ["old message"]
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "old message")

        let output = ctx.capture.stdout
        // 空buffer + 短prompt → previousDisplayLines=1 → 不应有光标上移
        #expect(!output.contains("\u{1B}[1A"))
        #expect(!output.contains("\u{1B}[2A"))
    }

    @Test("历史导航 — 长history→短history 正确回退显示行")
    func historyNavLongToShort() {
        // 模拟：空buffer → Up(长history) → Up(短history)
        // 验证第二次 Up 的 refreshDisplay 正确使用了第一次的 displayLines
        let longHistory = String(repeating: "x", count: 80)  // > 终端宽度，会换行
        let shortHistory = "short"
        var ctx = makeComposer(events: [.up, .up, .enter])
        ctx.composer.history = [shortHistory, longHistory]
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == shortHistory)

        let output = ctx.capture.stdout
        // 第二次 refreshDisplay 应该有光标上移（因为第一次 longHistory 占多行）
        // 验证最终显示正确：应包含 shortHistory
        #expect(output.contains(shortHistory))
    }

    @Test("历史导航 — 从长history回到draft，显示不漂移")
    func historyNavLongBackToDraft() {
        let longHistory = String(repeating: "x", count: 80)
        var ctx = makeComposer(events: [
            .printable("h"), .printable("i"),  // 输入 "hi"
            .up,   // 加载 longHistory (多行)
            .down, // 回到 draft "hi"
            .enter
        ])
        ctx.composer.history = [longHistory]
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "hi")

        let output = ctx.capture.stdout
        // 验证输出包含 "hi" 且最终显示正确
        #expect(output.contains("hi"))
    }

    // MARK: - Multi-line History Navigation

    @Test("多行历史导航 — Up/Down 循环不累积光标上移")
    func multiLineHistoryNoAccumulation() {
        // history 含 \n（用户用 \ 续行输入的多行命令）
        let multiLineHistory = "first line\nsecond line"
        var ctx = makeComposer(events: [
            .up,   // 加载多行历史
            .down, // 回到空 draft
            .up,   // 再次加载多行历史
            .down, // 回到空 draft
            .enter
        ])
        ctx.composer.history = [multiLineHistory]
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "")

        let output = ctx.capture.stdout
        // historyDisplayShifted flag 确保预防性上移只发生一次
        // 不应该出现 \e[2A 或更高（表示累积偏移）
        #expect(!output.contains("\u{1B}[2A"))
        #expect(!output.contains("\u{1B}[3A"))
    }

    @Test("多行历史导航 — 两条多行历史切换正确")
    func multiLineHistorySwitchBetween() {
        // history[0] = 最旧, history[1] = 最新
        let history1 = "aaa\nbbb"
        let history2 = "ccc\nddd"
        var ctx = makeComposer(events: [
            .up,   // → history2 (最新), buffer = "ccc\nddd"
            .up,   // buffer 含 \n → 光标移到第 0 行（行间移动）
            .up,   // 光标在第 0 行 → navigateHistory(.older) → history1
            .down, // buffer = "aaa\nbbb", 光标在末尾(行1=末行) → navigateHistory(.newer) → history2
            .down, // buffer = "ccc\nddd", 光标在末尾(行1=末行) → navigateHistory(.newer) → draft ""
            .enter
        ])
        ctx.composer.history = [history1, history2]
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "")

        let output = ctx.capture.stdout
        // 验证所有历史内容都被正确输出
        #expect(output.contains("aaa"))
        #expect(output.contains("bbb"))
        #expect(output.contains("ccc"))
        #expect(output.contains("ddd"))
        // 不应有超过 1 行的上移（无累积）
        #expect(!output.contains("\u{1B}[2A"))
    }

    @Test("多行历史导航 — \r\\n 在 raw mode 下正确替换为 \\r\\n")
    func multiLineHistoryNewlineDisplay() {
        let multiLine = "hello\nworld"
        var ctx = makeComposer(events: [.up, .enter])
        ctx.composer.history = [multiLine]
        let result = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "hello\nworld")

        let output = ctx.capture.stdout
        // raw mode 下 \n 必须被替换为 \r\n，确保第二行从列 0 开始
        #expect(output.contains("hello\r\nworld"))
    }

    // MARK: - Debug: Multi-line History ANSI Trace

    @Test("DEBUG: 多行历史导航 — 精确 ANSI 序列追踪")
    func debugMultiLineHistoryAnsiTrace() {
        // 模拟用户场景：空 buffer → Up(多行历史) → Down(回draft) → Up(多行历史) → Down(回draft)
        let multiLine = "line1\nline2"
        var ctx = makeComposer(events: [
            .up,   // 加载多行历史
            .down, // 回到空 draft
            .up,   // 再次加载
            .down, // 回到空 draft
            .enter
        ])
        ctx.composer.history = [multiLine]
        let _ = ctx.composer.readInput(prompt: "> ", continuationPrompt: "...> ")

        let output = ctx.capture.stdout
        // 将输出分解为有意义的操作步骤
        var pos = output.startIndex
        var ops: [String] = []
        while pos < output.endIndex {
            let char = output[pos]
            if char == "\u{1B}" {
                // ANSI escape sequence
                let next = output.index(after: pos)
                if next < output.endIndex && output[next] == "[" {
                    // CSI sequence: collect until letter
                    var end = output.index(next, offsetBy: 1)
                    while end < output.endIndex && !output[end].isLetter {
                        end = output.index(after: end)
                    }
                    if end < output.endIndex {
                        end = output.index(after: end) // include the letter
                    }
                    let seq = String(output[pos..<end])
                    ops.append("CSI(\(seq))")
                    pos = end
                } else {
                    ops.append("ESC")
                    pos = next
                }
            } else if char == "\r" {
                ops.append("\\r")
                pos = output.index(after: pos)
            } else if char == "\n" {
                ops.append("\\n")
                pos = output.index(after: pos)
            } else {
                // Printable: collect until next control/escape
                var end = pos
                while end < output.endIndex {
                    let c = output[end]
                    if c == "\r" || c == "\n" || c == "\u{1B}" { break }
                    end = output.index(after: end)
                }
                let text = String(output[pos..<end])
                ops.append("TEXT(\"\(text)\")")
                pos = end
            }
        }

        // Print the operations for debugging
        print("=== Multi-line History ANSI Trace ===")
        for (i, op) in ops.enumerated() {
            print("  [\(i)] \(op)")
        }
        print("=== Total operations: \(ops.count) ===")

        // Count cursor-up sequences
        let cursorUpCount = ops.filter { $0.contains("[1A") }.count
        let cursorUp2Count = ops.filter { $0.contains("[2A") || $0.contains("[3A") }.count

        print("Cursor-up(1) count: \(cursorUpCount)")
        print("Cursor-up(2+) count: \(cursorUp2Count)")

        // The key assertion: no cursor-up beyond 1 row (no accumulation)
        #expect(cursorUp2Count == 0)
    }
}
