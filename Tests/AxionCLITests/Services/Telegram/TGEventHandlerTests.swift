import Testing
import Foundation
import OpenAgentSDK
import AxionCore

@testable import AxionCLI

@Suite("TGEventHandler")
struct TGEventHandlerTests {
    /// Collects (message, chatId) pairs sent via the sendMessage closure.
    private final class MessageCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var _messages: [(message: String, chatId: Int64)] = []

        var messages: [(message: String, chatId: Int64)] {
            lock.lock()
            defer { lock.unlock() }
            return _messages
        }

        func append(_ message: String, chatId: Int64) {
            lock.lock()
            _messages.append((message, chatId))
            lock.unlock()
        }

        func clear() {
            lock.lock()
            _messages.removeAll()
            lock.unlock()
        }
    }

    private func makeContext() -> EventHandlerContext {
        EventHandlerContext(
            sessionId: "test-session",
            config: .default,
            eventBus: nil,
            externallyModified: false,
            externallyModifiedFlag: nil,
            takeoverEvent: nil,
            runCompleteContext: nil,
            sessionStore: SessionStore(sessionsDir: "/tmp/axion-test-sessions")
        )
    }

    private func makeHandler(
        chatId: Int64 = 123,
        collector: MessageCollector
    ) -> TGEventHandler {
        TGEventHandler(chatId: chatId, sendMessage: { message, chatId in
            collector.append(message, chatId: chatId)
            return nil
        })
    }

    // MARK: - Subscribed event types (streaming + non-streaming)

    @Test("Subscribes to correct event types including streaming")
    func subscribedEventTypes() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)

        let types = await handler.subscribedEventTypes.map { $0 }
        let typeNames = Set(types.map { String(describing: $0) })

        #expect(typeNames.contains("LLMTokenStreamEvent"))
        #expect(typeNames.contains("ToolStartedEvent"))
        #expect(typeNames.contains("ToolStreamingEvent"))
        #expect(typeNames.contains("ToolCompletedEvent"))
        #expect(typeNames.contains("AgentCompletedEvent"))
        #expect(typeNames.contains("AgentFailedEvent"))
        #expect(typeNames.contains("ReviewResultEvent"))
        #expect(typeNames.contains("AgentPausedEvent"))
        #expect(types.count == 8)
    }

    // MARK: - extractLastResultSection

    @Test("extractLastResultSection returns full text when no [结果] marker")
    func extractResultNoMarker() {
        let text = "Task completed successfully."
        #expect(TGEventHandler.extractLastResultSection(from: text) == text)
    }

    @Test("extractLastResultSection returns full text when single [结果] marker")
    func extractResultSingleMarker() {
        let text = "Some work done.\n[结果] Task completed."
        #expect(TGEventHandler.extractLastResultSection(from: text) == text)
    }

    @Test("extractLastResultSection trims stale observations from previous session task")
    func extractResultTrimsStaleSection() {
        let text = """
        计算器已经打开了，看起来之前输入过 5+3，显示 8。
        ✅ 计算结果：5 + 3 = 8
        [结果] 计算器已打开，5+3=8 计算完成

        先清除之前的计算，然后点击 5、+、9、8、=
        ✅ 计算完成：5 + 98 = 103
        从计算器确认：5+98=103
        [结果] 计算器已计算 5+98=103
        """
        let result = TGEventHandler.extractLastResultSection(from: text)
        #expect(!result.contains("5+3=8"))
        #expect(!result.contains("计算器已经打开了"))
        #expect(result.contains("5+98=103"))
        #expect(result.contains("[结果] 计算器已计算 5+98=103"))
    }

    // MARK: - AgentFailedEvent pushes error (no API key)

    @Test("AgentFailedEvent pushes error message without API key")
    func agentFailedPushesError() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = AgentFailedEvent(
            sessionId: nil,
            error: "Connection timeout",
            stepsCompleted: 3
        )
        await handler.handle(event, context: context)

        let messages = collector.messages
        #expect(messages.count == 1)
        #expect(messages[0].message.contains("任务失败"))
        // Error sanitizer maps timeout to Chinese
        #expect(messages[0].message.contains("命令执行超时"))
    }

    @Test("AgentFailedEvent sanitizes API keys from error")
    func agentFailedSanitizesKeys() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = AgentFailedEvent(
            sessionId: nil,
            error: "Invalid key sk-abc123def456ghi789jkl012mno345 in request",
            stepsCompleted: 1
        )
        await handler.handle(event, context: context)

        let messages = collector.messages
        #expect(messages.count == 1)
        #expect(!messages[0].message.contains("sk-abc123"))
        #expect(messages[0].message.contains("[REDACTED_KEY]"))
    }

    @Test("AgentFailedEvent sanitizes file paths from error")
    func agentFailedSanitizesPaths() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = AgentFailedEvent(
            sessionId: nil,
            error: "Error reading /Users/nick/.config/axion/secrets.json",
            stepsCompleted: 1
        )
        await handler.handle(event, context: context)

        let messages = collector.messages
        #expect(messages.count == 1)
        #expect(!messages[0].message.contains("Users/nick"))
        #expect(messages[0].message.contains("secrets.json"))
    }

    // MARK: - Streaming delegation: ToolCompletedEvent no longer sends step message

    @Test("ToolCompletedEvent is delegated to streaming controller, not direct push")
    func toolCompletedDelegatedToStreaming() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = ToolCompletedEvent(
            sessionId: nil,
            toolUseId: "tu-1",
            toolName: "screenshot",
            durationMs: 230,
            isError: false
        )
        await handler.handle(event, context: context)

        // Streaming controller handles it — the handler itself does NOT send step messages
        // The controller will send a preview/edit with tool finalize marker
        // For this test, we verify the handler doesn't send old-style step messages
        let messages = collector.messages
        // The streaming controller sends "⏳ 思考中..." on first event, then tool finalize
        #expect(messages.count >= 1)
        // Should NOT contain old "步骤 N:" format
        for msg in messages {
            #expect(!msg.message.contains("步骤"))
        }
    }

    // MARK: - ReviewResultEvent handling

    @Test("ReviewResultEvent with changes pushes review summary")
    func reviewResultWithChangesPushes() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = ReviewResultEvent(
            summary: "review done",
            memoryChanges: ["mem-1", "mem-2"],
            skillChanges: ["skill-1"],
            success: true,
            durationMs: 500,
            sessionId: "s-1"
        )
        await handler.handle(event, context: context)

        #expect(collector.messages.count == 1)
        #expect(collector.messages[0].message.contains("审查完成"))
        #expect(collector.messages[0].message.contains("2 条记忆"))
        #expect(collector.messages[0].message.contains("1 个技能"))
    }

    @Test("ReviewResultEvent failure pushes warning message")
    func reviewResultFailurePushesWarning() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = ReviewResultEvent(
            summary: "failed",
            memoryChanges: [],
            skillChanges: [],
            success: false,
            durationMs: 100,
            sessionId: "s-fail"
        )
        await handler.handle(event, context: context)

        #expect(collector.messages.count == 1)
        #expect(collector.messages[0].message.contains("审查失败"))
    }

    @Test("ReviewResultEvent success with no changes does not push")
    func reviewResultSuccessNoChangesNoPush() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = ReviewResultEvent(
            summary: "nothing to change",
            memoryChanges: [],
            skillChanges: [],
            success: true,
            durationMs: 50,
            sessionId: "s-noop"
        )
        await handler.handle(event, context: context)

        #expect(collector.messages.isEmpty)
    }

    // MARK: - stripMCPRawIO

    @Test("stripMCPRawIO extracts answer after last MCP block")
    func stripMCPRemovesToolIO() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://example.com","return_format":"markdown"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"text": {"title": "Example"}}

        根据以上数据，答案是 42。

        [结果] 答案是 42
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(!result.contains("🌐"))
        #expect(!result.contains("Input:"))
        #expect(!result.contains("Output:"))
        #expect(!result.contains("webReader_result"))
        #expect(!result.contains("Built-in Tool"))
        #expect(result.contains("根据以上数据"))
        #expect(result.contains("[结果] 答案是 42"))
    }

    @Test("stripMCPRawIO handles multiple tool blocks with interleaved model text")
    func stripMCPHandlesMultipleBlocks() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://a.com"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"text": {"title": "A"}}

                                                数据似乎不太对。🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://b.com"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"text": {"title": "B"}}

                                                根据以上数据，最终答案如下。

        [结果] 最终答案
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(!result.contains("🌐"))
        #expect(!result.contains("webReader"))
        #expect(!result.contains("Built-in Tool"))
        #expect(result.contains("最终答案如下"))
        #expect(result.contains("[结果] 最终答案"))
    }

    @Test("stripMCPRawIO handles leading-whitespace tool blocks")
    func stripMCPHandlesIndentedBlocks() {
        let text = """
        some header
                                                🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://example.com"}

        *Executing on server...*
                                                    Output:
        webReader_result_summary: {"text": {"title": "Example"}}

        根据以上数据，答案是 42。
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(!result.contains("🌐"))
        #expect(!result.contains("webReader"))
        #expect(!result.contains("Built-in Tool"))
        #expect(result.contains("some header"))
        #expect(result.contains("根据以上数据"))
    }

    @Test("stripMCPRawIO preserves text without tool blocks")
    func stripMCPPreservesPlain() {
        let text = "这是一段普通文本，没有任何工具输出。"
        #expect(TGEventHandler.stripMCPRawIO(from: text) == text)
    }

    @Test("stripMCPRawIO preserves text with Input: but no Output: (no MCP blocks)")
    func stripMCPFalsePositiveGuard() {
        let text = """
        让我解释一下。

        Input:
        这个字段接受 JSON 格式。

        没有对应的 Output 行，所以不应被当作 MCP 块删除。

        实际答案在这里。
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(result.contains("让我解释一下"))
        #expect(result.contains("Input:"))
        #expect(result.contains("实际答案在这里"))
    }

    @Test("stripMCPRawIO preserves literal Built-in Tool mention without MCP markers")
    func stripMCPLiteralHeaderGuard() {
        let text = """
        文档里提到了字符串 Built-in Tool: 作为调试说明。

        这里没有 Input 或 Output 块，所以不应被删除。
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(result == text)
    }

    @Test("stripMCPRawIO removes plain-text output payloads")
    func stripMCPRemovesPlainTextOutput() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://example.com"}

        Output:
        Cached response from edge node
        March 2026 snapshot

        根据最新数据，明天不下雨。
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(!result.contains("Cached response"))
        #expect(!result.contains("March 2026 snapshot"))
        #expect(result.contains("根据最新数据"))
    }

    @Test("stripMCPRawIO handles pretty-printed multiline input")
    func stripMCPHandlesPrettyPrintedInput() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {
          "url": "https://example.com",
          "headers": {
            "accept": "text/html"
          },
          "options": {
            "format": "markdown",
            "cache": false
          }
        }

        Output:
        {"ok":true}

        [结果] 处理完成
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(!result.contains("\"headers\""))
        #expect(!result.contains("\"cache\""))
        #expect(result.contains("[结果] 处理完成"))
    }

    // MARK: - cleanResultText

    @Test("cleanResultText strips MCP I/O and extracts result")
    func cleanResultTextStripsAndExtracts() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://example.com"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"text": {"title": "Example"}}

        根据以上数据，答案是 42。

        [结果] 答案是 42
        """
        let result = TGEventHandler.cleanResultText(from: text)
        #expect(!result.contains("🌐"))
        #expect(!result.contains("webReader"))
        #expect(result == "答案是 42")
        #expect(!result.contains("[结果]"))
    }

    @Test("cleanResultText strips weather-style interleaved MCP transcript")
    func cleanResultTextStripsWeatherTranscript() {
        let text = """
        我先帮你查一下广州明天的天气。
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://weather.example.com/guangzhou"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"forecast":"cloudy"}

        查询到了最新天气。🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://weather.example.com/guangzhou/advice"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"advice":"carry umbrella"}

        广州明天多云，26°C 到 32°C，外出建议带伞。
        [结果] 广州明天多云，26°C 到 32°C，外出建议带伞。
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result == "广州明天多云，26°C 到 32°C，外出建议带伞。")
        #expect(!result.contains("Built-in Tool"))
        #expect(!result.contains("Input:"))
        #expect(!result.contains("Output:"))
        #expect(!result.contains("result_summary"))
        #expect(!result.contains("[结果]"))
    }

    @Test("cleanResultText extracts multiline latest result block")
    func cleanResultTextExtractsMultilineLatestResult() {
        let text = """
        [结果] 旧答案

        这是上一轮的内容。

        [结果]
        第一行答案
        第二行答案
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result == "第一行答案\n第二行答案")
    }

    @Test("cleanResultText keeps short terminal answer after MCP output")
    func cleanResultTextKeepsShortTerminalAnswer() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://example.com"}

        Output:
        {"ok":true}

        42
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result == "42")
    }
}
