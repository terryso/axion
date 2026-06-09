import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

// MARK: - ContextManager Tests

@Suite("ContextManager")
struct ContextManagerTests {

    // MARK: - estimateContextTokens ([SDKMessage])

    @Test("estimateContextTokens: 空消息数组 → 0")
    func estimateContextTokens_empty() {
        let messages: [SDKMessage] = []
        #expect(ContextManager.estimateContextTokens(messages: messages) == 0)
    }

    @Test("estimateContextTokens: 单条 assistant 消息 → 正确估算")
    func estimateContextTokens_singleAssistant() {
        let messages: [SDKMessage] = [
            .assistant(SDKMessage.AssistantData(
                text: String(repeating: "a", count: 400),  // 400 chars ≈ 100 tokens
                model: "test",
                stopReason: "end_turn"
            ))
        ]
        let tokens = ContextManager.estimateContextTokens(messages: messages)
        #expect(tokens == 100)
    }

    @Test("estimateContextTokens: 多条消息 → 正确累加")
    func estimateContextTokens_multipleMessages() {
        let messages: [SDKMessage] = [
            .userMessage(SDKMessage.UserMessageData(message: "Hello")),  // 5 chars
            .assistant(SDKMessage.AssistantData(text: "World", model: "test", stopReason: "end_turn"))  // 5 chars
        ]
        let tokens = ContextManager.estimateContextTokens(messages: messages)
        // 10 chars / 4 = 2 tokens
        #expect(tokens == 2)
    }

    // MARK: - estimateContextTokens ([[String: Any]])

    @Test("estimateContextTokens dict: 空消息 → 0")
    func estimateContextTokensDict_empty() {
        #expect(ContextManager.estimateContextTokens(messages: [[String: Any]]()) == 0)
    }

    @Test("estimateContextTokens dict: 单条字符串 content → 正确估算")
    func estimateContextTokensDict_stringContent() {
        let messages: [[String: Any]] = [
            ["content": String(repeating: "x", count: 200)]  // 200 chars / 4 = 50 tokens
        ]
        #expect(ContextManager.estimateContextTokens(messages: messages) == 50)
    }

    @Test("estimateContextTokens dict: blocks content → 正确估算")
    func estimateContextTokensDict_blocksContent() {
        let messages: [[String: Any]] = [
            ["content": [["text": "Hello world"]]]  // 11 chars / 4 = 2 tokens
        ]
        #expect(ContextManager.estimateContextTokens(messages: messages) == 2)
    }

    // MARK: - formatCompactMessage

    @Test("formatCompactMessage: 正确格式化前后 token 对比")
    func formatCompactMessage_basic() {
        let result = ContextManager.formatCompactMessage(beforeTokens: 45_000, afterTokens: 8_000)
        #expect(result == "[axion] 上下文已自动压缩 (45k → 8k tokens)\n")
    }

    @Test("formatCompactMessage: 小数字不缩写")
    func formatCompactMessage_smallNumbers() {
        let result = ContextManager.formatCompactMessage(beforeTokens: 500, afterTokens: 200)
        #expect(result == "[axion] 上下文已自动压缩 (500 → 200 tokens)\n")
    }

    // MARK: - formatCompactFailureMessage

    @Test("formatCompactFailureMessage: 失败 1 次 → 普通警告")
    func formatCompactFailureMessage_singleFailure() {
        let result = ContextManager.formatCompactFailureMessage(failureCount: 1)
        #expect(result.contains("⚠️"))
        #expect(result.contains("压缩失败"))
        #expect(!result.contains("连续失败"))
    }

    @Test("formatCompactFailureMessage: 失败 3 次 → 停止尝试")
    func formatCompactFailureMessage_maxFailures() {
        let result = ContextManager.formatCompactFailureMessage(failureCount: 3)
        #expect(result.contains("连续失败"))
        #expect(result.contains("3 次"))
        #expect(result.contains("停止自动压缩"))
    }

    @Test("formatCompactFailureMessage: 失败 5 次 → 停止尝试")
    func formatCompactFailureMessage_exceedsMax() {
        let result = ContextManager.formatCompactFailureMessage(failureCount: 5)
        #expect(result.contains("连续失败"))
        #expect(result.contains("5 次"))
    }

    // MARK: - formatContextUsage

    @Test("formatContextUsage: 正确格式化用量行")
    func formatContextUsage_basic() {
        let result = ContextManager.formatContextUsage(usedTokens: 12_000, contextWindow: 200_000)
        #expect(result == "Context:        12k/200k (6%)")
    }

    @Test("formatContextUsage: 0 用量")
    func formatContextUsage_zero() {
        let result = ContextManager.formatContextUsage(usedTokens: 0, contextWindow: 200_000)
        #expect(result == "Context:        0/200k (0%)")
    }

    @Test("formatContextUsage: 满载")
    func formatContextUsage_full() {
        let result = ContextManager.formatContextUsage(usedTokens: 200_000, contextWindow: 200_000)
        #expect(result == "Context:        200k/200k (100%)")
    }

    @Test("formatContextUsage: 零 contextWindow → 0%")
    func formatContextUsage_zeroWindow() {
        let result = ContextManager.formatContextUsage(usedTokens: 100, contextWindow: 0)
        #expect(result.contains("(0%)"))
    }

    // MARK: - formatCompactStatus

