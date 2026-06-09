import Foundation
import OpenAgentSDK

// MARK: - Types

struct TGStreamingConfig: Sendable {
    let typingEnabled: Bool
    let typingInterval: TimeInterval

    static let `default` = TGStreamingConfig(
        typingEnabled: true,
        typingInterval: 4.0
    )
}

// MARK: - TGStreamingController

actor TGStreamingController {

    // MARK: - State

    private let chatId: Int64
    private var finalized = false
    private var completionReceived = false
    private var completionEventResultText: String?
    private var typingTask: _Concurrency.Task<Void, Never>?

    private let config: TGStreamingConfig
    private let originalTask: String?
    private let deferFinalDelivery: Bool
    private let sendMessage: @Sendable (String, Int64) async -> Int64?
    private let editMessage: @Sendable (Int64, Int64, String) async -> Bool
    private let sendChatAction: @Sendable (Int64, String) async -> Void
    private var toolMessageIds: [String: Int64] = [:]
    private var toolInputs: [String: String] = [:]

    // MARK: - Init

    init(
        chatId: Int64,
        originalTask: String? = nil,
        deferFinalDelivery: Bool = false,
        sendMessage: @escaping @Sendable (String, Int64) async -> Int64?,
        editMessage: @escaping @Sendable (Int64, Int64, String) async -> Bool,
        sendChatAction: @escaping @Sendable (Int64, String) async -> Void = { _, _ in },
        config: TGStreamingConfig = .default
    ) {
        self.chatId = chatId
        self.originalTask = originalTask
        self.deferFinalDelivery = deferFinalDelivery
        self.sendMessage = sendMessage
        self.editMessage = editMessage
        self.sendChatAction = sendChatAction
        self.config = config

        if config.typingEnabled {
            self.typingTask = _Concurrency.Task { [sendChatAction, chatId, interval = config.typingInterval] in
                while !_Concurrency.Task.isCancelled {
                    await sendChatAction(chatId, "typing")
                    try? await _Concurrency.Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            }
        }
    }

    // MARK: - Event Dispatch

    func handle(_ event: any AgentEvent) async {
        switch event {
        case let e as ToolStartedEvent:
            await handleToolStarted(e)
        case let e as ToolStreamingEvent:
            handleToolStreaming(e)
        case let e as ToolCompletedEvent:
            await handleToolCompleted(e)
        case let e as AgentCompletedEvent:
            await handleAgentCompleted(e)
        default:
            break
        }
    }

    // MARK: - Tool Started

    private func handleToolStarted(_ event: ToolStartedEvent) async {
        guard !finalized else { return }

        if let input = event.input { toolInputs[event.toolUseId] = input }
        let text = Self.formatToolStepMessage(toolName: event.toolName, input: event.input)
        if let msgId = await sendMessage(text, chatId) {
            toolMessageIds[event.toolUseId] = msgId
        }
    }

    // MARK: - Tool Streaming

    private func handleToolStreaming(_ event: ToolStreamingEvent) {
        // Suppress raw MCP output — tool progress shown via started/completed markers
    }

    // MARK: - Tool Completed

    private func handleToolCompleted(_ event: ToolCompletedEvent) async {
        guard !finalized else { return }

        let emoji = Self.toolEmoji(event.toolName)
        let resultSuffix: String

        if event.isError {
            resultSuffix = "\n❌ 失败" + (event.output.map { "：\n" + Self.summarizeOutput($0, maxLines: 3) } ?? "")
        } else if let output = event.output, !output.isEmpty {
            let summary = Self.summarizeOutput(output, maxLines: 4)
            if !summary.isEmpty {
                resultSuffix = "\n✅ 结果：\n\(summary)"
            } else {
                resultSuffix = "\n✅ 完成（\(event.durationMs)ms）"
            }
        } else {
            resultSuffix = "\n✅ 完成（\(event.durationMs)ms）"
        }

        let msgId = toolMessageIds.removeValue(forKey: event.toolUseId)
        let savedInput = toolInputs.removeValue(forKey: event.toolUseId)
        if let msgId {
            let original = Self.formatToolStepMessage(toolName: event.toolName, input: savedInput)
            _ = await editMessage(chatId, msgId, original + resultSuffix)
        } else {
            _ = await sendMessage("\(emoji) \(event.toolName)\(resultSuffix)", chatId)
        }
    }

    // MARK: - Agent Completed

    private func handleAgentCompleted(_ event: AgentCompletedEvent) async {
        guard !finalized, !completionReceived else { return }

        stopTypingTimer()

        completionReceived = true
        completionEventResultText = event.resultText

        if deferFinalDelivery {
            return
        }

        await sendFinal(using: event.resultText)
    }

    func finishDeferredRun(authoritativeResultText: String?) async {
        guard deferFinalDelivery, !finalized else { return }
        stopTypingTimer()

        await sendFinal(using: authoritativeResultText ?? completionEventResultText)
    }

    private func sendFinal(using resultText: String?) async {
        finalized = true

        let finalText: String
        if let resultText, !resultText.isEmpty {
            let stripped = TGEventHandler.stripMCPRawIO(from: resultText)
            let answer = stripped.isEmpty ? "✅ 已完成" : stripped
            finalText = Self.formatQuotedFinalAnswer(task: originalTask, answer: answer)
        } else {
            finalText = Self.formatQuotedFinalAnswer(task: originalTask, answer: "✅ 已完成")
        }

        _ = await sendMessage(finalText, chatId)
    }

    // MARK: - Cancel

    func cancel() {
        stopTypingTimer()
        finalized = true
    }

    // MARK: - Typing Timer

    private func stopTypingTimer() {
        typingTask?.cancel()
        typingTask = nil
    }
}
