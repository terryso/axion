import Foundation
import OpenAgentSDK

// MARK: - Types

enum TGStreamSegment {
    case llm
    case tool(name: String)
    case final
}

enum TGStreamingTransport {
    case edit
    case append
    case off
}

struct TGStreamingConfig: Sendable {
    let editInterval: TimeInterval
    let bufferThreshold: Int
    let transport: TGStreamingTransport
    let freshFinalAfter: TimeInterval

    static let `default` = TGStreamingConfig(
        editInterval: 0.8,
        bufferThreshold: 24,
        transport: .edit,
        freshFinalAfter: 60
    )
}

// MARK: - TGStreamingController

actor TGStreamingController {

    // MARK: - State

    private let chatId: Int64
    private var previewMessageId: Int64?
    private var previewCreatedAt: Date?
    private var bufferedText: String = ""
    private var renderedPreview: String = ""
    private var currentSegment: TGStreamSegment = .llm
    private var lastEditAt: Date = .distantPast
    private var retryAfterUntil: Date = .distantPast
    private var transport: TGStreamingTransport
    private var toolNameMap: [String: String] = [:]
    private var finalized = false
    private var consecutive429Count = 0
    private var segmentParts: [String] = []

    private let config: TGStreamingConfig
    private let sendMessage: @Sendable (String, Int64) async -> Int64?
    private let editMessage: @Sendable (Int64, Int64, String) async -> Bool

    // MARK: - Init

    init(
        chatId: Int64,
        sendMessage: @escaping @Sendable (String, Int64) async -> Int64?,
        editMessage: @escaping @Sendable (Int64, Int64, String) async -> Bool,
        config: TGStreamingConfig = .default
    ) {
        self.chatId = chatId
        self.sendMessage = sendMessage
        self.editMessage = editMessage
        self.config = config
        self.transport = config.transport
    }

    // MARK: - Event Dispatch

    func handle(_ event: any AgentEvent) async {
        switch event {
        case let e as LLMTokenStreamEvent:
            await handleLLMTokenStream(e)
        case let e as ToolStartedEvent:
            handleToolStarted(e)
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

    // MARK: - LLM Token Stream

    private func handleLLMTokenStream(_ event: LLMTokenStreamEvent) async {
        guard !finalized else { return }

        let wasFirstChunk = previewCreatedAt == nil

        // On first chunk, create preview bubble
        if wasFirstChunk {
            let previewText = "⏳ 思考中..."
            let msgId = await sendMessage(previewText, chatId)
            if let msgId { previewMessageId = msgId }
            previewCreatedAt = Date()
            lastEditAt = Date()
        }

        bufferedText += event.chunk
        segmentParts.append(event.chunk)

        // Don't flush on the same call as the first chunk — we just sent the preview
        guard !wasFirstChunk else { return }

        let shouldFlush: Bool
        if bufferedText.count >= config.bufferThreshold {
            shouldFlush = true
        } else {
            let now = Date()
            shouldFlush = now.timeIntervalSince(lastEditAt) >= config.editInterval
                && now >= retryAfterUntil
        }

        if shouldFlush {
            await flushBuffer()
        }
    }

    // MARK: - Tool Started

    private func handleToolStarted(_ event: ToolStartedEvent) {
        toolNameMap[event.toolUseId] = event.toolName
    }

    // MARK: - Tool Streaming

    private func handleToolStreaming(_ event: ToolStreamingEvent) {
        guard !finalized else { return }

        let toolName = toolNameMap[event.toolUseId] ?? event.toolUseId

        // Switch segment if needed
        if case .tool(let name) = currentSegment, name == toolName {
            // Same tool, continue
        } else {
            currentSegment = .tool(name: toolName)
        }

        bufferedText += event.chunk
        segmentParts.append(event.chunk)
    }

    // MARK: - Tool Completed

    private func handleToolCompleted(_ event: ToolCompletedEvent) async {
        guard !finalized else { return }

        let durationSec = String(format: "%.1f", Double(event.durationMs) / 1000.0)
        let statusEmoji = event.isError ? "❌" : "✓"
        let toolName = event.toolName
        let finalizeLine = "\n\(statusEmoji) \(toolName) (\(durationSec)s)\n"

        // Flush any pending buffer first
        if !bufferedText.isEmpty {
            await flushBuffer()
        }

        // Append tool finalize marker
        renderedPreview += finalizeLine
        bufferedText = finalizeLine

        await performEdit()

        // Reset segment for next LLM text
        currentSegment = .llm
        segmentParts = []
    }

    // MARK: - Agent Completed

    private func handleAgentCompleted(_ event: AgentCompletedEvent) async {
        guard !finalized else { return }

        // Flush any remaining buffer
        if !bufferedText.isEmpty {
            await flushBuffer()
        }

        finalized = true

        // Build final text
        var finalText = ""
        if let resultText = event.resultText, !resultText.isEmpty {
            let trimmed = TGEventHandler.extractLastResultSection(from: resultText)
            finalText = "✅ 任务完成 (\(event.totalSteps) 步, \(event.durationMs / 1000)s)\n\n\(trimmed)"
        } else {
            finalText = "✅ 任务完成 (\(event.totalSteps) 步, \(event.durationMs / 1000)s)"
        }

        // Check freshFinalAfter — if preview is stale, send new message
        let shouldSendFresh: Bool
        if let createdAt = previewCreatedAt {
            shouldSendFresh = Date().timeIntervalSince(createdAt) > config.freshFinalAfter
        } else {
            shouldSendFresh = true
        }

        if shouldSendFresh || transport != .edit {
            // Adapter handles formatting + splitting
            _ = await sendMessage(finalText, chatId)
            return
        }

        // Try editing the existing preview with final content
        if let msgId = previewMessageId {
            let success = await editMessage(chatId, msgId, finalText)
            if success {
                return
            }
            // Edit failed — fall through to send new message
        }

        // Fallback: send as new message(s)
        _ = await sendMessage(finalText, chatId)
    }

    // MARK: - Cancel

    func cancel() {
        finalized = true
        bufferedText = ""
        segmentParts = []
    }

    // MARK: - Set Preview Message ID

    func setPreviewMessageId(_ id: Int64) {
        previewMessageId = id
    }

    // MARK: - Flush Buffer

    private func flushBuffer() async {
        guard !bufferedText.isEmpty else { return }
        renderedPreview += bufferedText
        let content = bufferedText
        bufferedText = ""
        segmentParts = []

        await performEditWithContent(content)
    }

    private func performEdit() async {
        guard !renderedPreview.isEmpty else { return }
        await performEditWithContent(renderedPreview)
    }

    private func performEditWithContent(_ content: String) async {
        let now = Date()
        guard now >= retryAfterUntil else { return }
        guard now.timeIntervalSince(lastEditAt) >= config.editInterval else { return }

        // Build the full preview text
        let displayText: String
        if previewMessageId == nil {
            displayText = "⏳ 思考中...\n\(content)"
        } else {
            displayText = content
        }

        if transport == .edit, let msgId = previewMessageId {
            let success = await editMessage(chatId, msgId, displayText)
            if success {
                consecutive429Count = 0
                lastEditAt = Date()
            }
        } else {
            // Append mode: send as new message
            let msgId = await sendMessage(displayText, chatId)
            if previewMessageId == nil { previewMessageId = msgId }
        }
    }

    /// Handle a 429 error from editMessage.
    func handle429(retryAfter: TimeInterval?) {
        consecutive429Count += 1
        if let retryAfter {
            retryAfterUntil = Date().addingTimeInterval(retryAfter)
        } else {
            retryAfterUntil = Date().addingTimeInterval(1.0)
        }

        if consecutive429Count >= 3 {
            transport = .append
        }
    }

    /// Handle permanent edit failure — degrade to append-only.
    func handlePermanentFailure() {
        transport = .append
    }
}
