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
        private var _chatActions: [(chatId: Int64, action: String)] = []

        var sentMessages: [(text: String, chatId: Int64)] {
            lock.lock(); defer { lock.unlock() }
            return _sentMessages
        }
        var chatActions: [(chatId: Int64, action: String)] {
            lock.lock(); defer { lock.unlock() }
            return _chatActions
        }

        func appendSend(text: String, chatId: Int64) {
            lock.lock(); _sentMessages.append((text, chatId)); lock.unlock()
        }
        func appendChatAction(chatId: Int64, action: String) {
            lock.lock(); _chatActions.append((chatId, action)); lock.unlock()
        }
    }

    private func makeController(
        chatId: Int64 = 123,
        log: CallLog,
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
            editMessage: { _, _, _ in false },
            sendChatAction: { chatId, action in
                log.appendChatAction(chatId: chatId, action: action)
            },
            config: config
        )
    }

    // MARK: - LLM token stream is typing-only (no preview)

    @Test("LLMTokenStreamEvent does not create any message")
    func llmTokenStreamCreatesNoMessage() async {
        let log = CallLog()
        let controller = makeController(log: log)

        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "Hello"))
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: " World"))

        #expect(log.sentMessages.isEmpty)
    }

    // MARK: - Tool step messages

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

    @Test("Tool start formats shell command as inline code")
    func toolStartFormatsShellCommand() async {
        let log = CallLog()
        let controller = makeController(log: log)

        await controller.handle(ToolStartedEvent(
            sessionId: nil,
            toolName: "Bash",
            toolUseId: "tu-1",
            input: #"{"command":"curl -s \"wttr.in/Guangzhou?format=j1\""}"#
        ))

        #expect(log.sentMessages.count == 1)
        #expect(log.sentMessages[0].text == #"💻 Bash: `curl -s "wttr.in/Guangzhou?format=j1"`"#)
    }

    @Test("Tool streaming output is suppressed")
    func toolStreamingSuppressed() async {
        let log = CallLog()
        let controller = makeController(log: log)

        await controller.handle(ToolStartedEvent(
            sessionId: nil, toolName: "Bash", toolUseId: "tu-1", input: nil
        ))

        await controller.handle(ToolStreamingEvent(
            sessionId: nil, toolUseId: "tu-1", chunk: "raw output line 1\n"
        ))
        await controller.handle(ToolStreamingEvent(
            sessionId: nil, toolUseId: "tu-1", chunk: "raw output line 2\n"
        ))

        let allText = log.sentMessages.map(\.text).joined()
        #expect(!allText.contains("raw output line"))
    }

    @Test("Tool completed does not emit extra message")
    func toolCompletedDoesNotEmitExtraMessage() async {
        let log = CallLog()
        let controller = makeController(log: log)

        await controller.handle(ToolStartedEvent(
            sessionId: nil, toolName: "Bash", toolUseId: "tu-1", input: nil
        ))
        await controller.handle(ToolCompletedEvent(
            sessionId: nil, toolUseId: "tu-1", toolName: "Bash",
            durationMs: 500, isError: false
        ))

        #expect(log.sentMessages.count == 1)
    }

    // MARK: - Agent completed sends final answer

    @Test("AgentCompleted sends final answer as new message")
    func agentCompletedSendsFinalAnswer() async {
        let log = CallLog()
        let controller = makeController(log: log, originalTask: "广州明天天气")

        await controller.handle(AgentCompletedEvent(
            sessionId: nil, totalSteps: 2, durationMs: 1_500,
            resultText: "广州明天多云。"
        ))

        let lastMsg = log.sentMessages.last?.text ?? ""
        #expect(lastMsg == "> 广州明天天气\n\n广州明天多云。")
    }

    @Test("AgentCompleted cleans noisy result text")
    func agentCompletedCleansResultText() async {
        let log = CallLog()
        let controller = makeController(log: log, originalTask: "广州明天天气")

        let noisyResult = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://weather.example.com"}

        Output:
        webReader_result_summary: {"text":{"forecast":"sunny"}}

        广州明天多云，气温 26°C 到 32°C。
        [结果] 广州明天多云，气温 26°C 到 32°C。
        """

        await controller.handle(AgentCompletedEvent(
            sessionId: nil, totalSteps: 2, durationMs: 1_500,
            resultText: noisyResult
        ))

        let finalMsg = log.sentMessages.last?.text ?? ""
        // stripMCPRawIO removes MCP I/O but keeps [结果] and narrative lines
        #expect(finalMsg == "> 广州明天天气\n\n广州明天多云，气温 26°C 到 32°C。\n[结果] 广州明天多云，气温 26°C 到 32°C。")
        #expect(!finalMsg.contains("Built-in Tool"))
        #expect(!finalMsg.contains("result_summary"))
    }

    @Test("Full flow: tool steps then final answer")
    func fullFlowToolStepsThenFinalAnswer() async {
        let log = CallLog()
        let controller = makeController(log: log, originalTask: "帮我压缩一下视频")

        // LLM thinking (no message)
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "thinking..."))

        // Tool step
        await controller.handle(ToolStartedEvent(
            sessionId: nil, toolName: "Bash", toolUseId: "tu-1",
            input: #"{"command":"ffmpeg -i input.mp4 output.mp4"}"#
        ))

        // LLM output (no message — typing indicator only)
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "成功"))

        // Agent completes
        await controller.handle(AgentCompletedEvent(
            sessionId: nil, totalSteps: 3, durationMs: 5_000,
            resultText: "压缩完成"
        ))

        // Only 2 messages: tool step + final answer (no preview)
        #expect(log.sentMessages.count == 2)
        #expect(log.sentMessages[0].text == "💻 Bash: `ffmpeg -i input.mp4 output.mp4`")
        #expect(log.sentMessages[1].text == "> 帮我压缩一下视频\n\n压缩完成")
    }

    // MARK: - Deferred final delivery

    @Test("Deferred final delivery waits for authoritative response")
    func deferredFinalDeliveryWaits() async {
        let log = CallLog()
        let config = TGStreamingConfig(typingEnabled: false, typingInterval: 4.0)
        let controller = makeController(
            log: log, originalTask: "广州未来5天的天气",
            deferFinalDelivery: true, config: config
        )

        await controller.handle(AgentCompletedEvent(
            sessionId: nil, totalSteps: 2, durationMs: 1_500,
            resultText: "旧任务结果"
        ))

        #expect(log.sentMessages.isEmpty)

        await controller.finishDeferredRun(authoritativeResultText: "未来5天以阵雨和多云为主。")

        let finalMsg = log.sentMessages.last?.text ?? ""
        #expect(finalMsg == "> 广州未来5天的天气\n\n未来5天以阵雨和多云为主。")
    }

    // MARK: - Cancel

    @Test("Cancel discards all state and stops further events")
    func cancelDiscardsState() async {
        let log = CallLog()
        let controller = makeController(log: log)

        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "buffered"))
        await controller.cancel()

        let countBefore = log.sentMessages.count
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "after cancel"))
        #expect(log.sentMessages.count == countBefore)
    }

    // MARK: - Typing indicator

    @Test("Typing action sent on controller init")
    func typingSentOnInit() async {
        let log = CallLog()
        let config = TGStreamingConfig(typingEnabled: true, typingInterval: 0.05)
        let _ = makeController(log: log, config: config)

        try? await _Concurrency.Task.sleep(nanoseconds: 80_000_000)

        let actions = log.chatActions
        #expect(actions.count >= 1)
        #expect(actions[0].action == "typing")
    }

    @Test("Typing continues during LLM token stream")
    func typingContinuesDuringStream() async {
        let log = CallLog()
        let config = TGStreamingConfig(typingEnabled: true, typingInterval: 0.05)
        let controller = makeController(log: log, config: config)

        try? await _Concurrency.Task.sleep(nanoseconds: 80_000_000)

        // Send LLM tokens — typing should NOT stop
        await controller.handle(LLMTokenStreamEvent(sessionId: nil, chunk: "Hello"))

        try? await _Concurrency.Task.sleep(nanoseconds: 120_000_000)

        let actionsAfter = log.chatActions.count
        #expect(actionsAfter >= 3) // Still firing during streaming
    }

    @Test("Typing stops after AgentCompleted")
    func typingStopsAfterCompletion() async {
        let log = CallLog()
        let config = TGStreamingConfig(typingEnabled: true, typingInterval: 0.05)
        let controller = makeController(log: log, config: config)

        try? await _Concurrency.Task.sleep(nanoseconds: 80_000_000)

        await controller.handle(AgentCompletedEvent(
            sessionId: nil, totalSteps: 1, durationMs: 1_000,
            resultText: "Done"
        ))

        let actionsAtCompletion = log.chatActions.count

        try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
        let actionsAfter = log.chatActions.count
        #expect(actionsAfter == actionsAtCompletion)
    }

    @Test("Typing disabled when typingEnabled is false")
    func typingDisabledWhenConfigFalse() async {
        let log = CallLog()
        let config = TGStreamingConfig(typingEnabled: false, typingInterval: 0.05)
        let _ = makeController(log: log, config: config)

        try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
        #expect(log.chatActions.isEmpty)
    }

    @Test("Typing timer cancelled on cancel()")
    func typingCancelledOnCancel() async {
        let log = CallLog()
        let config = TGStreamingConfig(typingEnabled: true, typingInterval: 0.05)
        let controller = makeController(log: log, config: config)

        try? await _Concurrency.Task.sleep(nanoseconds: 80_000_000)
        await controller.cancel()

        let actionsAtCancel = log.chatActions.count

        try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
        let actionsAfter = log.chatActions.count
        #expect(actionsAfter == actionsAtCancel)
    }

    // MARK: - Empty/null result

    @Test("Empty result text shows completed message")
    func emptyResultShowsCompleted() async {
        let log = CallLog()
        let controller = makeController(log: log, originalTask: "do stuff")

        await controller.handle(AgentCompletedEvent(
            sessionId: nil, totalSteps: 1, durationMs: 1_000,
            resultText: ""
        ))

        let msg = log.sentMessages.last?.text ?? ""
        #expect(msg == "> do stuff\n\n✅ 已完成")
    }

    @Test("Nil result text shows completed message")
    func nilResultShowsCompleted() async {
        let log = CallLog()
        let controller = makeController(log: log, originalTask: "do stuff")

        await controller.handle(AgentCompletedEvent(
            sessionId: nil, totalSteps: 1, durationMs: 1_000,
            resultText: nil
        ))

        let msg = log.sentMessages.last?.text ?? ""
        #expect(msg == "> do stuff\n\n✅ 已完成")
    }

    @Test("No original task shows answer directly")
    func noOriginalTaskShowsAnswerDirectly() async {
        let log = CallLog()
        let controller = makeController(log: log)

        await controller.handle(AgentCompletedEvent(
            sessionId: nil, totalSteps: 1, durationMs: 1_000,
            resultText: "Here is the answer"
        ))

        let msg = log.sentMessages.last?.text ?? ""
        #expect(msg == "Here is the answer")
    }
}
