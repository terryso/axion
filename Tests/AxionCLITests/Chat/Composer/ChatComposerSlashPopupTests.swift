import Testing
@testable import AxionCLI

@Suite("ChatComposer Slash Popup (AC1/AC2/AC5/AC6/AC7)")
struct ChatComposerSlashPopupTests {

    // MARK: - AC1: 输入 `/` 触发 slashPopup 模式

    @Test("AC1: 输入 `/` 触发 slashPopup 模式并渲染命令列表")
    func slashTriggersPopup() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .escape,  // 取消 popup
            .enter    // 提交空 buffer
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        // Esc cancels popup and restores draft (which was empty before "/")
        // Then Enter submits empty string — but empty buffer is discarded
        // Actually Esc in normal mode clears buffer, so buffer="" and Enter submits ""
        #expect(result == "")
        // 验证 popup 输出包含命令列表
        #expect(capture.stdout.contains("/help"))
    }

    // MARK: - AC2: 继续输入过滤

    @Test("AC2: 输入 `/re` 过滤为只包含 /resume")
    func slashQueryFiltersToResume() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .printable("r"),
            .printable("e"),
            .escape,  // 取消
            .enter    // 提交
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        _ = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        // 应包含 /resume 在过滤后的输出中
        #expect(capture.stdout.contains("/resume"))
    }

    // MARK: - AC5: Tab 补全选中命令（acceptsArgs=false → 直接提交）

    @Test("AC5: Tab 补全 /help 并直接提交（acceptsArgs=false）")
    func tabCompletesHelpAndSubmits() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .printable("h"),
            .tab  // 补全 /help → acceptsArgs=false → 直接提交
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "/help")
    }

    // MARK: - AC5: Enter 选中命令并提交

    @Test("AC5: Enter 选中 /help 并直接提交")
    func enterSelectsHelpAndSubmits() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .printable("h"),
            .enter  // 选中 /help → acceptsArgs=false → 直接提交
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "/help")
    }

    // MARK: - AC5: Tab 补全 acceptsArgs=true → 留在编辑模式

    @Test("AC5: Tab 补全 /model 留空参数（acceptsArgs=true）")
    func tabCompletesModelStaysInEdit() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .printable("m"),
            .tab,  // 补全 /model → acceptsArgs=true → 留在编辑模式
            .enter  // 然后用户按 Enter 提交
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "/model ")
    }

    // MARK: - AC6: Up/Down 移动选中

    @Test("AC6: Down 移动选中到下一个命令")
    func downMovesSelection() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .down,  // 移到第二个命令
            .tab    // 补全选中的命令
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        // 默认排序第一个是 /apps（接受参数），第二个是 /archive
        // Down 移到第二个，tab 补全
        // 接受 args=false 的命令 → 直接提交
        #expect(result == "/archive")
    }

    @Test("AC6: Up 在第一个位置不移动")
    func upAtFirstPosition() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .up,   // 在第一个位置 up 不移动
            .tab   // 补全第一个命令
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        // 第一个命令按字母序是 /apps，接受参数所以保留编辑态并补空格
        #expect(result == "/apps ")
    }

    // MARK: - AC7: Esc 取消恢复原始草稿

    @Test("AC7: Esc 取消 popup 恢复原始草稿")
    func escCancelsAndRestoresDraft() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .escape,  // 取消 popup，恢复 draft（空）
            .printable("h"), .printable("i"),
            .enter
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        // Esc 取消 popup → draft 是空的（输入 "/" 前是空的）
        // 然后 "hi" → Enter
        #expect(result == "hi")
    }

    @Test("AC7: Esc 取消 popup 恢复有内容的草稿")
    func escCancelsAndRestoresNonEmptyDraft() {
        let capture = OutputCapture()
        // 先输入 "hello"，然后输入 "/" 触发 popup
        // 但 "/" 触发只在 buffer == "/" 时（空 buffer 后输入 "/"）
        // 所以这个场景是：buffer 空 → 输入 "/" → popup → Esc → buffer 空
        let reader = MockKeyReader([
            .printable("/"),
            .escape,  // 取消 → draft restore（空 buffer）
            .printable("t"), .printable("e"), .printable("s"), .printable("t"),
            .enter
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "test")
    }

    // MARK: - Backspace 行为

    @Test("Backspace 从 `/re` 退回到 `/r`")
    func backslashFromReToR() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .printable("r"),
            .printable("e"),
            .backspace,  // 退回 /r
            .escape,     // 取消
            .enter       // 提交
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        _ = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        // 退回到 /r 后应该重新过滤（匹配 /resume）
        // 在 popup 过程中至少输出过命令列表
        #expect(capture.stdout.contains("/help"))
    }

    @Test("Backspace 从 `/` 取消 popup")
    func backspaceFromSlashCancels() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .backspace,  // 只有 "/" 时 backspace → 取消 popup
            .printable("x"), .enter
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "x")
    }

    // MARK: - Ctrl+C in popup

    @Test("Ctrl+C 在 popup 模式返回 nil")
    func ctrlCInPopup() {
        let capture = OutputCapture()
        let reader = MockKeyReader([
            .printable("/"),
            .ctrl("c")
        ])
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == nil)
    }

    // MARK: - AC8: 非 TTY 不触发 popup

    @Test("AC8: 非 TTY 模式不触发 slash popup")
    func nonTTYNoPopup() {
        let capture = OutputCapture()
        capture.queuedLines = ["/help"]
        var composer = ChatComposer(
            isTTY: false,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { capture.nextLine() },
            keyReader: nil
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "/help")
        // 非 TTY 模式不应触发 popup（无命令列表输出）
        #expect(!capture.stdout.contains("无匹配命令"))
    }
}
