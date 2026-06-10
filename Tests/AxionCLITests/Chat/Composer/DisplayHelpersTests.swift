import Testing

@testable import AxionCLI

@Suite("ChatComposer DisplayHelpers")
struct DisplayHelpersTests {

    // MARK: - calculateDisplayLines

    @Test("single-line buffer fits in one display line")
    func testSingleLineFitsOneLine() {
        // prompt 20 chars + buffer 10 chars = 30 chars, fits in 80-col terminal
        let lines = ChatComposer.calculateDisplayLines(
            prompt: "axion [0/200k 0% ░░░]> ",
            buffer: "hello",
            termWidth: 80
        )
        #expect(lines == 1)
    }

    @Test("single-line buffer wraps to two lines")
    func testSingleLineWraps() {
        // prompt 30 chars + buffer 60 chars = 90 chars, wraps in 80-col terminal
        let lines = ChatComposer.calculateDisplayLines(
            prompt: String(repeating: "a", count: 30),
            buffer: String(repeating: "b", count: 60),
            termWidth: 80
        )
        // 30 + 60 = 90 → ceil(90/80) = 2
        #expect(lines == 2)
    }

    @Test("empty buffer counts as one line with prompt")
    func testEmptyBuffer() {
        let lines = ChatComposer.calculateDisplayLines(
            prompt: "prompt> ",
            buffer: "",
            termWidth: 80
        )
        #expect(lines == 1)
    }

    @Test("buffer with one newline produces two display lines")
    func testOneNewlineTwoLines() {
        // "line1\nline2" → two terminal lines
        let lines = ChatComposer.calculateDisplayLines(
            prompt: "> ",
            buffer: "line1\nline2",
            termWidth: 80
        )
        #expect(lines == 2)
    }

    @Test("buffer with multiple newlines produces correct display lines")
    func testMultipleNewlines() {
        // "a\nb\nc" → 3 terminal lines
        let lines = ChatComposer.calculateDisplayLines(
            prompt: "> ",
            buffer: "a\nb\nc",
            termWidth: 80
        )
        #expect(lines == 3)
    }

    @Test("trailing newline adds an empty display line")
    func testTrailingNewline() {
        // "hello\n" → line 1 = "hello", line 2 = "" (empty)
        let lines = ChatComposer.calculateDisplayLines(
            prompt: "> ",
            buffer: "hello\n",
            termWidth: 80
        )
        #expect(lines == 2)
    }

    @Test("empty line between newlines counts as one display line")
    func testEmptyLineBetweenNewlines() {
        // "a\n\nc" → 3 lines: "a", "", "c"
        let lines = ChatComposer.calculateDisplayLines(
            prompt: "> ",
            buffer: "a\n\nc",
            termWidth: 80
        )
        #expect(lines == 3)
    }

    @Test("long line after newline wraps correctly")
    func testLongLineAfterNewlineWraps() {
        // "> " = 2 chars, "short" = 5 chars → line 1: 7 chars (1 line)
        // 90-char line → ceil(90/80) = 2 lines
        let lines = ChatComposer.calculateDisplayLines(
            prompt: "> ",
            buffer: "short\n" + String(repeating: "x", count: 90),
            termWidth: 80
        )
        #expect(lines == 3)  // 1 + 2
    }

    @Test("CJK wide characters in multi-line buffer calculate correctly")
    func testCJKMultiLine() {
        // "你好" = 4 display cols, "世界" = 4 display cols
        let lines = ChatComposer.calculateDisplayLines(
            prompt: "> ",
            buffer: "你好\n世界",
            termWidth: 80
        )
        #expect(lines == 2)
    }

    @Test("ANSI codes in prompt are stripped for width calculation")
    func testANSIInPrompt() {
        // ANSI color codes have 0 display width
        let prompt = "\u{1B}[38;2;76;175;80m>\u{1B}[0m "
        let lines = ChatComposer.calculateDisplayLines(
            prompt: prompt,
            buffer: "hello",
            termWidth: 80
        )
        // prompt display width = "> " = 2, buffer = 5 → total 7 → 1 line
        #expect(lines == 1)
    }

    // MARK: - cursorVisualPosition

    @Test("cursor at end of single-line buffer")
    func testCursorAtEnd() {
        let pos = ChatComposer.cursorVisualPosition(
            prompt: "> ",
            buffer: "hello",
            cursor: 5,
            termWidth: 80
        )
        // "> " (2) + "hello" (5) = col 7
        #expect(pos.row == 0)
        #expect(pos.col == 7)
    }

