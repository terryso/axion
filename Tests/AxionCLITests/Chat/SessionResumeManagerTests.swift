import AxionCore
import Foundation
import Testing

@testable import AxionCLI

@Suite("SessionResumeManager")
struct SessionResumeManagerTests {

    // MARK: - formatSessionList

    @Test("formatSessionList 空列表返回 '无可恢复的会话'")
    func formatSessionListEmpty() {
        let output = SessionResumeManager.formatSessionList([])
        #expect(output.contains("无可恢复的会话"))
    }

    @Test("formatSessionList 非空列表包含表头")
    func formatSessionListHeader() {
        let sessions = [
            SessionInfo(
                sessionId: "chat-a1b2c3d4",
                cwd: "/tmp",
                model: "claude-sonnet-4",
                createdAt: Date(),
                messageCount: 5,
                summary: "Test session",
                status: "completed",
                totalSteps: 3
            )
        ]
        let output = SessionResumeManager.formatSessionList(sessions)
        #expect(output.contains("SESSION"))
        #expect(output.contains("TASK"))
        #expect(output.contains("STATUS"))
        #expect(output.contains("STEPS"))
        #expect(output.contains("CREATED"))
    }

    @Test("formatSessionList 包含会话数据")
    func formatSessionListData() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let sessions = [
            SessionInfo(
                sessionId: "chat-abcdef12",
                cwd: "/Users/test",
                model: "claude-sonnet-4",
                createdAt: date,
                messageCount: 10,
                summary: "Write hello world",
                status: "completed",
                totalSteps: 5
            )
        ]
        let output = SessionResumeManager.formatSessionList(sessions)
        // Verify the session data row contains expected fields
        // sessionId "chat-abcdef12" is 13 chars, fits in 14-char column → no truncation
        #expect(output.contains("chat-abcdef12"))
        #expect(output.contains("completed"))   // status
        #expect(output.contains("5"))           // steps
    }

    @Test("formatSessionList 无 summary 时显示 '-'")
    func formatSessionListNoSummary() {
        let sessions = [
            SessionInfo(
                sessionId: "chat-test",
                cwd: "/tmp",
                model: "model",
                createdAt: Date(),
                messageCount: 0,
                summary: nil,
                status: "unknown",
                totalSteps: 0
            )
        ]
        let output = SessionResumeManager.formatSessionList(sessions)
        #expect(output.contains("-"))
    }

    // MARK: - formatResumeHint

    @Test("formatResumeHint 包含 /resume <session-id> 提示")
    func formatResumeHint() {
        let output = SessionResumeManager.formatResumeHint()
        #expect(output.contains("/resume"))
        #expect(output.contains("session-id"))
    }

    // MARK: - formatResumeError

    @Test("formatResumeError 包含错误描述")
    func formatResumeError() {
        let error = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "session not found"
        ])
        let output = SessionResumeManager.formatResumeError(error)
        #expect(output.contains("恢复失败"))
        #expect(output.contains("session not found"))
    }

    // MARK: - formatSessionNotFound

    @Test("formatSessionNotFound 包含 session ID")
    func formatSessionNotFound() {
        let output = SessionResumeManager.formatSessionNotFound("chat-xyz123")
        #expect(output.contains("会话未找到"))
        #expect(output.contains("chat-xyz123"))
    }

    // MARK: - formatSessionAlreadyRunning

    @Test("formatSessionAlreadyRunning 包含 session ID")
    func formatSessionAlreadyRunning() {
        let output = SessionResumeManager.formatSessionAlreadyRunning("chat-running1")
        #expect(output.contains("会话正在运行"))
        #expect(output.contains("chat-running1"))
    }

    // MARK: - SlashCommandAction

    @Test("SlashCommandAction.none 不等于 .exit")
    func actionNoneNotExit() {
        #expect(SlashCommandAction.none != .exit)
    }

    @Test("SlashCommandAction.resumeSession 相等性")
    func actionResumeEquality() {
        #expect(SlashCommandAction.resumeSession("abc") == .resumeSession("abc"))
        #expect(SlashCommandAction.resumeSession("abc") != .resumeSession("xyz"))
    }

    @Test("SlashCommandAction.resumeSession 不等于 .none 和 .exit")
    func actionResumeNotOthers() {
        #expect(SlashCommandAction.resumeSession("abc") != .none)
        #expect(SlashCommandAction.resumeSession("abc") != .exit)
    }

    // MARK: - BannerRenderer.renderResumeBanner

    @Test("renderResumeBanner 包含 session ID 和消息数")
    func renderResumeBanner() {
        let output = BannerRenderer.renderResumeBanner(
            sessionId: "chat-a1b2c3d4",
            messageCount: 15,
            model: "claude-sonnet-4",
            contextWindow: 200_000
        )
        #expect(output.contains("chat-a1b2c3d4"))
        #expect(output.contains("15"))
        #expect(output.contains("claude-sonnet-4"))
        #expect(output.contains("200k"))
        #expect(output.contains("已恢复会话"))
        #expect(output.contains("/help"))
    }

    @Test("renderResumeBanner 上下文显示 0/N 格式")
    func renderResumeBannerContext() {
        let output = BannerRenderer.renderResumeBanner(
            sessionId: "chat-test",
            messageCount: 0,
            model: "model",
            contextWindow: 128_000
        )
        #expect(output.contains("0/128k"))
    }

    // MARK: - SlashCommand helpText 更新验证

    @Test("/resume 帮助文本已更新（不包含 '暂未实现'）")
    func resumeHelpTextUpdated() {
        let helpText = SlashCommand.resume.helpText
        #expect(!helpText.contains("暂未实现"))
        #expect(helpText.contains("/resume"))
    }

    // MARK: - handleResume 各种参数场景

    @Test("handleResume 传入带空格的 session ID")
    func handleResumeWithSpaces() {
        // parseArgument 会先 trim，这里直接测试 handler
        let action = SlashCommandHandler.handleResume(argument: "  chat-abc  ")
        #expect(action == .resumeSession("  chat-abc  "))
    }

    @Test("handleResume 传入完整 session ID")
    func handleResumeFullSessionId() {
        let action = SlashCommandHandler.handleResume(argument: "chat-a1b2c3d4e5f6")
        #expect(action == .resumeSession("chat-a1b2c3d4e5f6"))
    }
}
