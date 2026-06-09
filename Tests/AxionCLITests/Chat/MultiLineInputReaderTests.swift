import Testing

@testable import AxionCLI

@Suite("MultiLineInputReader")
struct MultiLineInputReaderTests {

    // MARK: - Helpers

    /// Wrapper to hold mutable state that closures can capture.
    private final class LineProvider {
        var lines: [String?]
        var index = 0

        init(lines: [String?]) {
            self.lines = lines
        }

        func next() -> String? {
            guard index < lines.count else { return nil }
            let line = lines[index]
            index += 1
            return line
        }
    }

    /// Wrapper to capture stdout output.
    private final class OutputCapture {
        var output = ""
        func append(_ str: String) { output += str }
        func getOutput() -> String { output }
    }

    /// Creates a reader with injected readLineFn returning the given sequence of lines.
    private func makeReader(
        isTTY: Bool = true,
        lines: [String?]
    ) -> MultiLineInputReader {
        let provider = LineProvider(lines: lines)
        return MultiLineInputReader(
            isTTY: isTTY,
            readLineFn: { provider.next() },
            writeStdout: { _ in },
            writeStderr: { _ in },
            cjkEnabledFn: { false }  // 测试中禁用 CJK raw mode，使用注入的 readLineFn
        )
    }

    // MARK: - AC3: 非 TTY 降级 — 直接 readLine，不处理 paste/续行

    @Test("非 TTY 模式：直接返回 readLine 结果，不处理续行")
    func nonTTY_returnsReadlineDirectly() {
        let reader = makeReader(isTTY: false, lines: ["hello"])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(result == "hello")
    }

    @Test("非 TTY 模式：readLine 返回 nil → nil（EOF）")
    func nonTTY_returnsNilOnEOF() {
        let reader = makeReader(isTTY: false, lines: [nil])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(result == nil)
    }

    @Test("非 TTY 模式：行末反斜杠不触发续行")
    func nonTTY_backslashNotContinuation() {
        let input = "print(" + "\\"
        let reader = makeReader(isTTY: false, lines: [input])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(result == input)
    }

    @Test("非 TTY 模式：不输出 prompt 到 stdout")
    func nonTTY_doesNotOutputPrompt() {
        let capture = OutputCapture()
        let provider = LineProvider(lines: ["hello"])
        let reader = MultiLineInputReader(
            isTTY: false,
            readLineFn: { provider.next() },
            writeStdout: { capture.append($0) },
            writeStderr: { _ in },
            cjkEnabledFn: { false }
        )
        _ = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(capture.getOutput() == "")
    }

    // MARK: - AC1: 反斜杠续行

    @Test("单行无反斜杠 → 直接返回")
    func singleLineNoBackslash() {
        let reader = makeReader(isTTY: true, lines: ["hello"])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(result == "hello")
    }

    @Test("行末反斜杠 + 下一行 → 合并（去除反斜杠，用换行连接）")
    func backslashContinuation() {
        let backslash = "\\"
        let reader = makeReader(isTTY: true, lines: ["print(" + backslash, "hello)"])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(result == "print(\nhello)")
    }

    @Test("多级续行（3 行）")
    func multiLevelContinuation() {
        let bs = "\\"
        let reader = makeReader(isTTY: true, lines: [
            "func foo(" + bs,
            "  bar: String," + bs,
            "  baz: Int" + bs,
            ")"
        ])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(result == "func foo(\n  bar: String,\n  baz: Int\n)")
    }

    // MARK: - AC6: 续行取消

    @Test("续行模式下空行输入 → 取消信号（返回空字符串）")
    func continuationCancel_emptyLine() {
        let bs = "\\"
        let reader = makeReader(isTTY: true, lines: ["print(" + bs, ""])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        // 续行取消返回空字符串 ""（与 nil/EOF 区分）
        #expect(result == "")
    }

    @Test("续行模式下空格行不触发取消 → 正常结束")
    func continuation_whitespaceOnly_notCancel() {
        let bs = "\\"
        let reader = makeReader(isTTY: true, lines: ["print(" + bs, "   )"])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        // 空格行不是空行，不触发取消
        #expect(result == "print(\n   )")
    }

    // MARK: - AC2: Bracket Paste 多行粘贴

    @Test("Bracket paste：完整包裹 → 内容原样合并")
    func bracketPaste_complete() {
        let reader = makeReader(isTTY: true, lines: [
            "\u{1B}[200~line1",
            "line2",
            "line3\u{1B}[201~"
        ])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(result == "line1\nline2\nline3")
    }

    @Test("Bracket paste：单行包裹 → 返回内容")
    func bracketPaste_singleLine() {
        let reader = makeReader(isTTY: true, lines: [
            "\u{1B}[200~hello\u{1B}[201~"
        ])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(result == "hello")
    }

