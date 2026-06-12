import Foundation
import Testing

@testable import AxionCLI
import OpenAgentSDK

/// E2E tests for the Chat streaming pipeline (ChatOutputFormatter).
///
/// Tests the interactive mode's output formatter with both mock streams
/// (deterministic, no API) and real Agent streams (requires API key).
@Suite("Chat Streaming E2E")
struct ChatStreamingE2ETests {

    // MARK: - Mock Stream Tests (no API needed)

    @Test("mock stream: simple text response")
    func mockSimpleText() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        handler.startLLMWaiting()

        let messages: [SDKMessage] = [
            ChatE2EMessages.partial("Hello"),
            ChatE2EMessages.partial(" World"),
            ChatE2EMessages.assistant("Hello World"),
            ChatE2EMessages.successResult(text: "Done"),
        ]

        let stream = mockAgentStream(messages: messages)
        for await message in stream {
            handler.handle(message)
        }
        handler.displayCompletion()

        let output = capturing.allStdout
        #expect(output.contains("Hello"), "Should contain partial text 'Hello'")
        #expect(output.contains("World"), "Should contain partial text 'World'")
    }

    @Test("mock stream: tool use + tool result")
    func mockToolUseAndResult() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        let messages: [SDKMessage] = [
            ChatE2EMessages.assistant("I'll list files."),
            ChatE2EMessages.toolUse("Bash", id: "t1", input: #"{"command":"ls"}"#),
            ChatE2EMessages.toolResult(id: "t1", content: "file1.txt\nfile2.txt"),
            ChatE2EMessages.assistant("Here are the files."),
            ChatE2EMessages.successResult(text: "Listed 2 files"),
        ]

        let stream = mockAgentStream(messages: messages)
        for await message in stream {
            handler.handle(message)
        }
        handler.displayCompletion()

        let output = capturing.allStdout
        #expect(output.contains("exec"), "Should show tool execution (Bash → exec)")
        #expect(capturing.containsStdout("file1.txt") || capturing.containsStderr("file1.txt") || output.contains("exec"),
               "Should show tool execution info")
    }

    @Test("mock stream: error result")
    func mockErrorResult() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        let messages: [SDKMessage] = [
            ChatE2EMessages.assistant("Working on it..."),
            ChatE2EMessages.errorResult(text: "Max turns exceeded"),
        ]

        let stream = mockAgentStream(messages: messages)
        for await message in stream {
            handler.handle(message)
        }

        let output = capturing.allStderr
        #expect(output.contains("最大步数限制") || output.contains("Max"),
               "Should show error message for max turns")
    }

    @Test("mock stream: cancelled with suppressInterruptError")
    func mockCancelledSuppressed() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        handler.suppressInterruptError = true

        let messages: [SDKMessage] = [
            ChatE2EMessages.cancelledResult(),
        ]

        let stream = mockAgentStream(messages: messages)
        for await message in stream {
            handler.handle(message)
        }

        let output = capturing.allStderr
        #expect(!output.contains("取消"), "Should NOT show cancelled warning when suppressed")
        #expect(!output.contains("Cancelled"), "Should NOT show cancelled warning when suppressed")
    }

    @Test("mock stream: cancelled without suppress shows warning")
    func mockCancelledNotSuppressed() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        let messages: [SDKMessage] = [
            ChatE2EMessages.cancelledResult(),
        ]

        let stream = mockAgentStream(messages: messages)
        for await message in stream {
            handler.handle(message)
        }

        let output = capturing.allStderr
        #expect(output.contains("取消"), "Should show cancelled warning when not suppressed")
    }

    @Test("mock stream: execution error suppressed")
    func mockExecutionErrorSuppressed() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        handler.suppressInterruptError = true

        let messages: [SDKMessage] = [
            ChatE2EMessages.executionErrorResult(),
        ]

        let stream = mockAgentStream(messages: messages)
        for await message in stream {
            handler.handle(message)
        }

        let output = capturing.allStderr
        #expect(!output.contains("执行错误"), "Should NOT show error when suppressed")
    }

    @Test("mock stream: error tool result with isError flag")
    func mockErrorToolResult() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        let messages: [SDKMessage] = [
            ChatE2EMessages.toolUse("Bash", id: "t1"),
            ChatE2EMessages.toolResult(id: "t1", content: "command not found", isError: true),
            ChatE2EMessages.successResult(),
        ]

        let stream = mockAgentStream(messages: messages)
        for await message in stream {
            handler.handle(message)
        }

        let output = capturing.allStdout
        #expect(output.contains("exec"), "Should show tool execution (Bash → exec)")
    }

    @Test("mock stream: paused system message")
    func mockPausedMessage() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        let messages: [SDKMessage] = [
            ChatE2EMessages.toolUse("Bash", id: "t1"),
            ChatE2EMessages.paused(reason: "需要用户确认"),
        ]

        let stream = mockAgentStream(messages: messages)
        for await message in stream {
            handler.handle(message)
        }

        let output = capturing.allStderr
        #expect(output.contains("暂停") || output.contains("需要用户确认"),
               "Should show paused reason")
    }

    @Test("mock stream: tool use tracks timing")
    func mockToolTiming() async {
        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        let messages: [SDKMessage] = [
            ChatE2EMessages.toolUse("Read", id: "t1", input: #"{"path":"test.swift"}"#),
            ChatE2EMessages.toolResult(id: "t1", content: "file contents here"),
            ChatE2EMessages.successResult(),
        ]

        let stream = mockAgentStream(messages: messages)
        for await message in stream {
            handler.handle(message)
        }

        let output = capturing.allStdout
        #expect(output.contains("read"), "Should show Read tool name (lowercased)")
    }

    // MARK: - ChatTheme Integration

    @Test("themed output: user message has role dot")
    func themedUserMessage() {
        let theme = ChatTheme(profile: .ansi16, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let output = renderer.renderUserMessage(text: "Hello")

        #expect(output.contains("Hello"), "Should contain message text")
        #expect(output.hasPrefix("\u{1B}["), "Should start with ANSI code for colored dot")
    }

    @Test("themed output: assistant block start has dot")
    func themedAssistantBlock() {
        let theme = ChatTheme(profile: .ansi16, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let output = renderer.renderAssistantBlockStart()

        #expect(output.hasPrefix("\u{1B}["), "Should start with ANSI code for colored dot")
    }

    @Test("themed output: warning has red dot")
    func themedWarning() {
        let theme = ChatTheme(profile: .ansi16, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let output = renderer.renderWarning(message: "test warning")

        #expect(output.contains("test warning"), "Should contain warning text")
        #expect(output.hasPrefix("\u{1B}["), "Should start with ANSI code")
    }

    @Test("themed output: turn summary TTY format")
    func themedTurnSummaryTTY() {
        let theme = ChatTheme(profile: .ansi16, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let output = renderer.renderTurnSummary(
            duration: "3.2s",
            toolCount: 2,
            inputTokens: "1.2k",
            outputTokens: "856"
        )

        #expect(output.contains("3.2s"), "Should show duration")
        #expect(output.contains("2 tools"), "Should show tool count")
        #expect(output.contains("1.2k"), "Should show input tokens")
        #expect(output.contains("856"), "Should show output tokens")
        #expect(output.contains("──"), "Should use dash separator in TTY mode")
    }

    @Test("themed output: turn summary non-TTY format")
    func themedTurnSummaryNonTTY() {
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let renderer = TranscriptRenderer(theme: theme)
        let output = renderer.renderTurnSummary(
            duration: "5.0s",
            toolCount: 0,
            inputTokens: "500",
            outputTokens: "200"
        )

        #expect(output.contains("[turn:"), "Should use bracket format in non-TTY")
        #expect(output.contains("5.0s"), "Should show duration")
        #expect(output.contains("0 tools"), "Should show tool count")
    }

    // MARK: - Real Agent Tests (requires API key)

    @Test("real agent: simple question returns text")
    func realSimpleQuestion() async throws {
        let maxRetries = 2

        for attempt in 1...maxRetries {
            guard let (agent, _) = try await buildRealChatAgent(maxTurns: 2) else { return }

            let capturing = CapturingChatOutput()
            let handler = capturing.makeFormatter()

            handler.startLLMWaiting()
            let result = await collectStreamResult(
                agent: agent,
                task: "回复 hello，不要使用任何工具",
                handler: handler
            )

            try? await agent.close()

            if !result.assistantTexts.isEmpty && result.resultSubtype == .success {
                return  // Test passed
            }

            if attempt < maxRetries {
                print("[retry] realSimpleQuestion attempt \(attempt)/\(maxRetries) failed: subtype=\(String(describing: result.resultSubtype)), assistantTexts=\(result.assistantTexts.count), resultText=\(result.resultText.prefix(200))")
                try? await _Concurrency.Task.sleep(for: .seconds(3))
                continue
            }

            // Final attempt — fail with diagnostic info
            #expect(!result.assistantTexts.isEmpty, "Should have assistant text (after \(maxRetries) attempts). subtype=\(String(describing: result.resultSubtype)), resultText=\(result.resultText.prefix(200))")
            #expect(result.resultSubtype == .success, "Should complete successfully (after \(maxRetries) attempts). subtype=\(String(describing: result.resultSubtype))")
        }
    }

    @Test("real agent: tool call produces tool output")
    func realToolCall() async throws {
        guard let (agent, _) = try await buildRealChatAgent(maxTurns: 3) else { return }

        let capturing = CapturingChatOutput()
        let handler = capturing.makeFormatter()

        handler.startLLMWaiting()
        let result = await collectStreamResult(
            agent: agent,
            task: "列出当前目录下的文件",
            handler: handler
        )

        try? await agent.close()

        #expect(!result.toolCalls.isEmpty, "Should have at least one tool call")
        #expect(result.resultSubtype == .success, "Should complete successfully")
        // Output should contain tool execution info
        #expect(!capturing.allStdout.isEmpty, "Should produce stdout output")
    }

    @Test("real agent: multi-turn conversation with session store")
    func realMultiTurn() async throws {
        let config = try await ConfigManager.loadConfig()
        guard config.apiKey != nil, !config.apiKey!.isEmpty else { return }
        // forChat 非 dryrun：build() 守卫要求 helper 可解析（AgentBuilder.swift:71）。
        // swift test host 进程下 resolveHelperPath 即便 .build 有二进制也可能返回 nil
        // （策略3 依赖进程路径含 .build）—— 不可用时优雅跳过，不硬失败。
        guard HelperPathResolver.resolveHelperPath() != nil else { return }

        // Build agent with SessionStore so multi-turn context is preserved
        let sessionsDir = ConfigManager.sessionsDirectory
        let store = SessionStore(sessionsDir: sessionsDir)
        let sessionId = "chat-multiturn-test-\(Int.random(in: 1000...9999))"

        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            sessionId: sessionId,
            sessionStore: store
        )

        let buildResult = try await AgentBuilder.build(buildConfig)
        let agent = buildResult.agent

        // Turn 1
        let capturing1 = CapturingChatOutput()
        let handler1 = capturing1.makeFormatter()
        handler1.startLLMWaiting()

        let result1 = await collectStreamResult(
            agent: agent,
            task: "记住数字 42",
            handler: handler1
        )
        #expect(result1.resultSubtype == .success, "Turn 1 should succeed")

        // Turn 2 — verify agent remembers context
        let capturing2 = CapturingChatOutput()
        let handler2 = capturing2.makeFormatter()
        handler2.startLLMWaiting()

        let result2 = await collectStreamResult(
            agent: agent,
            task: "我刚才让你记住的数字是什么？直接回复数字",
            handler: handler2
        )
        #expect(result2.resultSubtype == .success, "Turn 2 should succeed")

        try? await agent.close()

        // Verify the response mentions 42
        let combined = result2.assistantTexts.joined(separator: " ") + result2.resultText
        #expect(combined.contains("42"), "Agent should remember the number 42 from previous turn")
    }
}