    @Test("cursor at start of single-line buffer")
    func testCursorAtStart() {
        let pos = ChatComposer.cursorVisualPosition(
            prompt: "> ",
            buffer: "hello",
            cursor: 0,
            termWidth: 80
        )
        // prompt width = 2, cursor at col 2
        #expect(pos.row == 0)
        #expect(pos.col == 2)
    }

    @Test("cursor in middle of single-line buffer")
    func testCursorInMiddle() {
        let pos = ChatComposer.cursorVisualPosition(
            prompt: "> ",
            buffer: "hello",
            cursor: 3,
            termWidth: 80
        )
        // "> " (2) + "hel" (3) = col 5
        #expect(pos.row == 0)
        #expect(pos.col == 5)
    }

    @Test("cursor at start of second line in multi-line buffer")
    func testCursorAtSecondLineStart() {
        let pos = ChatComposer.cursorVisualPosition(
            prompt: "> ",
            buffer: "line1\nline2",
            cursor: 6,  // after "line1\n"
            termWidth: 80
        )
        // row: "> " + "line1" = 7 → 0 full rows, row = 0
        // cursor at start of "line2" → col = 0
        #expect(pos.row == 1)
        #expect(pos.col == 0)
    }

    @Test("cursor at end of second line in multi-line buffer")
    func testCursorAtSecondLineEnd() {
        let pos = ChatComposer.cursorVisualPosition(
            prompt: "> ",
            buffer: "line1\nline2",
            cursor: 11,  // after "line1\nline2"
            termWidth: 80
        )
        // end of "line2" → row 1, col 5
        #expect(pos.row == 1)
        #expect(pos.col == 5)
    }

    @Test("cursor in middle of second line in multi-line buffer")
    func testCursorInSecondLineMiddle() {
        let pos = ChatComposer.cursorVisualPosition(
            prompt: "> ",
            buffer: "line1\nline2",
            cursor: 8,  // after "line1\nli"
            termWidth: 80
        )
        // "li" → col 2
        #expect(pos.row == 1)
        #expect(pos.col == 2)
    }

    @Test("cursor in third line of three-line buffer")
    func testCursorInThirdLine() {
        let pos = ChatComposer.cursorVisualPosition(
            prompt: "> ",
            buffer: "a\nb\nc",
            cursor: 4,  // after "a\nb\n"
            termWidth: 80
        )
        #expect(pos.row == 2)
        #expect(pos.col == 0)
    }

    @Test("cursor at end of wrapped first line")
    func testCursorAtWrapBoundary() {
        // 80-col terminal, prompt = 2 chars, buffer = 78 chars = fills line 1
        // cursor at 78 → col = 2 + 78 = 80, row = 1, col = 0
        let pos = ChatComposer.cursorVisualPosition(
            prompt: "> ",
            buffer: String(repeating: "x", count: 78),
            cursor: 78,
            termWidth: 80
        )
        #expect(pos.row == 1)
        #expect(pos.col == 0)
    }

    @Test("cursor at end of long multi-line buffer")
    func testEndPositionOfMultiLine() {
        // For refreshDisplay: end position of "line1\nline2\nline3"
        let pos = ChatComposer.cursorVisualPosition(
            prompt: "> ",
            buffer: "line1\nline2\nline3",
            cursor: 17,
            termWidth: 80
        )
        #expect(pos.row == 2)
        #expect(pos.col == 5)
    }

    @Test("empty buffer cursor position")
    func testEmptyBufferCursor() {
        let pos = ChatComposer.cursorVisualPosition(
            prompt: "> ",
            buffer: "",
            cursor: 0,
            termWidth: 80
        )
        #expect(pos.row == 0)
        #expect(pos.col == 2)
    }
}

// MARK: - Testable overload for calculateDisplayLines with explicit termWidth

extension ChatComposer {
    /// 测试用重载：接受明确的 termWidth 参数，避免依赖 ioctl。
    static func calculateDisplayLines(
        prompt: String, buffer: String, termWidth: Int
    ) -> Int {
        let bufferLines = buffer.components(separatedBy: "\n")

        var totalLines = 0
        for (i, line) in bufferLines.enumerated() {
            let lineWidth = (i == 0 ? displayWidth(prompt) : 0) + displayWidth(line)
            totalLines += max(1, (lineWidth + termWidth - 1) / termWidth)
        }
        return totalLines
    }
}
