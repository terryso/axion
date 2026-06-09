import Testing
@testable import AxionCLI

@Suite("ChatComposer History")
struct ChatComposerHistoryTests {

    // MARK: - Test Helpers

    /// 创建带历史记录的 composer
    private func makeHistoryComposer(
        events: [KeyEvent],
        history: [String] = [],
        isTTY: Bool = true
    ) -> (composer: ChatComposer, capture: OutputCapture) {
        let capture = OutputCapture()
        var composer = ChatComposer(
            isTTY: isTTY,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { capture.nextLine() },
            keyReader: MockKeyReader(events)
        )
        composer.history = history
        return (composer: composer, capture: capture)
    }

    // MARK: - AC1: Up/Down 历史导航

    @Test("AC1: Up 回填历史消息")
    func upFillsHistory() {
        var (composer, _) = makeHistoryComposer(
            events: [.up, .enter],
            history: ["previous message"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "previous message")
    }

    @Test("AC1: Up/Down 边界 — Down 回到空")
    func upDownBoundary() {
        var (composer, _) = makeHistoryComposer(
            events: [.up, .down, .enter],
            history: ["msg1"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "")
    }

    @Test("AC1: Up 多次回填更旧历史")
    func upMultipleHistory() {
        var (composer, _) = makeHistoryComposer(
            events: [.up, .up, .enter],
            history: ["oldest", "middle", "newest"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "middle")
    }

    @Test("AC1: Up 到达边界不再移动")
    func upBoundary() {
        var (composer, _) = makeHistoryComposer(
            events: [.up, .up, .up, .enter],
            history: ["oldest", "newest"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "oldest")
    }

    @Test("AC1: 非空 buffer 不触发历史导航")
    func nonEmptyBufferNoHistory() {
        var (composer, _) = makeHistoryComposer(
            events: [.printable("x"), .up, .enter],
            history: ["previous message"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "x")
    }

    // MARK: - AC2/AC4: Ctrl+R 搜索 → Enter 采纳

    @Test("AC2/AC4: Ctrl+R 进入搜索 → 输入 query → Enter 采纳")
    func ctrlRSearchAndAccept() {
        var (composer, capture) = makeHistoryComposer(
            events: [
                .ctrl("r"),
                .printable("g"),
                .printable("i"),
                .printable("t"),
                .enter
            ],
            history: ["hello world", "git commit", "git push"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "git push")
        #expect(capture.stderr.contains("reverse-i-search"))
    }

    // MARK: - AC5: Esc 取消恢复草稿

    @Test("AC5: Ctrl+R 搜索 → Esc 取消恢复原始草稿")
    func ctrlRCancelRestoreDraft() {
        var (composer, _) = makeHistoryComposer(
            events: [
                .printable("a"),
                .ctrl("r"),
                .printable("h"),
                .escape,
                .backspace,
                .enter
            ],
            history: ["hello"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "")
    }

    // MARK: - AC3: 搜索无匹配

    @Test("AC3: Ctrl+R 搜索无匹配 → 显示 no match")
    func ctrlRNoMatch() {
        var (composer, capture) = makeHistoryComposer(
            events: [
                .ctrl("r"),
                .printable("z"),
                .printable("z"),
                .escape,
                .enter               // Esc 恢复空 draft → enter 提交 ""
            ],
            history: ["hello world"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "")
        #expect(capture.stderr.contains("no match"))
    }

    // MARK: - AC3: Ctrl+R 翻页

    @Test("AC3: Ctrl+R 翻页跳到更旧匹配")
    func ctrlRPageOlder() {
        var (composer, _) = makeHistoryComposer(
            events: [
                .ctrl("r"),
                .printable("g"),
                .ctrl("r"),
                .enter
            ],
            history: ["git commit", "git push"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "git commit")
    }

    // MARK: - AC8: 非 TTY 降级

    @Test("AC8: 非 TTY 降级无快捷键")
    func nonTTYNoShortcuts() {
        var (composer, capture) = makeHistoryComposer(
            events: [],
            history: ["previous"],
            isTTY: false
        )
        capture.queuedLines = ["user input"]
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "user input")
    }

    // MARK: - AC5: Ctrl+C 取消搜索

    @Test("AC5: Ctrl+R 搜索 → Ctrl+C 取消")
    func ctrlRCancelWithCtrlC() {
        var (composer, _) = makeHistoryComposer(
            events: [
                .ctrl("r"),
                .printable("h"),
                .ctrl("c")
            ],
            history: ["hello"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == nil)
    }

    // MARK: - AC4: Enter 采纳搜索结果

    @Test("AC4: Enter 采纳搜索结果")
    func acceptSearchResult() {
        var (composer, _) = makeHistoryComposer(
            events: [
                .ctrl("r"),
                .printable("h"),
                .enter
            ],
            history: ["hello"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "hello")
    }

    // MARK: - AC1: 编辑操作重置历史导航

    @Test("AC1: 输入字符重置历史导航状态")
    func editResetsHistory() {
        var (composer, _) = makeHistoryComposer(
            events: [
                .up,
                .printable("x"),
                .enter
            ],
            history: ["msg"]
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "msgx")
    }

    // MARK: - AC6: Ctrl+G 外部编辑器

    @Test("AC6: Ctrl+G 未设置编辑器 → 显示提示")
    func ctrlGNoEditor() {
        var (composer, capture) = makeHistoryComposer(
            events: [.ctrl("g"), .enter],
            history: []
        )
        composer.injectedEditorLauncher = ExternalEditorLauncher(
            envVar: { _ in nil },
            createTempFile: { _ in nil },
            readFile: { _ in nil },
            deleteFile: { _ in },
            launchProcess: { _, _ in nil },
            restoreTerminal: { },
            reEnterRawMode: { }
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "")
        #expect(capture.stderr.contains("VISUAL 或 EDITOR"))
    }

    @Test("AC6: Ctrl+G 触发外部编辑器 → 回填")
    func ctrlGEditorFillsBuffer() {
        var (composer, _) = makeHistoryComposer(
            events: [.ctrl("g"), .enter],
            history: []
        )
        composer.injectedEditorLauncher = ExternalEditorLauncher(
            envVar: { _ in "vim" },
            createTempFile: { _ in "/tmp/test.md" },
            readFile: { _ in "edited by vim" },
            deleteFile: { _ in },
            launchProcess: { _, _ in 0 },
            restoreTerminal: { },
            reEnterRawMode: { }
        )
        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")
        #expect(result == "edited by vim")
    }
}
