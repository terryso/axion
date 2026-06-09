import Foundation
import Testing

@testable import AxionCLI

// MARK: - InputQueue Tests

@Suite("InputQueue")
struct InputQueueTests {

    // MARK: - Enqueue / Dequeue FIFO (AC1)

    @Test("入队/出队基本 FIFO")
    func testEnqueueDequeueFIFO() {
        var queue = InputQueue()

        let r1 = queue.enqueue(text: "第一条")
        #expect(r1 == .success(position: 1))

        let r2 = queue.enqueue(text: "第二条")
        #expect(r2 == .success(position: 2))

        #expect(queue.count == 2)
        #expect(!queue.isEmpty)

        // FIFO：先入先出
        let first = queue.dequeue()
        #expect(first?.text == "第一条")

        let second = queue.dequeue()
        #expect(second?.text == "第二条")

        #expect(queue.isEmpty)
        #expect(queue.count == 0)
    }

    @Test("空队列出队返回 nil")
    func testDequeueEmpty() {
        var queue = InputQueue()
        #expect(queue.dequeue() == nil)
    }

    // MARK: - Capacity Limit (AC4)

    @Test("容量限制 — 超出返回 .queueFull")
    func testCapacityLimit() {
        var queue = InputQueue(maxCapacity: 3)

        #expect(queue.enqueue(text: "A") == .success(position: 1))
        #expect(queue.enqueue(text: "B") == .success(position: 2))
        #expect(queue.enqueue(text: "C") == .success(position: 3))

        // 第 4 条应被拒绝
        let result = queue.enqueue(text: "D")
        #expect(result == .queueFull(currentCount: 3))

        // 队列内容不变
        #expect(queue.count == 3)
    }

    @Test("默认容量为 5")
    func testDefaultCapacity() {
        var queue = InputQueue()
        for i in 1...5 {
            #expect(queue.enqueue(text: "msg\(i)") == .success(position: i))
        }
        let result = queue.enqueue(text: "overflow")
        #expect(result == .queueFull(currentCount: 5))
    }

    // MARK: - Duplicate Detection

    @Test("重复消息检测 — 与队尾相同返回 .duplicate")
    func testDuplicateDetection() {
        var queue = InputQueue()

        #expect(queue.enqueue(text: "hello") == .success(position: 1))
        // 相同消息 → duplicate
        let result = queue.enqueue(text: "hello")
        #expect(result == .duplicate(text: "hello"))
        #expect(queue.count == 1)  // 未增加

        // 不同消息 → 成功
        #expect(queue.enqueue(text: "world") == .success(position: 2))

        // 现在队尾是 "world"，再入 "hello" 应该成功
        #expect(queue.enqueue(text: "hello") == .success(position: 3))
    }

    // MARK: - Remove Last (AC3 — Ctrl+E)

    @Test("removeLast 弹出最近一条")
    func testRemoveLast() {
        var queue = InputQueue()
        queue.enqueue(text: "第一条")
        queue.enqueue(text: "第二条")
        queue.enqueue(text: "第三条")

        let removed = queue.removeLast()
        #expect(removed?.text == "第三条")
        #expect(queue.count == 2)

        // 队列顺序不变
        #expect(queue.dequeue()?.text == "第一条")
        #expect(queue.dequeue()?.text == "第二条")
    }

    @Test("removeLast 空队列返回 nil")
    func testRemoveLastEmpty() {
        var queue = InputQueue()
        #expect(queue.removeLast() == nil)
    }

    @Test("removeLast 后继续入队")
    func testRemoveLastThenEnqueue() {
        var queue = InputQueue()
        queue.enqueue(text: "A")
        queue.enqueue(text: "B")

        _ = queue.removeLast()  // 移除 B
        queue.enqueue(text: "C")

        #expect(queue.count == 2)
        #expect(queue.dequeue()?.text == "A")
        #expect(queue.dequeue()?.text == "C")
    }

    // MARK: - Preview Summary (AC6)

    @Test("previewSummary — 1 条消息格式")
    func testPreviewSummaryOne() {
        var queue = InputQueue()
        queue.enqueue(text: "也修复一下测试")

        let summary = queue.previewSummary()
        #expect(summary == "⏳ 已排队 (1条等待): \"也修复一下测试\"")
    }

    @Test("previewSummary — 多条消息格式")
    func testPreviewSummaryMultiple() {
        var queue = InputQueue()
        queue.enqueue(text: "做A")
        queue.enqueue(text: "做B")
        queue.enqueue(text: "做C")

        let summary = queue.previewSummary()
        #expect(summary == "⏳ 已排队 (3条等待): \"做C\"")
    }

    @Test("previewSummary — 空队列返回 nil")
    func testPreviewSummaryEmpty() {
        let queue = InputQueue()
        #expect(queue.previewSummary() == nil)
    }

    // MARK: - Preview Last Truncation (AC6)

    @Test("previewLast — 短文本不截断")
    func testPreviewLastShort() {
        var queue = InputQueue()
        queue.enqueue(text: "短消息")
        #expect(queue.previewLast() == "短消息")
    }

    @Test("previewLast — 超过 40 字符截断")
    func testPreviewLastTruncation() {
        var queue = InputQueue()
        let longText = String(repeating: "A", count: 50)
        queue.enqueue(text: longText)

        let preview = queue.previewLast()
        #expect(preview != nil)
        #expect(preview!.count == 43)  // 40 + "..."
        #expect(preview!.hasSuffix("..."))
    }

    @Test("previewLast — 恰好 40 字符不截断")
    func testPreviewLastExact40() {
        var queue = InputQueue()
        let exact = String(repeating: "X", count: 40)
        queue.enqueue(text: exact)
        #expect(queue.previewLast() == exact)
    }

    @Test("previewLast — 空队列返回 nil")
    func testPreviewLastEmpty() {
        let queue = InputQueue()
        #expect(queue.previewLast() == nil)
    }

    // MARK: - isEmpty / count Properties

    @Test("isEmpty 和 count 属性")
    func testProperties() {
        var queue = InputQueue()
        #expect(queue.isEmpty)
        #expect(queue.count == 0)

        queue.enqueue(text: "msg")
        #expect(!queue.isEmpty)
        #expect(queue.count == 1)

        _ = queue.dequeue()
        #expect(queue.isEmpty)
        #expect(queue.count == 0)
    }

    // MARK: - QueuedMessage

    @Test("QueuedMessage 包含 timestamp")
    func testQueuedMessageTimestamp() {
        var queue = InputQueue()
        let before = Date()
        queue.enqueue(text: "test")
        let after = Date()

        let msg = queue.dequeue()
        #expect(msg != nil)
        #expect(msg!.timestamp >= before)
        #expect(msg!.timestamp <= after)
    }

    // MARK: - Edge Cases

    @Test("入队空字符串 — 允许（由调用方决定是否入队空消息）")
    func testEnqueueEmptyString() {
        var queue = InputQueue()
        let result = queue.enqueue(text: "")
        #expect(result == .success(position: 1))
    }

    @Test("dequeue 全部后可重新入队")
    func testFullCycle() {
        var queue = InputQueue(maxCapacity: 2)

        queue.enqueue(text: "A")
        queue.enqueue(text: "B")
        // 已满
        #expect(queue.enqueue(text: "C") == .queueFull(currentCount: 2))

        // 消费一条
        _ = queue.dequeue()
        // 现在有空间了
        #expect(queue.enqueue(text: "C") == .success(position: 2))
    }
}
