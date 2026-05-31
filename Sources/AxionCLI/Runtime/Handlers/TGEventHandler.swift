import Foundation
import OpenAgentSDK

/// Pushes task execution progress and results to Telegram.
///
/// One instance per TG task — `chatId` is injected at init time.
/// Non-TG tasks (HTTP API / CLI) do not create this handler.
///
/// Streaming events (LLMTokenStream, ToolStarted, ToolStreaming, ToolCompleted,
/// AgentCompleted) are delegated to a `TGStreamingController` for edit-based
/// live updates. Non-streaming events (AgentFailed, ReviewResult) still send
/// independent messages directly.
actor TGEventHandler: EventHandler {
    let identifier = "telegram-push"
    let subscribedEventTypes: [any AgentEvent.Type] = [
        LLMTokenStreamEvent.self,
        ToolStartedEvent.self,
        ToolStreamingEvent.self,
        ToolCompletedEvent.self,
        AgentCompletedEvent.self,
        AgentFailedEvent.self,
        ReviewResultEvent.self,
        AgentPausedEvent.self,
    ]

    let chatId: Int64
    private let allowedUserId: Int64
    private let sendMessage: @Sendable (String, Int64) async -> Int64?
    private let editMessage: @Sendable (Int64, Int64, String) async -> Bool
    private let sendChatAction: @Sendable (Int64, String) async -> Void
    private let sendMessageWithMarkup: @Sendable (Int64, String, TGInlineKeyboardMarkup?) async -> Int64?
    private let streamingConfig: TGStreamingConfig
    private let sessionStore: TGInteractiveSessionStore?
    private let registerResumeHandle: (@Sendable (String, @Sendable @escaping (String) async -> Void) -> Void)?
    private lazy var streamingController: TGStreamingController = {
        TGStreamingController(
            chatId: chatId,
            sendMessage: sendMessage,
            editMessage: editMessage,
            sendChatAction: sendChatAction,
            config: streamingConfig
        )
    }()

    init(
        chatId: Int64,
        allowedUserId: Int64 = 0,
        sendMessage: @escaping @Sendable (String, Int64) async -> Int64?,
        editMessage: @escaping @Sendable (Int64, Int64, String) async -> Bool = { _, _, _ in false },
        sendChatAction: @escaping @Sendable (Int64, String) async -> Void = { _, _ in },
        streamingConfig: TGStreamingConfig = .default,
        sessionStore: TGInteractiveSessionStore? = nil,
        registerResumeHandle: (@Sendable (String, @Sendable @escaping (String) async -> Void) -> Void)? = nil,
        sendMessageWithMarkup: @escaping @Sendable (Int64, String, TGInlineKeyboardMarkup?) async -> Int64? = { _, _, _ in nil }
    ) {
        self.chatId = chatId
        self.allowedUserId = allowedUserId
        self.sendMessage = sendMessage
        self.editMessage = editMessage
        self.sendChatAction = sendChatAction
        self.streamingConfig = streamingConfig
        self.sessionStore = sessionStore
        self.registerResumeHandle = registerResumeHandle
        self.sendMessageWithMarkup = sendMessageWithMarkup
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        switch event {
        case let failedEvent as AgentFailedEvent:
            await handleFailed(failedEvent)
        case let reviewEvent as ReviewResultEvent:
            await handleReviewResult(reviewEvent)
        case let pausedEvent as AgentPausedEvent:
            await handlePaused(pausedEvent)
        default:
            // All other events go to streaming controller
            await streamingController.handle(event)
        }
    }

    private func handlePaused(_ event: AgentPausedEvent) async {
        guard let store = sessionStore else { return }

        let pendingId = event.pendingId
        let mode: TGInteractionMode = mapPauseReasonToMode(event.reason)

        let keyboard = await store.buildKeyboard(for: mode, pendingId: pendingId)
        let text = "⏸️ Agent 已暂停\n原因: \(event.reason)"

        let msgId = await sendWithReplyMarkup(text: text, replyMarkup: keyboard)
        guard let messageId = msgId else { return }

        await store.register(
            pendingId: pendingId,
            chatId: chatId,
            messageId: messageId,
            mode: mode,
            allowedUserId: allowedUserId,
            onResume: { response in
                // The actual agent.resume() is called via TaskSerialQueue.resumeInteraction.
                // This closure updates the TG message after resume completes.
            }
        )
    }

    private func sendWithReplyMarkup(text: String, replyMarkup: TGInlineKeyboardMarkup) async -> Int64? {
        return await sendMessageWithMarkup(chatId, text, replyMarkup)
    }

    private func mapPauseReasonToMode(_ reason: String) -> TGInteractionMode {
        let lower = reason.lowercased()
        if lower.contains("approve") || lower.contains("approval") || lower.contains("danger") {
            return .approval
        } else if lower.contains("confirm") {
            return .confirm
        } else if lower.contains("clarif") {
            return .clarify
        } else {
            return .approval
        }
    }

    private func handleFailed(_ event: AgentFailedEvent) async {
        await streamingController.cancel()
        let sanitizedError = TGErrorSanitizer.sanitizeForTelegramError(event.error)
        let message = "❌ 任务失败: \(sanitizedError)"
        _ = await sendMessage(message, chatId)
    }

    private func handleReviewResult(_ event: ReviewResultEvent) async {
        guard event.success else {
            _ = await sendMessage("⚠️ 后台审查失败", chatId)
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
        _ = await sendMessage(message, chatId)
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

    /// Strips raw MCP tool I/O sections from text.
    /// Detects blocks by "Input:" marker and strips the preceding header + entire I/O section.
    static func stripMCPRawIO(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var cleanedLines: [String] = []
        var index = 0
        var phase: MCPBlockPhase?
        var sawOutputSeparator = false

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let markerRange = line.range(of: "Built-in Tool:"), isLikelyMCPHeader(in: lines, at: index) {
                let prefix = preservedProsePrefix(before: markerRange.lowerBound, in: line)
                if !prefix.isEmpty {
                    cleanedLines.append(prefix)
                }
                phase = .header
                sawOutputSeparator = false
                index += 1
                continue
            }

            if phase == nil, isLikelyMCPInputStart(in: lines, at: index) {
                phase = .input
                sawOutputSeparator = false
                index += 1
                continue
            }

            guard let currentPhase = phase else {
                cleanedLines.append(line)
                index += 1
                continue
            }

            if trimmed.isEmpty {
                if currentPhase == .output {
                    sawOutputSeparator = true
                }
                index += 1
                continue
            }

            if isExecutingLine(trimmed) {
                index += 1
                continue
            }

            if isInputHeader(trimmed) {
                phase = .input
                sawOutputSeparator = false
                index += 1
                continue
            }

            if isOutputHeader(trimmed) {
                phase = .output
                sawOutputSeparator = false
                index += 1
                continue
            }

            if currentPhase == .output,
               sawOutputSeparator,
               (trimmed.hasPrefix("[结果]") || isLikelyNarrativeLine(trimmed) || isTerminalContentLine(in: lines, at: index)) {
                phase = nil
                sawOutputSeparator = false
                continue
            }

            if isToolResultLine(trimmed) || isStructuredPayloadLine(trimmed) {
                index += 1
                continue
            }

            if trimmed.hasPrefix("[结果]") {
                phase = nil
                sawOutputSeparator = false
                continue
            }

            switch currentPhase {
            case .header:
                index += 1
            case .output:
                if sawOutputSeparator, (isLikelyNarrativeLine(trimmed) || isTerminalContentLine(in: lines, at: index)) {
                    phase = nil
                    sawOutputSeparator = false
                    continue
                }
                index += 1
            case .input:
                index += 1
            }
        }

        var cleaned = cleanedLines.joined(separator: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum MCPBlockPhase {
        case header
        case input
        case output
    }

    private static func isLikelyMCPInputStart(in lines: [String], at index: Int) -> Bool {
        guard index < lines.count else { return false }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard isInputHeader(trimmed) else { return false }

        let lookaheadEnd = min(index + 40, lines.count - 1)
        guard lookaheadEnd > index else { return false }

        for candidateIndex in (index + 1)...lookaheadEnd {
            let candidate = lines[candidateIndex].trimmingCharacters(in: .whitespaces)
            if candidate.contains("Built-in Tool:") { return true }
            if isExecutingLine(candidate) { return true }
            if isOutputHeader(candidate) { return true }
            if isToolResultLine(candidate) { return true }
        }

        return false
    }

    private static func isLikelyMCPHeader(in lines: [String], at index: Int) -> Bool {
        guard index < lines.count else { return false }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("Built-in Tool:") else { return false }
        if trimmed.contains("Z.ai") { return true }

        let lookaheadEnd = min(index + 20, lines.count - 1)
        guard lookaheadEnd > index else { return false }

        for candidateIndex in (index + 1)...lookaheadEnd {
            let candidate = lines[candidateIndex].trimmingCharacters(in: .whitespaces)
            if isInputHeader(candidate) || isOutputHeader(candidate) || isExecutingLine(candidate) || isToolResultLine(candidate) {
                return true
            }
        }

        return false
    }

    private static func isInputHeader(_ line: String) -> Bool {
        line.hasPrefix("Input:")
    }

    private static func isOutputHeader(_ line: String) -> Bool {
        line.hasPrefix("Output:")
    }

    private static func isExecutingLine(_ line: String) -> Bool {
        line.contains("Executing on server...")
    }

    private static func isStructuredPayloadLine(_ line: String) -> Bool {
        guard !line.hasPrefix("[结果]") else { return false }
        if line.hasPrefix("{") || line.hasPrefix("}") { return true }
        if line == "[]" || line == "{}" { return true }
        if line.hasPrefix("[") && (line.contains(":") || line.hasSuffix("]")) { return true }
        if line.hasPrefix("]") { return true }
        if line.hasPrefix("\"") || line == "true" || line == "false" || line == "null" { return true }
        if Double(line) != nil { return true }
        if line.hasPrefix("```") { return true }
        return false
    }

    private static func isToolResultLine(_ line: String) -> Bool {
        if line.contains("_result_summary:") { return true }
        if line.contains("_result:") { return true }
        return false
    }

    private static func preservedProsePrefix(before boundary: String.Index, in line: String) -> String {
        let trimmed = String(line[..<boundary]).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        if let punctuationIndex = trimmed.lastIndex(where: { "。！？!?".contains($0) }) {
            return String(trimmed[...punctuationIndex]).trimmingCharacters(in: .whitespaces)
        }

        if trimmed.contains("Z.ai") || trimmed.count <= 12 {
            return ""
        }

        return trimmed
    }

    /// Strips raw MCP tool I/O then extracts the last result section.
    static func cleanResultText(from text: String) -> String {
        let stripped = stripMCPRawIO(from: text)
        if let markedAnswer = extractLatestMarkedAnswer(from: stripped), !markedAnswer.isEmpty {
            return markedAnswer
        }
        let latest = extractLastResultSection(from: stripped)
        let normalizedLines = latest
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("[结果]") else { return line }
                return trimmed.replacingOccurrences(of: "[结果]", with: "").trimmingCharacters(in: .whitespaces)
            }
        let cleaned = normalizedLines.joined(separator: "\n")
        let collapsed = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractLatestMarkedAnswer(from text: String) -> String? {
        let marker = "[结果]"
        guard let range = text.range(of: marker, options: .backwards) else { return nil }
        let answer = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return answer.isEmpty ? nil : answer
    }

    private static func isLikelyNarrativeLine(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        if line.hasPrefix("[结果]") { return true }
        if line.hasPrefix("#") || line.hasPrefix("- ") || line.hasPrefix("* ") { return true }

        let narrativePunctuation = CharacterSet(charactersIn: "，。：；！？!?")
        if line.rangeOfCharacter(from: narrativePunctuation) != nil {
            return true
        }

        let letterScalars = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return letterScalars.count >= 12
    }

    private static func isTerminalContentLine(in lines: [String], at index: Int) -> Bool {
        guard index < lines.count else { return false }
        for candidateIndex in (index + 1)..<lines.count {
            if !lines[candidateIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
        }
        return true
    }
}
