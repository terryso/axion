import Foundation

// MARK: - QueuedMessage

/// 排队消息 — 用户在 agent 执行期间预先输入的消息。
struct QueuedMessage: Equatable {
    /// 消息文本
    let text: String
    /// 入队时间戳
    let timestamp: Date
}

// MARK: - EnqueueResult

/// 入队操作结果。
enum EnqueueResult: Equatable {
    /// 成功入队，返回在队列中的位置（1-based）
    case success(position: Int)
    /// 队列已满，返回当前队列大小
    case queueFull(currentCount: Int)
    /// 重复消息（与队尾完全相同），返回重复的文本
    case duplicate(text: String)
}

// MARK: - InputQueue

/// 输入队列 — FIFO + 容量限制 + 预览摘要。
///
/// 纯 struct，零外部依赖，零 I/O。
/// 所有操作返回值类型，由 ChatCommand 主循环和 ChatComposer 负责显示。
struct InputQueue {
    /// 排队消息列表（FIFO：index 0 = 队首，先入先出）
    private(set) var messages: [QueuedMessage]

    /// 最大容量（默认 5）
    let maxCapacity: Int

    // MARK: - Init

    init(maxCapacity: Int = 5) {
        self.messages = []
        self.maxCapacity = maxCapacity
    }

    // MARK: - Properties

    /// 队列是否为空
    var isEmpty: Bool { messages.isEmpty }

    /// 当前队列中的消息数量
    var count: Int { messages.count }

    // MARK: - Enqueue (AC1/AC4)

    /// 将消息入队。
    ///
    /// - Returns: `.success(position:)` 成功入队；
    ///            `.queueFull(currentCount:)` 队列已满；
    ///            `.duplicate(text:)` 与队尾完全相同（防止重复入队）。
    mutating func enqueue(text: String) -> EnqueueResult {
        // AC4: 容量检查
        guard count < maxCapacity else {
            return .queueFull(currentCount: count)
        }

        // 重复检测：与队尾消息完全相同时拒绝
        if let last = messages.last, last.text == text {
            return .duplicate(text: text)
        }

        messages.append(QueuedMessage(text: text, timestamp: Date()))
        return .success(position: count)
    }

    // MARK: - Dequeue (AC2)

    /// 弹出队首消息（FIFO）。
    mutating func dequeue() -> QueuedMessage? {
        guard !messages.isEmpty else { return nil }
        return messages.removeFirst()
    }

    // MARK: - Remove Last (AC3 — Ctrl+E 编辑)

    /// 弹出最近一条排队消息（队尾），用于 Ctrl+E 编辑。
    mutating func removeLast() -> QueuedMessage? {
        guard !messages.isEmpty else { return nil }
        return messages.removeLast()
    }

    // MARK: - Preview (AC6)

    /// 返回排队预览摘要。
    ///
    /// 格式：
    /// - 1 条：`⏳ 已排队 (1条等待): "消息预览..."`
    /// - N 条：`⏳ 已排队 (N条等待): "最近消息预览..."`
    /// - 空队列：`nil`
    func previewSummary() -> String? {
        guard !messages.isEmpty else { return nil }
        let previewText = previewLast() ?? ""
        if count == 1 {
            return "⏳ 已排队 (1条等待): \"\(previewText)\""
        }
        return "⏳ 已排队 (\(count)条等待): \"\(previewText)\""
    }

    /// 返回最近一条排队消息的截断预览（最多 40 字符）。
    func previewLast() -> String? {
        guard let last = messages.last else { return nil }
        if last.text.count <= 40 {
            return last.text
        }
        return String(last.text.prefix(40)) + "..."
    }
}