    @Test("formatCompactStatus: 低于阈值 → 显示用量")
    func formatCompactStatus_belowThreshold() {
        let result = ContextManager.formatCompactStatus(usedTokens: 50_000, contextWindow: 200_000)
        #expect(result.contains("50k/200k"))
        #expect(result.contains("25%"))
        #expect(!result.contains("自动压缩"))
    }

    @Test("formatCompactStatus: 达到 SDK 阈值 → 提示自动压缩")
    func formatCompactStatus_atSDKThreshold() {
        // SDK threshold for 200K = 200K - 13K = 187K
        let result = ContextManager.formatCompactStatus(usedTokens: 190_000, contextWindow: 200_000)
        #expect(result.contains("190k/200k"))
        #expect(result.contains("95%"))
        #expect(result.contains("自动压缩"))
    }

    @Test("formatCompactStatus: 低于 SDK 阈值 → 不提示自动压缩")
    func formatCompactStatus_belowSDKThreshold() {
        // 160K < 187K SDK threshold
        let result = ContextManager.formatCompactStatus(usedTokens: 160_000, contextWindow: 200_000)
        #expect(result.contains("160k/200k"))
        #expect(result.contains("80%"))
        #expect(!result.contains("自动压缩"))
    }

    @Test("formatCompactStatus: 远超阈值 → 提示自动压缩")
    func formatCompactStatus_aboveThreshold() {
        let result = ContextManager.formatCompactStatus(usedTokens: 195_000, contextWindow: 200_000)
        #expect(result.contains("195k/200k"))
        #expect(result.contains("自动压缩"))
    }
}

// MARK: - SlashCommandHandler Updated Tests

@Suite("SlashCommandHandler + ContextManager")
struct SlashCommandHandlerContextTests {

    // MARK: - handleCompact (updated from placeholder)

    @Test("handleCompact: 显示当前上下文状态")
    func handleCompact_showsStatus() {
        let output = SlashCommandHandler.handleCompact(
            contextTokens: 50_000,
            contextWindow: 200_000
        )
        #expect(output.contains("50k/200k"))
        #expect(output.contains("25%"))
        #expect(!output.contains("暂未实现"))
    }

    @Test("handleCompact: 默认参数（零值）")
    func handleCompact_defaultArgs() {
        let output = SlashCommandHandler.handleCompact()
        #expect(output.contains("0/0"))
        #expect(!output.contains("暂未实现"))
    }

    @Test("handleCompact: 达到 SDK 阈值提示自动压缩")
    func handleCompact_atSDKThreshold() {
        // SDK threshold for 200K = 187K; use 190K to exceed it
        let output = SlashCommandHandler.handleCompact(
            contextTokens: 190_000,
            contextWindow: 200_000
        )
        #expect(output.contains("自动压缩"))
    }

    // MARK: - handleCost (enhanced with context line)

    @Test("handleCost: 包含上下文用量行")
    func handleCost_includesContextLine() {
        let usage = TokenUsage(
            inputTokens: 1000,
            outputTokens: 500,
            cacheCreationInputTokens: 200,
            cacheReadInputTokens: 300
        )
        let output = SlashCommandHandler.handleCost(
            usage: usage,
            model: "claude-sonnet-4-20250514",
            contextTokens: 12_000,
            contextWindow: 200_000
        )
        #expect(output.contains("1000"))  // input
        #expect(output.contains("500"))   // output
        #expect(output.contains("1500"))  // total
        #expect(output.contains("$"))
        #expect(output.contains("Context:"))
        #expect(output.contains("12k/200k"))
        #expect(output.contains("(6%)"))
    }

    @Test("handleCost: 零值上下文行")
    func handleCost_zeroContext() {
        let usage = TokenUsage(inputTokens: 0, outputTokens: 0)
        let output = SlashCommandHandler.handleCost(
            usage: usage,
            model: "claude-sonnet-4-20250514"
        )
        #expect(output.contains("Context:"))
        #expect(output.contains("0/0"))
        #expect(output.contains("(0%)"))
    }

    @Test("handleCost: 向后兼容 — 不传 contextTokens/contextWindow")
    func handleCost_backwardCompatible() {
        let usage = TokenUsage(inputTokens: 100, outputTokens: 50)
        let output = SlashCommandHandler.handleCost(
            usage: usage,
            model: "claude-sonnet-4-20250514"
        )
        // Should still work with defaults (0, 0)
        #expect(output.contains("100"))
        #expect(output.contains("50"))
        #expect(output.contains("$"))
        #expect(output.contains("Context:"))
    }

    // MARK: - Regression: existing /cost token and cost display unchanged

    @Test("handleCost: 原有 token 用量和成本显示保持不变")
    func handleCost_regression_existingOutput() {
        let usage = TokenUsage(
            inputTokens: 5000,
            outputTokens: 2000,
            cacheCreationInputTokens: 1000,
            cacheReadInputTokens: 500
        )
        let output = SlashCommandHandler.handleCost(
            usage: usage,
            model: "claude-sonnet-4-20250514",
            contextTokens: 30_000,
            contextWindow: 200_000
        )
        // Existing fields still present
        #expect(output.contains("Input:"))
        #expect(output.contains("Output:"))
        #expect(output.contains("Cache Creation:"))
        #expect(output.contains("Cache Read:"))
        #expect(output.contains("Total:"))
        #expect(output.contains("预估成本:"))
        #expect(output.contains("5000"))
        #expect(output.contains("2000"))
        #expect(output.contains("1000"))
        #expect(output.contains("500"))
        #expect(output.contains("7000"))  // total
    }
}
