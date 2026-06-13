import Foundation
import Testing

@testable import AxionCLI

/// E2E tests for InputQueue FIFO flow.
///
/// Tests the queuing behavior that the REPL uses when users type ahead
/// while the agent is busy. Pure struct — no API needed.
@Suite("InputQueue Flow E2E")
struct InputQueueFlowE2ETests {

    // MARK: - FIFO Order

    @Test("FIFO: enqueue A then B, dequeue returns A first")
    func fifoOrder() {
        var queue = InputQueue()

        let resultA = queue.enqueue(text: "消息A")
        #expect(resultA == .success(position: 1),
               "First enqueue should succeed at position 1")

        let resultB = queue.enqueue(text: "消息B")
        #expect(resultB == .success(position: 2),
               "Second enqueue should succeed at position 2")

        let first = queue.dequeue()
        #expect(first?.text == "消息A", "Should dequeue A first (FIFO)")

        let second = queue.dequeue()
        #expect(second?.text == "消息B", "Should dequeue B second (FIFO)")

        let empty = queue.dequeue()
        #expect(empty == nil, "Should return nil when empty")
    }

    @Test("FIFO: three messages in correct order")
    func fifoThree() {
        var queue = InputQueue()
        _ = queue.enqueue(text: "first")
        _ = queue.enqueue(text: "second")
        _ = queue.enqueue(text: "third")

        #expect(queue.dequeue()?.text == "first")
        #expect(queue.dequeue()?.text == "second")
        #expect(queue.dequeue()?.text == "third")
        #expect(queue.dequeue() == nil)
    }

    // MARK: - Capacity

    @Test("capacity: default max is 5")
    func defaultCapacity() {
        var queue = InputQueue()
        for i in 1...5 {
            let result = queue.enqueue(text: "msg\(i)")
            #expect(result == .success(position: i),
                   "Message \(i) should succeed")
        }

        let overflow = queue.enqueue(text: "msg6")
        #expect(overflow == .queueFull(currentCount: 5),
               "6th message should fail with queueFull")
    }

    @Test("capacity: custom maxCapacity")
    func customCapacity() {
        var queue = InputQueue(maxCapacity: 3)
        for i in 1...3 {
            _ = queue.enqueue(text: "msg\(i)")
        }

        let overflow = queue.enqueue(text: "msg4")
        #expect(overflow == .queueFull(currentCount: 3),
               "Should fail when custom capacity reached")
    }

    @Test("capacity: dequeue frees space")
    func dequeueFreesSpace() {
        var queue = InputQueue(maxCapacity: 2)
        _ = queue.enqueue(text: "A")
        _ = queue.enqueue(text: "B")

        // Full
        let full = queue.enqueue(text: "C")
        #expect(full == .queueFull(currentCount: 2))

        // Dequeue one
        _ = queue.dequeue()

        // Now can enqueue
        let result = queue.enqueue(text: "C")
        #expect(result == .success(position: 2),
               "Should succeed after dequeue freed space")
    }

    // MARK: - Duplicate Detection

    @Test("duplicate: identical to last message is rejected")
    func duplicateRejection() {
        var queue = InputQueue()
        _ = queue.enqueue(text: "相同消息")

        let dup = queue.enqueue(text: "相同消息")
        #expect(dup == .duplicate(text: "相同消息"),
               "Should reject duplicate of last message")
    }

    @Test("duplicate: different messages are allowed")
    func differentMessagesAllowed() {
        var queue = InputQueue()
        _ = queue.enqueue(text: "消息1")

        let result = queue.enqueue(text: "消息2")
        #expect(result == .success(position: 2),
               "Different messages should be allowed")
    }

    @Test("duplicate: after dequeue, same text is allowed again")
    func afterDequeueSameTextAllowed() {
        var queue = InputQueue()
        _ = queue.enqueue(text: "消息")
        _ = queue.dequeue()

        let result = queue.enqueue(text: "消息")
        #expect(result == .success(position: 1),
               "Same text should be allowed after previous was dequeued")
    }

    // MARK: - Preview

    @Test("preview: empty queue returns nil")
    func previewEmpty() {
        let queue = InputQueue()
        #expect(queue.previewSummary() == nil, "Empty queue should have no preview")
    }

    @Test("preview: single message")
    func previewSingle() {
        var queue = InputQueue()
        _ = queue.enqueue(text: "你好世界")

        let preview = queue.previewSummary()
        #expect(preview != nil, "Should have preview")
        #expect(preview?.contains("1条等待") == true, "Should show 1 message waiting")
        #expect(preview?.contains("你好世界") == true, "Should show message preview")
    }

    @Test("preview: multiple messages shows count and last")
    func previewMultiple() {
        var queue = InputQueue()
        _ = queue.enqueue(text: "第一条消息")
        _ = queue.enqueue(text: "第二条消息")
        _ = queue.enqueue(text: "最新消息")

        let preview = queue.previewSummary()
        #expect(preview?.contains("3条等待") == true, "Should show 3 messages waiting")
        #expect(preview?.contains("最新消息") == true, "Should show last message preview")
    }

    @Test("preview: long message is truncated to 40 chars")
    func previewTruncation() {
        var queue = InputQueue()
        let longMsg = String(repeating: "a", count: 60)
        _ = queue.enqueue(text: longMsg)

        let preview = queue.previewSummary()
        #expect(preview?.contains("...") == true, "Should truncate with ...")
    }

    // MARK: - Remove Last

    @Test("removeLast: pops from end of queue")
    func removeLastFromEnd() {
        var queue = InputQueue()
        _ = queue.enqueue(text: "A")
        _ = queue.enqueue(text: "B")
        _ = queue.enqueue(text: "C")

        let removed = queue.removeLast()
        #expect(removed?.text == "C", "Should remove last (C)")

        // Verify remaining order
        #expect(queue.dequeue()?.text == "A")
        #expect(queue.dequeue()?.text == "B")
        #expect(queue.dequeue() == nil)
    }

    @Test("removeLast: single element queue")
    func removeLastSingle() {
        var queue = InputQueue()
        _ = queue.enqueue(text: "only")

        let removed = queue.removeLast()
        #expect(removed?.text == "only", "Should remove the only element")
        #expect(queue.isEmpty, "Queue should be empty")
    }

    @Test("removeLast: empty queue returns nil")
    func removeLastEmpty() {
        var queue = InputQueue()
        #expect(queue.removeLast() == nil, "Should return nil for empty queue")
    }

    // MARK: - Count & IsEmpty

    @Test("count and isEmpty track correctly")
    func countAndIsEmpty() {
        var queue = InputQueue()
        #expect(queue.isEmpty, "New queue should be empty")
        #expect(queue.count == 0, "New queue should have count 0")

        _ = queue.enqueue(text: "msg1")
        #expect(!queue.isEmpty, "Should not be empty after enqueue")
        #expect(queue.count == 1)

        _ = queue.enqueue(text: "msg2")
        #expect(queue.count == 2)

        _ = queue.dequeue()
        #expect(queue.count == 1)

        _ = queue.dequeue()
        #expect(queue.isEmpty, "Should be empty after dequeuing all")
        #expect(queue.count == 0)
    }

    // MARK: - Timestamp

    @Test("queued message has timestamp")
    func queuedMessageHasTimestamp() {
        var queue = InputQueue()
        let before = Date()
        _ = queue.enqueue(text: "test")
        let after = Date()

        let msg = queue.dequeue()
        #expect(msg != nil, "Should dequeue a message")
        #expect(msg!.timestamp >= before, "Timestamp should be >= before enqueue")
        #expect(msg!.timestamp <= after, "Timestamp should be <= after enqueue")
    }
}
