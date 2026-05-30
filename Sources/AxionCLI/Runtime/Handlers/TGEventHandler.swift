import Foundation
import OpenAgentSDK

/// Pushes task execution progress and results to Telegram.
///
/// One instance per TG task — `chatId` is injected at init time.
/// Non-TG tasks (HTTP API / CLI) do not create this handler.
actor TGEventHandler: EventHandler {
    let identifier = "telegram-push"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        ToolStartedEvent.self,
        ToolCompletedEvent.self,
        AgentCompletedEvent.self,
        AgentFailedEvent.self,
        ReviewResultEvent.self,
    ]

    let chatId: Int64
    private let sendMessage: @Sendable (String, Int64) async -> Void
    private var lastPushTime: Date = .distantPast
    private let pushInterval: TimeInterval = 5.0
    private var stepCount: Int = 0
    private var pendingInputs: [String: String] = [:]

    init(chatId: Int64, sendMessage: @escaping @Sendable (String, Int64) async -> Void) {
        self.chatId = chatId
        self.sendMessage = sendMessage
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        switch event {
        case let started as ToolStartedEvent:
            await handleToolStarted(started)
        case let toolEvent as ToolCompletedEvent:
            await handleToolCompleted(toolEvent)
        case let completedEvent as AgentCompletedEvent:
            await handleCompleted(completedEvent)
        case let failedEvent as AgentFailedEvent:
            await handleFailed(failedEvent)
        case let reviewEvent as ReviewResultEvent:
            await handleReviewResult(reviewEvent)
        default:
            break
        }
    }

    private func handleToolStarted(_ event: ToolStartedEvent) async {
        if let input = event.input, !input.isEmpty {
            pendingInputs[event.toolUseId] = input
        }
    }

    private func handleToolCompleted(_ event: ToolCompletedEvent) async {
        stepCount += 1
        let now = Date()
        guard now.timeIntervalSince(lastPushTime) >= pushInterval else {
            pendingInputs.removeValue(forKey: event.toolUseId)
            return
        }
        lastPushTime = now

        let statusEmoji = event.isError ? "❌" : "✓"
        let input = pendingInputs.removeValue(forKey: event.toolUseId)
        let detail = summarizeToolInput(toolName: event.toolName, input: input)
        let message = "步骤 \(stepCount): \(detail) (\(event.durationMs)ms) \(statusEmoji)"
        await sendMessage(message, chatId)
    }

    private func summarizeToolInput(toolName: String, input: String?) -> String {
        guard let input, !input.isEmpty else { return toolName }
        // For JSON input, try to extract the meaningful field
        if toolName == "Bash", let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let command = json["command"] as? String {
            return "Bash: \(command.prefix(80))"
        }
        // For other tools, show truncated input
        let truncated = String(input.prefix(80))
        return "\(toolName): \(truncated)"
    }

    private func handleCompleted(_ event: AgentCompletedEvent) async {
        var result = "✅ 任务完成 (\(event.totalSteps) 步, \(event.durationMs / 1000)s)"
        if let text = event.resultText, !text.isEmpty {
            // In persistent sessions the agent may narrate stale observations
            // from previous tasks before addressing the current one.  Extract
            // only the last "[结果]" section so the TG completion message
            // contains the current task's outcome, not old history.
            let trimmed = Self.extractLastResultSection(from: text)
            result += "\n\n\(trimmed)"
        }
        await sendMessage(result, chatId)
    }

    /// Returns the section after the second-to-last `[结果]` line,
    /// which corresponds to the current task's outcome in a resumed session.
    /// Falls back to the full text when fewer than 2 `[结果]` markers are found.
    static func extractLastResultSection(from text: String) -> String {
        let marker = "[结果]"
        var markerPositions: [String.Index] = []
        var searchStart = text.startIndex
        while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
            markerPositions.append(range.lowerBound)
            searchStart = range.upperBound
        }

        guard markerPositions.count >= 2 else { return text }

        // Find the end of the line containing the second-to-last marker
        let secondLastPos = markerPositions[markerPositions.count - 2]
        let afterMarker = text[secondLastPos...]
        let lineEnd = afterMarker.firstIndex(of: "\n") ?? text.endIndex

        // Start from the character after the newline
        let start = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        guard start < text.endIndex else { return text }

        return String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleFailed(_ event: AgentFailedEvent) async {
        let message = "❌ 任务失败: \(event.error)"
        await sendMessage(message, chatId)
    }

    private func handleReviewResult(_ event: ReviewResultEvent) async {
        guard event.success else {
            await sendMessage("⚠️ 后台审查失败", chatId)
            return
        }
        guard !event.memoryChanges.isEmpty || !event.skillChanges.isEmpty else { return }

        var parts: [String] = []
        if !event.memoryChanges.isEmpty {
            parts.append("新增 \(event.memoryChanges.count) 条记忆")
        }
        if !event.skillChanges.isEmpty {
            parts.append("更新 \(event.skillChanges.count) 个技能")
        }
        let message = "📊 审查完成: \(parts.joined(separator: ", "))"
        await sendMessage(message, chatId)
    }
}
