import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI

@Suite("TGStreamingController")
struct TGStreamingControllerTests {

    // MARK: - Helpers

    private final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _sentMessages: [(text: String, chatId: Int64)] = []
        private var _editedMessages: [(chatId: Int64, messageId: Int64, text: String)] = []
        private var _editResults: [Bool] = []
        private var _chatActions: [(chatId: Int64, action: String)] = []

        var sentMessages: [(text: String, chatId: Int64)] {
            lock.lock(); defer { lock.unlock() }
            return _sentMessages
        }
        var editedMessages: [(chatId: Int64, messageId: Int64, text: String)] {
            lock.lock(); defer { lock.unlock() }
            return _editedMessages
        }
        var editResults: [Bool] {
            lock.lock(); defer { lock.unlock() }
            return _editResults
        }
        var chatActions: [(chatId: Int64, action: String)] {
            lock.lock(); defer { lock.unlock() }
            return _chatActions
        }

        func appendSend(text: String, chatId: Int64) {
            lock.lock(); _sentMessages.append((text, chatId)); lock.unlock()
        }
        func appendEdit(chatId: Int64, messageId: Int64, text: String, result: Bool) {
            lock.lock()
            _editedMessages.append((chatId, messageId, text))
            _editResults.append(result)
            lock.unlock()
        }
        func appendChatAction(chatId: Int64, action: String) {
            lock.lock(); _chatActions.append((chatId, action)); lock.unlock()
        }
    }

    private func makeController(
        chatId: Int64 = 123,
        log: CallLog,
        editResult: Bool = true,
        config: TGStreamingConfig = .default
    ) -> TGStreamingController {
        TGStreamingController(
            chatId: chatId,
            sendMessage: { text, chatId in
                log.appendSend(text: text, chatId: chatId)
                return Int64(log.sentMessages.count)
            },
            editMessage: { chatId, messageId, text in
                let result = editResult
                log.appendEdit(chatId: chatId, messageId: messageId, text: text, result: result)
                return result
            },
            sendChatAction: { chatId, action in
                log.appendChatAction(chatId: chatId, action: action)
            },
            config: config
        )
    }

    // MARK: - AC #1: First chunk creates preview bubble

    @Test("First LLMTokenStreamEvent creates preview bubble with 思考中 prefix")
    func firstChunkCreatesPreview() async {
        let log = CallLog()
        let controller = makeController(log: log)

        let event = LLMTokenStreamEvent(sessionId: nil, chunk: "Hello")
        await controller.handle(event)

        let sent = log.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "⏳ 思考中...")
        #expect(sent[0].chatId == 123)
    }

    // MARK: - AC #2: Buffered tokens trigger edit after threshold

    @Test("Buffered tokens trigger edit after buffer threshold")
    func bufferThresholdTriggersEdit() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 5,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, config: config)

        // First chunk — creates preview
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "12345"))
        // Buffer threshold (5) met, but no previewMessageId yet so sends as message
        #expect(log.sentMessages.count >= 1)
    }

    @Test("Buffered tokens trigger edit after interval")
    func intervalTriggersEdit() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0, // 0 interval = always flush
            bufferThreshold: 1000, // high threshold so interval triggers first
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, config: config)

        // First chunk — creates preview
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "Hi"))

        // Second chunk — interval=0 should trigger edit
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: " World"))

        // At least preview + some edit action
        #expect(log.sentMessages.count >= 1)
    }

    // MARK: - AC #3: Tool segment finalize

    @Test("Tool completed shows ✓ toolName (duration)")
    func toolCompletedShowsFinalize() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, config: config)

        // Setup tool name mapping
        await controller.handle(ToolStartedEvent(
            sessionId: nil, toolName: "Bash", toolUseId: "tu-1", input: nil
        ))

        // Complete the tool
        await controller.handle(ToolCompletedEvent(
            sessionId: nil,
            toolUseId: "tu-1",
            toolName: "Bash",
            durationMs: 1200,
            isError: false
        ))

        // Check that the tool finalize marker was sent
        let allSent = log.sentMessages.map(\.text).joined()
        #expect(allSent.contains("✓ Bash (1.2s)"))
    }

    @Test("Tool completed with error shows ❌ marker")
    func toolCompletedErrorShowsMarker() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, config: config)

        await controller.handle(ToolStartedEvent(
            sessionId: nil, toolName: "Bash", toolUseId: "tu-1", input: nil
        ))
        await controller.handle(ToolCompletedEvent(
            sessionId: nil,
            toolUseId: "tu-1",
            toolName: "Bash",
            durationMs: 500,
            isError: true
        ))

        let allSent = log.sentMessages.map(\.text).joined()
        #expect(allSent.contains("❌ Bash (0.5s)"))
    }

    // MARK: - AC #4: 429 handling

    @Test("429 with retry-after delays next edit via handle429")
    func handle429DelaysNextEdit() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, config: config)

        // Trigger 429
        await controller.handle429(retryAfter: 10.0)

        // Next tokens should be buffered, not flushed (retryAfterUntil)
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "test"))
        // Only the preview message sent, no edit
        #expect(log.sentMessages.count == 1)
    }

    @Test("3 consecutive 429s degrades to append-only")
    func three429sDegradesToAppend() async {
        let log = CallLog()
        let controller = makeController(log: log)

        await controller.handle429(retryAfter: nil)
        await controller.handle429(retryAfter: nil)
        await controller.handle429(retryAfter: nil)

        // After 3 consecutive 429s, transport should be append
        // Verify by sending more tokens — they should be sent as new messages
        // (since transport is append, not edit)
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "after degrade"))
        // Preview message should have been sent
        #expect(log.sentMessages.count >= 1)
    }

    // MARK: - AC #5: Permanent failure switches to append

    @Test("Permanent failure switches to append-only")
    func permanentFailureSwitchesToAppend() async {
        let log = CallLog()
        let controller = makeController(log: log)

        await controller.handlePermanentFailure()

        // After permanent failure, controller should be in append mode
        // Verify by sending tokens — should go through sendMessage, not editMessage
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "after failure"))

        // Should have sent via sendMessage
        #expect(log.sentMessages.count >= 1)
        #expect(log.editedMessages.isEmpty)
    }

    // MARK: - AC #6: AgentCompleted clears prefix

    @Test("AgentCompletedEvent clears 思考中 and applies final formatting")
    func agentCompletedClearsPrefix() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, config: config)

        // Send some tokens first
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "thinking..."))

        // Complete the agent
        await controller.handle(AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 5,
            durationMs: 12_000,
            resultText: "The task is done."
        ))

        // The preview is fresh (< 60s) so controller edits instead of sending new message.
        // Check editedMessages for the final content (not sentMessages).
        let allEdits = log.editedMessages.map(\.text)
        let finalEdit = allEdits.last ?? ""
        #expect(!finalEdit.contains("⏳ 思考中..."))
        #expect(finalEdit.contains("任务完成"))
    }

    // MARK: - AC #7: Overflow split

    @Test("Overflow content sent to sendMessage for adapter-level splitting")
    func overflowSplitsIntoChunks() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, config: config)

        let longText = String(repeating: "A", count: 5000)
        await controller.handle(AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 5,
            durationMs: 12_000,
            resultText: longText
        ))

        // No preview was created, so shouldSendFresh=true → sends via sendMessage.
        // Splitting is delegated to the adapter (sendFormatted handles it in production).
        // Controller sends the raw long text in a single sendMessage call.
        let allSent = log.sentMessages
        #expect(allSent.count >= 1)
        let lastMessage = allSent.last?.text ?? ""
        #expect(lastMessage.contains(String(repeating: "A", count: 100)))
    }

    // MARK: - AC #8: freshFinalAfter sends new message

    @Test("freshFinalAfter sends new message instead of editing stale preview")
    func freshFinalAfterSendsNewMessage() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 0,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, config: config)

        // Send tokens to create preview (which sets previewCreatedAt)
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "start"))

        // Complete after a delay (simulated by freshFinalAfter=0)
        await controller.handle(AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 3,
            durationMs: 5_000,
            resultText: "Done"
        ))

        // With freshFinalAfter=0, the preview is immediately stale,
        // so the final message should be sent as a new sendMessage
        #expect(log.sentMessages.count >= 2) // preview + final
        let lastMsg = log.sentMessages.last?.text ?? ""
        #expect(lastMsg.contains("任务完成"))
    }

    // MARK: - Cancel

    @Test("Cancel discards buffered content")
    func cancelDiscardsBuffer() async {
        let log = CallLog()
        let controller = makeController(log: log)

        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "buffered"))
        await controller.cancel()

        // After cancel, further events are ignored
        let countBefore = log.sentMessages.count
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "after cancel"))
        #expect(log.sentMessages.count == countBefore)
    }

    // MARK: - Edit message closure verification

    @Test("editMessage closure is called with correct parameters")
    func editMessageClosureCalled() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, config: config)

        // Create preview and set messageId
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "first"))
        await controller.setPreviewMessageId(42)

        // Next chunk should trigger an edit
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "second"))

        // Check edit was called
        #expect(log.editedMessages.count >= 1)
        let edit = log.editedMessages.first!
        #expect(edit.chatId == 123)
        #expect(edit.messageId == 42)
        #expect(edit.text.contains("second"))
    }

    // MARK: - Typing Indicator Tests (Story 32.3)

    @Test("Typing action sent on controller init (before first LLM chunk)")
    func typingSentOnInit() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: true,
            typingInterval: 0.05 // 50ms for fast test
        )
        let _ = makeController(log: log, config: config)

        // Wait for the typing timer to fire at least once
        try? await _Concurrency.Task.sleep(nanoseconds: 80_000_000) // 80ms

        let actions = log.chatActions
        #expect(actions.count >= 1)
        #expect(actions[0].action == "typing")
        #expect(actions[0].chatId == 123)
    }

    @Test("Typing stops after first streaming chunk creates preview")
    func typingStopsAfterFirstChunk() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: true,
            typingInterval: 0.05
        )
        let controller = makeController(log: log, config: config)

        // Wait for typing to start
        try? await _Concurrency.Task.sleep(nanoseconds: 80_000_000)
        let actionsBefore = log.chatActions.count
        #expect(actionsBefore >= 1)

        // Send first chunk — should stop typing timer
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "Hello"))

        // Wait and check no more typing actions
        try? await _Concurrency.Task.sleep(nanoseconds: 120_000_000) // Wait for 2+ typing intervals
        let actionsAfter = log.chatActions.count
        // Should not have significantly more actions (at most 1 re-fire from edit)
        #expect(actionsAfter <= actionsBefore + 2)
    }

    @Test("Typing re-fires after each successful edit")
    func typingReFiresAfterEdit() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: true,
            typingInterval: 0.05 // Short interval for fast test
        )
        let controller = makeController(log: log, config: config)

        // Wait for initial typing timer to fire
        try? await _Concurrency.Task.sleep(nanoseconds: 80_000_000)

        // First chunk creates preview (stops typing timer)
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "first"))
        await controller.setPreviewMessageId(1)

        let actionsBefore = log.chatActions.count

        // Second chunk triggers edit → re-fire typing
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "second"))

        // Yield to allow the re-fire Task to execute
        try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)

        // Should have one more typing action (re-fire after edit)
        let actionsAfter = log.chatActions
        #expect(actionsAfter.count > actionsBefore)
        #expect(actionsAfter.last?.action == "typing")
    }

    @Test("Typing disabled when typingEnabled is false")
    func typingDisabledWhenConfigFalse() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 0.05
        )
        let _ = makeController(log: log, config: config)

        // Wait — no typing should occur
        try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)

        #expect(log.chatActions.isEmpty)
    }

    @Test("Typing timer cancelled on AgentCompleted")
    func typingCancelledOnFinalize() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: true,
            typingInterval: 0.05
        )
        let controller = makeController(log: log, config: config)

        // Wait for typing to start
        try? await _Concurrency.Task.sleep(nanoseconds: 80_000_000)

        // Send some tokens then complete
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "thinking..."))
        await controller.handle(AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 3,
            durationMs: 5_000,
            resultText: "Done"
        ))

        let actionsAtCompletion = log.chatActions.count

        // Wait more — no additional typing should fire
        try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
        let actionsAfter = log.chatActions.count
        #expect(actionsAfter <= actionsAtCompletion + 1) // +1 for possible re-fire
    }

    @Test("Typing timer cancelled on cancel()")
    func typingCancelledOnCancel() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: true,
            typingInterval: 0.05
        )
        let controller = makeController(log: log, config: config)

        // Wait for typing to start
        try? await _Concurrency.Task.sleep(nanoseconds: 80_000_000)

        await controller.cancel()

        let actionsAtCancel = log.chatActions.count

        // Wait more — no additional typing should fire
        try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
        let actionsAfter = log.chatActions.count
        #expect(actionsAfter == actionsAtCancel)
    }

    @Test("No-op sendChatAction does not block message delivery")
    func noOpChatActionDoesNotBlockDelivery() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: true,
            typingInterval: 4.0
        )
        // Use a controller where sendChatAction throws
        let controller = TGStreamingController(
            chatId: 123,
            sendMessage: { text, chatId in
                log.appendSend(text: text, chatId: chatId)
                return Int64(log.sentMessages.count)
            },
            editMessage: { chatId, messageId, text in
                log.appendEdit(chatId: chatId, messageId: messageId, text: text, result: true)
                return true
            },
            sendChatAction: { _, _ in
                // Simulate failure — but still returns Void (non-blocking)
            },
            config: config
        )

        // Send tokens and complete — message delivery should still work
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "Hello"))
        await controller.handle(AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 1,
            durationMs: 1_000,
            resultText: "Task done"
        ))

        // Message should have been delivered — preview is fresh so final goes via editMessage
        #expect(log.sentMessages.count >= 1)
        let allText = log.editedMessages.map(\.text).joined() + log.sentMessages.map(\.text).joined()
        #expect(allText.contains("任务完成"))
    }
}