    @Test("无包裹序列 → 正常 readLine 行为")
    func noBracketPaste_normalInput() {
        let reader = makeReader(isTTY: true, lines: ["normal input"])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(result == "normal input")
    }

    @Test("Bracket paste 内容含反斜杠 → 不触发续行")
    func bracketPaste_withBackslash() {
        let bs = "\\"
        let reader = makeReader(isTTY: true, lines: [
            "\u{1B}[200~line1" + bs,
            "line2\u{1B}[201~"
        ])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        // Bracket paste 内容不做续行处理
        let expected = "line1" + bs + "\nline2"
        #expect(result == expected)
    }

    @Test("Bracket paste：EOF 中途 → 返回已累积内容")
    func bracketPaste_eof_returnsAccumulated() {
        let reader = makeReader(isTTY: true, lines: [
            "\u{1B}[200~line1",
            "line2"
            // No pasteEnd — simulates EOF
        ])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        // EOF during bracket paste → return accumulated content
        #expect(result == "line1\nline2")
    }

    // MARK: - EOF 处理

    @Test("TTY 模式：readLine 返回 nil → nil（EOF）")
    func tty_eof_returnsNil() {
        let reader = makeReader(isTTY: true, lines: [nil])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(result == nil)
    }

    @Test("续行中 EOF → 返回已累积内容")
    func continuation_eof_returnsAccumulated() {
        let bs = "\\"
        let reader = makeReader(isTTY: true, lines: ["print(" + bs, nil])
        let result = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        // 续行中遇到 EOF，返回已累积的内容
        #expect(result == "print(")
    }

    // MARK: - AC4: 终端恢复 — enableBracketPaste / disableBracketPaste

    @Test("enableBracketPaste 输出正确 ANSI 序列")
    func enableBracketPaste_outputsCorrectSequence() {
        let capture = OutputCapture()
        let reader = MultiLineInputReader(
            isTTY: true,
            readLineFn: { nil },
            writeStdout: { _ in },
            writeStderr: { capture.append($0) },
            cjkEnabledFn: { false }
        )
        reader.enableBracketPaste()
        #expect(capture.getOutput() == "\u{1B}[?2004h")
    }

    @Test("disableBracketPaste 输出正确 ANSI 序列")
    func disableBracketPaste_outputsCorrectSequence() {
        let capture = OutputCapture()
        let reader = MultiLineInputReader(
            isTTY: true,
            readLineFn: { nil },
            writeStdout: { _ in },
            writeStderr: { capture.append($0) },
            cjkEnabledFn: { false }
        )
        reader.disableBracketPaste()
        #expect(capture.getOutput() == "\u{1B}[?2004l")
    }

    @Test("非 TTY 模式下 enableBracketPaste 不输出")
    func nonTTY_enableBracketPaste_noOutput() {
        let capture = OutputCapture()
        let reader = MultiLineInputReader(
            isTTY: false,
            readLineFn: { nil },
            writeStdout: { _ in },
            writeStderr: { capture.append($0) },
            cjkEnabledFn: { false }
        )
        reader.enableBracketPaste()
        #expect(capture.getOutput() == "")
    }

    @Test("非 TTY 模式下 disableBracketPaste 不输出")
    func nonTTY_disableBracketPaste_noOutput() {
        let capture = OutputCapture()
        let reader = MultiLineInputReader(
            isTTY: false,
            readLineFn: { nil },
            writeStdout: { _ in },
            writeStderr: { capture.append($0) },
            cjkEnabledFn: { false }
        )
        reader.disableBracketPaste()
        #expect(capture.getOutput() == "")
    }

    // MARK: - 提示符输出

    @Test("readInput 输出 prompt 到 stdout")
    func readInput_outputsPrompt() {
        let capture = OutputCapture()
        let provider = LineProvider(lines: ["hello"])
        let reader = MultiLineInputReader(
            isTTY: true,
            readLineFn: { provider.next() },
            writeStdout: { capture.append($0) },
            writeStderr: { _ in },
            cjkEnabledFn: { false }
        )
        _ = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        #expect(capture.getOutput().contains("axion> "))
    }

    @Test("续行模式输出 continuationPrompt")
    func continuation_outputsContinuationPrompt() {
        let capture = OutputCapture()
        let bs = "\\"
        let provider = LineProvider(lines: ["print(" + bs, "hello)"])
        let reader = MultiLineInputReader(
            isTTY: true,
            readLineFn: { provider.next() },
            writeStdout: { capture.append($0) },
            writeStderr: { _ in },
            cjkEnabledFn: { false }
        )
        _ = reader.readInput(prompt: "axion> ", continuationPrompt: "...> ")
        let output = capture.getOutput()
        #expect(output.contains("axion> "))
        #expect(output.contains("...> "))
    }
}
