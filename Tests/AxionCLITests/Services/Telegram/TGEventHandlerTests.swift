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
        TGEventHandler(chatId: chatId) { message, chatId in
            collector.append(message, chatId: chatId)
        }
    }

    // MARK: - Task 4.1: Subscribed event types

    @Test("Subscribes to correct event types")
    func subscribedEventTypes() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)

        let types = await handler.subscribedEventTypes.map { $0 }
        let typeNames = Set(types.map { String(describing: $0) })

        #expect(typeNames.contains("ToolStartedEvent"))
        #expect(typeNames.contains("ToolCompletedEvent"))
        #expect(typeNames.contains("AgentCompletedEvent"))
        #expect(typeNames.contains("AgentFailedEvent"))
        #expect(typeNames.contains("ReviewResultEvent"))
        #expect(types.count == 5)
    }

    // MARK: - Task 4.2: ToolCompletedEvent push content format

    @Test("ToolCompletedEvent pushes step progress with tool name and duration")
    func toolCompletedPushesContent() async {
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

        let messages = collector.messages
        #expect(messages.count == 1)
        #expect(messages[0].chatId == 123)
        #expect(messages[0].message.contains("screenshot"))
        #expect(messages[0].message.contains("230"))
    }

    // MARK: - Task 4.3: Throttle logic (5 seconds)

    @Test("Throttle: multiple events within 5 seconds only push once")
    func throttleSuppressesRapidEvents() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        // First event — should push
        let event1 = ToolCompletedEvent(
            sessionId: nil, toolUseId: "tu-1", toolName: "screenshot",
            durationMs: 100, isError: false
        )
        await handler.handle(event1, context: context)

        // Second event immediately — should be throttled
        let event2 = ToolCompletedEvent(
            sessionId: nil, toolUseId: "tu-2", toolName: "click",
            durationMs: 200, isError: false
        )
        await handler.handle(event2, context: context)

        #expect(collector.messages.count == 1)
        #expect(collector.messages[0].message.contains("screenshot"))
    }

    // MARK: - Task 4.4: AgentCompletedEvent pushes result

    @Test("AgentCompletedEvent pushes final result")
    func agentCompletedPushesResult() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 5,
            durationMs: 12_000,
            resultText: "The task is done successfully."
        )
        await handler.handle(event, context: context)

        let messages = collector.messages
        #expect(messages.count == 1)
        #expect(messages[0].message.contains("任务完成"))
        #expect(messages[0].message.contains("5"))
        #expect(messages[0].message.contains("12"))
        #expect(messages[0].message.contains("The task is done successfully."))
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

    @Test("AgentCompletedEvent with stale session history only pushes current task result")
    func agentCompletedTrimsStaleHistory() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let text = """
        计算器已打开，之前有 5+3=8。
        [结果] 5+3=8 完成
        清除后执行 5+98=103
        ✅ 5 + 98 = 103
        [结果] 计算器已计算 5+98=103
        """
        let event = AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 9,
            durationMs: 733_000,
            resultText: text
        )
        await handler.handle(event, context: context)

        let msg = collector.messages[0].message
        #expect(!msg.contains("5+3=8"))
        #expect(msg.contains("5+98=103"))
        #expect(msg.contains("任务完成"))
    }

    // MARK: - Task 4.5: AgentFailedEvent pushes error (no API key)

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

    // MARK: - Task 4.6: Long message splitting

    @Test("Long AgentCompletedEvent result is sent through sendMessage (splitting handled by adapter)")
    func longMessageSentThroughSendMessage() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let longText = String(repeating: "A", count: 5000)
        let event = AgentCompletedEvent(
            sessionId: nil,
            totalSteps: 10,
            durationMs: 60_000,
            resultText: longText
        )
        await handler.handle(event, context: context)

        // sendMessage is called — splitting is TelegramAdapter's job
        #expect(collector.messages.count == 1)
        #expect(collector.messages[0].message.contains(longText))
    }

    // MARK: - Task 4.7: No chatId — silent skip (non-TG tasks)

    @Test("Handler with chatId still works — non-TG tasks simply don't create handler")
    func handlerAlwaysHasChatId() async {
        // Non-TG tasks don't create a TGEventHandler at all.
        // This test verifies the handler still functions normally
        // when called with any valid chatId.
        let collector = MessageCollector()
        let handler = makeHandler(chatId: 999, collector: collector)
        let context = makeContext()

        let event = AgentCompletedEvent(
            sessionId: nil, totalSteps: 1, durationMs: 500, resultText: "ok"
        )
        await handler.handle(event, context: context)

        #expect(collector.messages.count == 1)
        #expect(collector.messages[0].chatId == 999)
    }

    // MARK: - Additional edge cases

    @Test("ToolCompletedEvent with error still pushes")
    func toolCompletedErrorPushes() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = ToolCompletedEvent(
            sessionId: nil, toolUseId: "tu-1", toolName: "bash",
            durationMs: 50, isError: true
        )
        await handler.handle(event, context: context)

        #expect(collector.messages.count == 1)
        #expect(collector.messages[0].message.contains("bash"))
    }

    @Test("AgentCompletedEvent with nil resultText still pushes summary")
    func agentCompletedNilResult() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = AgentCompletedEvent(
            sessionId: nil, totalSteps: 3, durationMs: 2000, resultText: nil
        )
        await handler.handle(event, context: context)

        #expect(collector.messages.count == 1)
        #expect(collector.messages[0].message.contains("任务完成"))
        #expect(collector.messages[0].message.contains("3"))
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
}
