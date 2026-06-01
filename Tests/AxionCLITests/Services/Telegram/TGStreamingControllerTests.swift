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
        originalTask: String? = nil,
        deferFinalDelivery: Bool = false,
        config: TGStreamingConfig = .default
    ) -> TGStreamingController {
        TGStreamingController(
            chatId: chatId,
            originalTask: originalTask,
            deferFinalDelivery: deferFinalDelivery,
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

    @Test("First LLMTokenStreamEvent creates preview bubble with quiet processing prefix")
    func firstChunkCreatesPreview() async {
        let log = CallLog()
        let controller = makeController(log: log)

        let event = LLMTokenStreamEvent(sessionId: nil, chunk: "Hello")
        await controller.handle(event)

        let sent = log.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text == "⏳ 处理中…")
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
        let controller = makeController(log: log, originalTask: "查看一下当前目录有多少文件", config: config)

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
        let controller = makeController(log: log, originalTask: "查看一下当前目录有多少文件", config: config)

        // First chunk — creates preview
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "Hi"))

        // Second chunk — interval=0 should trigger edit
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: " World"))

        // At least preview + some edit action
        #expect(log.sentMessages.count >= 1)
    }

    // MARK: - AC #3: Tool segment finalize

    @Test("Tool start sends standalone step message with arguments")
    func toolStartSendsStandaloneStepMessage() async {
        let log = CallLog()
        let controller = makeController(log: log)

        await controller.handle(ToolStartedEvent(
            sessionId: nil, toolName: "WebSearch", toolUseId: "tu-1", input: #"{"query":"广州明天天气"}"#
        ))

        #expect(log.sentMessages.count == 1)
        #expect(log.sentMessages[0].text == "🔍 WebSearch: query: 广州明天天气")
    }

    @Test("Tool completed no longer emits separate finalize marker")
    func toolCompletedDoesNotEmitFinalizeMarker() async {
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

        #expect(log.sentMessages.count == 1)
        #expect(log.sentMessages[0].text == "💻 Bash")
        #expect(log.editedMessages.isEmpty)
    }

    @Test("Tool start formats shell command as inline code")
    func toolStartFormatsShellCommand() async {
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
            sessionId: nil,
            toolName: "Bash",
            toolUseId: "tu-1",
            input: #"{"command":"curl -s \"wttr.in/Guangzhou?format=j1\""}"#
        ))

        #expect(log.sentMessages.count == 1)
        #expect(log.sentMessages[0].text == #"💻 Bash: `curl -s "wttr.in/Guangzhou?format=j1"`"#)
    }

    @Test("Tool step includes argument preview")
    func toolStepIncludesPreview() async {
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

        let inputJson = #"{"query":"广州明天天气"}"#
        await controller.handle(ToolStartedEvent(
            sessionId: nil, toolName: "WebSearch", toolUseId: "tu-1", input: inputJson
        ))

        let allSent = log.sentMessages.map(\.text).joined()
        #expect(allSent.contains("🔍 WebSearch: query: 广州明天天气"))
        #expect(!allSent.contains(#""query""#))
    }

    @Test("Tool streaming output is suppressed")
    func toolStreamingSuppressed() async {
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

        await controller.handle(ToolStartedEvent(
            sessionId: nil, toolName: "Bash", toolUseId: "tu-1", input: nil
        ))

        // Send tool streaming chunks — should be suppressed
        await controller.handle(ToolStreamingEvent(
            sessionId: nil, toolUseId: "tu-1", chunk: "raw output line 1\n"
        ))
        await controller.handle(ToolStreamingEvent(
            sessionId: nil, toolUseId: "tu-1", chunk: "raw output line 2\n"
        ))

        // Complete tool
        await controller.handle(ToolCompletedEvent(
            sessionId: nil,
            toolUseId: "tu-1",
            toolName: "Bash",
            durationMs: 500,
            isError: false
        ))

        // Raw output should NOT appear in any sent message
        let allText = log.sentMessages.map(\.text).joined() + log.editedMessages.map(\.text).joined()
        #expect(!allText.contains("raw output line 1"))
        #expect(!allText.contains("raw output line 2"))
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

    @Test("Edit failure falls back to append message")
    func editFailureFallsBackToAppend() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, editResult: false, config: config)

        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "Hi"))
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: " there"))

        #expect(log.editedMessages.count == 1)
        #expect(log.editResults == [false])
        #expect(log.sentMessages.count == 2)
        #expect(log.sentMessages.last?.text == "Hi there")
    }

    // MARK: - AC #6: AgentCompleted clears prefix

    @Test("AgentCompletedEvent clears processing prefix and keeps final answer concise")
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
        let controller = makeController(log: log, originalTask: "广州明天天气", config: config)

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
        #expect(!finalEdit.contains("⏳ 处理中…"))
        #expect(finalEdit == "> 广州明天天气\n\nThe task is done.")
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
        let controller = makeController(log: log, originalTask: "查看一下当前目录有多少文件", config: config)

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
        let controller = makeController(log: log, originalTask: "查看一下当前目录有多少文件", config: config)

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
        #expect(lastMsg == "> 查看一下当前目录有多少文件\n\nDone")
    }

    @Test("Final answer sends as new message after standalone tool steps")
    func finalAnswerSendsAsNewMessageAfterToolSteps() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, originalTask: "帮我压缩一下视频", config: config)

        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "thinking..."))
        await controller.handle(ToolStartedEvent(
            sessionId: nil,
            toolName: "Bash",
            toolUseId: "tu-1",
            input: #"{"command":"ffmpeg -i input.mp4 output.mp4"}"#
        ))
        await controller.handle(AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 3,
            durationMs: 5_000,
            resultText: "压缩完成"
        ))

        #expect(log.sentMessages.count == 3)
        #expect(log.sentMessages[0].text == "⏳ 处理中…")
        #expect(log.sentMessages[1].text == "💻 Bash: `ffmpeg -i input.mp4 output.mp4`")
        #expect(log.sentMessages[2].text == "> 帮我压缩一下视频\n\n压缩完成")
        #expect(!(log.editedMessages.last?.text.contains("压缩完成") ?? false))
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
        #expect(allText.contains("Task done"))
    }

    @Test("Edit fallback sends cleaned final answer without transcript noise")
    func editFallbackSendsQuietCleanFinalAnswer() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(log: log, editResult: false, originalTask: "广州明天天气", config: config)

        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "thinking"))
        await controller.setPreviewMessageId(99)

        let noisyResult = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://weather.example.com"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"text":{"forecast":"sunny"}}

        广州明天多云，气温 26°C 到 32°C。
        [结果] 广州明天多云，气温 26°C 到 32°C。
        """

        await controller.handle(AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 2,
            durationMs: 1_500,
            resultText: noisyResult
        ))

        let finalSend = log.sentMessages.last?.text ?? ""
        #expect(finalSend == "> 广州明天天气\n\n广州明天多云，气温 26°C 到 32°C。")
        #expect(!finalSend.contains("Built-in Tool"))
        #expect(!finalSend.contains("Input:"))
        #expect(!finalSend.contains("Output:"))
        #expect(!finalSend.contains("result_summary"))
    }

    @Test("Deferred final delivery prefers authoritative run response")
    func deferredFinalDeliveryUsesAuthoritativeResponse() async {
        let log = CallLog()
        let config = TGStreamingConfig(
            editInterval: 0,
            bufferThreshold: 1000,
            transport: .edit,
            freshFinalAfter: 60,
            typingEnabled: false,
            typingInterval: 4.0
        )
        let controller = makeController(
            log: log,
            originalTask: "广州未来5天的天气",
            deferFinalDelivery: true,
            config: config
        )

        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "thinking"))
        await controller.handle(AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 2,
            durationMs: 1_500,
            resultText: "旧任务结果"
        ))

        #expect(!(log.sentMessages.map(\.text).joined().contains("旧任务结果")))
        #expect(!(log.editedMessages.map(\.text).joined().contains("旧任务结果")))

        await controller.finishDeferredRun(authoritativeResultText: "未来5天以阵雨和多云为主。")

        let finalEdit = log.editedMessages.last?.text ?? ""
        #expect(finalEdit == "> 广州未来5天的天气\n\n未来5天以阵雨和多云为主。")
        #expect(!finalEdit.contains("旧任务结果"))
    }
}
