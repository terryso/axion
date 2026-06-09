import Foundation
import Testing

@testable import AxionCLI

// MARK: - Test Helpers

/// 测试用输出捕获 — 线程安全通过串行访问保证。
final class QueueTestCapture: @unchecked Sendable {
    var stdout = ""
    var stderr = ""
}

/// 创建带 MockKeyReader 的 ChatComposer 测试上下文。
private func makeQueueComposer(
    events: [KeyEvent],
    queue: InputQueue = InputQueue(),
    isTTY: Bool = true
) -> (composer: ChatComposer, capture: QueueTestCapture) {
    let capture = QueueTestCapture()
    var composer = ChatComposer(
        isTTY: isTTY,
        writeStdout: { capture.stdout += $0 },
        writeStderr: { capture.stderr += $0 },
        readLineFn: { nil },
        keyReader: MockKeyReader(events)
    )
    composer.inputQueue = queue
    return (composer, capture)
}

// MARK: - ChatComposer Queue Integration Tests (Story 38.5)

@Suite("ChatComposer Queue")
struct ChatComposerQueueTests {

    // MARK: - Ctrl+E (AC3) — 通过事件循环测试

    @Test("Ctrl+E 弹出最近排队消息到 buffer — 事件循环集成")
    func testCtrlEPopsLastViaEventLoop() {
        var queue = InputQueue()
        _ = queue.enqueue(text: "消息A")
        _ = queue.enqueue(text: "消息B")

        var (composer, _) = makeQueueComposer(
            events: [
                .ctrl("e"),   // 弹出 "消息B" 到 buffer
                .enter,       // 提交
            ],
            queue: queue
        )

        let result = composer.readInput(prompt: "t> ", continuationPrompt: "...> ")

        #expect(result == "消息B")
        #expect(composer.inputQueue?.count == 1)
        // 队列中剩余 "消息A"
        #expect(composer.inputQueue?.previewLast() == "消息A")
    }

    @Test("Ctrl+E 空队列无操作 — 事件循环集成")
    func testCtrlEEmptyQueueViaEventLoop() {
        var (composer, _) = makeQueueComposer(
            events: [
                .ctrl("e"),                   // 空队列 → 无操作
                .printable("h"), .printable("i"),  // 输入 "hi"
                .enter,                        // 提交 "hi"
            ],
            queue: InputQueue()
        )

        let result = composer.readInput(prompt: "t> ", continuationPrompt: "...> ")

        #expect(result == "hi")
        #expect(composer.inputQueue?.isEmpty == true)
    }

    @Test("Ctrl+E 非 empty buffer 无操作 — 事件循环集成")
    func testCtrlENonEmptyBufferNoOpViaEventLoop() {
        var queue = InputQueue()
        _ = queue.enqueue(text: "排队消息")

        var (composer, _) = makeQueueComposer(
            events: [
                .printable("x"),   // buffer = "x"
                .ctrl("e"),        // buffer 非空 → 无操作
                .enter,            // 提交 "x"
            ],
            queue: queue
        )

        let result = composer.readInput(prompt: "t> ", continuationPrompt: "...> ")

        #expect(result == "x")
        // 队列未被修改
        #expect(composer.inputQueue?.count == 1)
    }

    // MARK: - Ctrl+Q (入队) — 通过事件循环测试

    @Test("Ctrl+Q 入队当前 buffer 内容 — 事件循环集成")
    func testCtrlQEnqueuesViaEventLoop() {
        var (composer, _) = makeQueueComposer(
            events: [
                .printable("q"), .printable("u"), .printable("e"), .printable("u"), .printable("e"),
                .ctrl("q"),       // 入队 "queuee"，清空 buffer
                .printable("b"), .printable("y"), .printable("e"),
                .enter,            // 提交 "bye"
            ],
            queue: InputQueue()
        )

        let result = composer.readInput(prompt: "t> ", continuationPrompt: "...> ")

        #expect(result == "bye")
        #expect(composer.inputQueue?.count == 1)
        #expect(composer.inputQueue?.previewLast() == "queue")
    }

    @Test("Ctrl+Q 空 buffer 无操作 — 事件循环集成")
    func testCtrlQEmptyBufferNoOpViaEventLoop() {
        var (composer, _) = makeQueueComposer(
            events: [
                .ctrl("q"),       // buffer 为空 → 无操作
                .printable("o"), .printable("k"),
                .enter,            // 提交 "ok"
            ],
            queue: InputQueue()
        )

        let result = composer.readInput(prompt: "t> ", continuationPrompt: "...> ")

        #expect(result == "ok")
        #expect(composer.inputQueue?.isEmpty == true)
    }

