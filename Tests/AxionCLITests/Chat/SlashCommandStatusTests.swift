import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

@Suite("SlashCommand /status (AC5)")
struct SlashCommandStatusTests {

    // MARK: - handleStatus 输出格式

    @Test("handleStatus — 输出包含所有字段")
    func handleStatusContainsAllFields() {
        let usage = TokenUsage(inputTokens: 45000, outputTokens: 12000)
        let output = SlashCommandHandler.handleStatus(
            model: "claude-sonnet-4-20250514",
            permissionMode: "bypassPermissions",
            sessionId: "chat-20260607abcd",
            contextTokens: 12345,
            contextWindow: 200000,
            cwd: "/Users/nick/project",
            usage: usage
        )
        #expect(output.contains("会话状态:"))
        #expect(output.contains("模型:"))
        #expect(output.contains("claude-sonnet-4-20250514"))
        #expect(output.contains("权限:"))
        #expect(output.contains("bypassPermissions"))
        #expect(output.contains("Session:"))
        #expect(output.contains("chat-202"))  // 前 8 位
        #expect(output.contains("工作目录:"))
        #expect(output.contains("/Users/nick/project"))
        #expect(output.contains("Token:"))
        #expect(output.contains("输入 45000"))
        #expect(output.contains("输出 12000"))
        #expect(output.contains("总 57000"))
    }

    @Test("handleStatus — context 百分比计算")
    func handleStatusContextPercentage() {
        let usage = TokenUsage(inputTokens: 10000, outputTokens: 5000)
        let output = SlashCommandHandler.handleStatus(
            model: "test-model",
            permissionMode: "default",
            sessionId: "session-12345678",
            contextTokens: 50000,
            contextWindow: 200000,
            cwd: "/tmp",
            usage: usage
        )
        // 50000/200000 = 25%
        #expect(output.contains("25%"))
    }

    @Test("handleStatus — session ID 截取前 8 位")
    func handleStatusSessionIdTruncated() {
        let usage = TokenUsage(inputTokens: 0, outputTokens: 0)
        let output = SlashCommandHandler.handleStatus(
            model: "test",
            permissionMode: "default",
            sessionId: "very-long-session-id-12345",
            contextTokens: 0,
            contextWindow: 200000,
            cwd: "/tmp",
            usage: usage
        )
        #expect(output.contains("very-lon"))
        #expect(!output.contains("very-long-session"))
    }

    @Test("handleStatus — 零 token 用量")
    func handleStatusZeroTokens() {
        let usage = TokenUsage(inputTokens: 0, outputTokens: 0)
        let output = SlashCommandHandler.handleStatus(
            model: "test",
            permissionMode: "default",
            sessionId: "session-1234",
            contextTokens: 0,
            contextWindow: 200000,
            cwd: "/tmp",
            usage: usage
        )
        #expect(output.contains("输入 0"))
        #expect(output.contains("输出 0"))
        #expect(output.contains("总 0"))
    }
}
