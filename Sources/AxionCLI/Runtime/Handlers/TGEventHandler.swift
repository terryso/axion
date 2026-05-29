import Foundation
import OpenAgentSDK

/// Pushes task execution progress and results to Telegram.
///
/// One instance per TG task — `chatId` is injected at init time.
/// Non-TG tasks (HTTP API / CLI) do not create this handler.
actor TGEventHandler: EventHandler {
    let identifier = "telegram-push"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        ToolCompletedEvent.self,
        AgentCompletedEvent.self,
        AgentFailedEvent.self,
    ]

    let chatId: Int64
    private let sendMessage: @Sendable (String, Int64) async -> Void
    private var lastPushTime: Date = .distantPast
    private let pushInterval: TimeInterval = 5.0
    private var stepCount: Int = 0

    init(chatId: Int64, sendMessage: @escaping @Sendable (String, Int64) async -> Void) {
        self.chatId = chatId
        self.sendMessage = sendMessage
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        switch event {
        case let toolEvent as ToolCompletedEvent:
            await handleToolCompleted(toolEvent)
        case let completedEvent as AgentCompletedEvent:
            await handleCompleted(completedEvent)
        case let failedEvent as AgentFailedEvent:
            await handleFailed(failedEvent)
        default:
            break
        }
    }

    private func handleToolCompleted(_ event: ToolCompletedEvent) async {
        stepCount += 1
        let now = Date()
        guard now.timeIntervalSince(lastPushTime) >= pushInterval else { return }
        lastPushTime = now

        let statusEmoji = event.isError ? "❌" : "✓"
        let message = "步骤 \(stepCount): \(event.toolName) (\(event.durationMs)ms) \(statusEmoji)"
        await sendMessage(message, chatId)
    }

    private func handleCompleted(_ event: AgentCompletedEvent) async {
        var result = "✅ 任务完成 (\(event.totalSteps) 步, \(event.durationMs / 1000)s)"
        if let text = event.resultText, !text.isEmpty {
            result += "\n\n\(text)"
        }
        await sendMessage(result, chatId)
    }

    private func handleFailed(_ event: AgentFailedEvent) async {
        let message = "❌ 任务失败: \(event.error)"
        await sendMessage(message, chatId)
    }
}