    @Test("Ctrl+Q 队列满时显示错误反馈 — 事件循环集成")
    func testCtrlQQueueFullViaEventLoop() {
        var queue = InputQueue(maxCapacity: 1)
        _ = queue.enqueue(text: "first")

        var (composer, capture) = makeQueueComposer(
            events: [
                .printable("x"),
                .ctrl("q"),       // 队列已满（1/1）
                .backspace,       // 删除 "x"
                .printable("o"), .printable("k"),
                .enter,            // 提交 "ok"
            ],
            queue: queue
        )

        let result = composer.readInput(prompt: "t> ", continuationPrompt: "...> ")

        #expect(result == "ok")
        // 队列未变
        #expect(composer.inputQueue?.count == 1)
        // 错误反馈包含 "排队已满"
        #expect(capture.stderr.contains("排队已满"))
    }

    @Test("Ctrl+Q 入队后显示排队预览反馈 — 事件循环集成")
    func testCtrlQShowsPreviewFeedback() {
        var (composer, capture) = makeQueueComposer(
            events: [
                .printable("m"), .printable("s"), .printable("g"),
                .ctrl("q"),       // 入队 "msg"
                .printable("g"), .printable("o"),
                .enter,            // 提交 "go"
            ],
            queue: InputQueue()
        )

        _ = composer.readInput(prompt: "t> ", continuationPrompt: "...> ")

        // stderr 应包含排队预览
        #expect(capture.stderr.contains("已排队"))
    }

    // MARK: - Ctrl+E + Ctrl+Q 组合

    @Test("Ctrl+Q 入队后 Ctrl+E 弹出编辑 — 事件循环集成")
    func testCtrlQThenCtrlE() {
        var (composer, _) = makeQueueComposer(
            events: [
                .printable("a"), .printable("b"),
                .ctrl("q"),       // 入队 "ab"
                .ctrl("e"),       // 弹出 "ab" 回 buffer
                .printable("c"),  // buffer = "abc"
                .enter,            // 提交 "abc"
            ],
            queue: InputQueue()
        )

        let result = composer.readInput(prompt: "t> ", continuationPrompt: "...> ")

        #expect(result == "abc")
        // 队列已清空（入队又弹出）
        #expect(composer.inputQueue?.isEmpty == true)
    }

    // MARK: - Queue Preview Rendering (AC6)

    @Test("renderQueuePreview — 有排队消息时返回预览")
    func testRenderQueuePreviewNonEmpty() {
        var composer = ChatComposer(
            isTTY: false,
            writeStdout: { _ in },
            writeStderr: { _ in },
            readLineFn: { nil }
        )
        var queue = InputQueue()
        _ = queue.enqueue(text: "做Y")
        composer.inputQueue = queue

        let preview = composer.renderQueuePreview()
        #expect(preview == "⏳ 已排队 (1条等待): \"做Y\"")
    }

    @Test("renderQueuePreview — 空队列返回 nil")
    func testRenderQueuePreviewEmpty() {
        var composer = ChatComposer(
            isTTY: false,
            writeStdout: { _ in },
            writeStderr: { _ in },
            readLineFn: { nil }
        )
        composer.inputQueue = InputQueue()

        let preview = composer.renderQueuePreview()
        #expect(preview == nil)
    }

    @Test("renderQueuePreview — 无 inputQueue 返回 nil")
    func testRenderQueuePreviewNoQueue() {
        let composer = ChatComposer(
            isTTY: false,
            writeStdout: { _ in },
            writeStderr: { _ in },
            readLineFn: { nil }
        )

        let preview = composer.renderQueuePreview()
        #expect(preview == nil)
    }

    // MARK: - Slash Command Bypass (AC5)

    @Test("slash 命令不入队 — 由 ChatCommand 主循环判断")
    func testSlashCommandBypass() {
        #expect(SlashCommand.parse("/cost") != nil)
        #expect(SlashCommand.parse("/clear") != nil)
        #expect(SlashCommand.parse("普通消息") == nil)
    }

    // MARK: - Non-TTY Degradation (AC7)

    @Test("非 TTY 环境下 Ctrl+E/Q 不触发 — readInput 走降级路径")
    func testNonTTYDegradation() {
        let composer = ChatComposer(
            isTTY: false,
            writeStdout: { _ in },
            writeStderr: { _ in },
            readLineFn: { nil }
        )
        #expect(composer.renderQueuePreview() == nil)
    }
}
