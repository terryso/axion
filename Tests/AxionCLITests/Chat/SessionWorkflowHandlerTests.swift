import AxionCore
import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

@Suite("SessionWorkflowHandler (38.7)")
struct SessionWorkflowHandlerTests {

    // MARK: - formatNewSuccess (AC1)

    @Test("formatNewSuccess 包含 session ID 前缀")
    func formatNewSuccess() {
        let output = SessionWorkflowHandler.formatNewSuccess(sessionId: "chat-abcdef12")
        #expect(output.contains("新会话已创建"))
        #expect(output.contains("chat-abc"))
    }

    // MARK: - formatForkSuccess (AC2)

    @Test("formatForkSuccess 包含新 session 和来源 ID")
    func formatForkSuccess() {
        let output = SessionWorkflowHandler.formatForkSuccess(
            newId: "chat-newid123",
            sourceId: "chat-srcid456"
        )
        #expect(output.contains("已分叉会话"))
        #expect(output.contains("chat-new"))
        #expect(output.contains("chat-src"))
    }

    // MARK: - formatForkError

    @Test("formatForkError 包含错误提示")
    func formatForkError() {
        let output = SessionWorkflowHandler.formatForkError()
        #expect(output.contains("分叉会话失败"))
    }

    // MARK: - handleArchive 确认流程 (AC3)

    @Test("handleArchive 确认 y → 返回 .archiveSession")
    func handleArchiveConfirmed() async {
        let store = SessionStore(sessionsDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        // 先保存一个会话以便加载
        let sessionId = "chat-test-archive"
        let metadata = PartialSessionMetadata(cwd: "/tmp", model: "test")
        try? await store.save(sessionId: sessionId, messages: [], metadata: metadata)

        let action = await SessionWorkflowHandler.handleArchive(
            sessionId: sessionId,
            sessionStore: store,
            messageCount: 5,
            confirmFn: { "y" }
        )
        #expect(action == .archiveSession)
    }

    @Test("handleArchive 确认 yes → 返回 .archiveSession")
    func handleArchiveConfirmedYes() async {
        let store = SessionStore(sessionsDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        let sessionId = "chat-test-yes"
        let metadata = PartialSessionMetadata(cwd: "/tmp", model: "test")
        try? await store.save(sessionId: sessionId, messages: [], metadata: metadata)

        let action = await SessionWorkflowHandler.handleArchive(
            sessionId: sessionId,
            sessionStore: store,
            messageCount: 3,
            confirmFn: { "yes" }
        )
        #expect(action == .archiveSession)
    }

    @Test("handleArchive 取消 N → 返回 .none")
    func handleArchiveCancelled() async {
        let store = SessionStore(sessionsDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)

        let action = await SessionWorkflowHandler.handleArchive(
            sessionId: "chat-test-cancel",
            sessionStore: store,
            messageCount: 5,
            confirmFn: { "N" }
        )
        #expect(action == .none)
    }

    @Test("handleArchive 取消 空输入 → 返回 .none (AC8)")
    func handleArchiveEmptyInput() async {
        let store = SessionStore(sessionsDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)

        let action = await SessionWorkflowHandler.handleArchive(
            sessionId: "chat-test-empty",
            sessionStore: store,
            messageCount: 5,
            confirmFn: { nil }
        )
        #expect(action == .none)
    }

    // MARK: - 空会话保护 (AC7)

    @Test("handleFork 空会话 → 返回 .none + 提示")
    func handleForkEmptySession() async {
        let store = SessionStore(sessionsDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)

        let action = await SessionWorkflowHandler.handleFork(
            sessionId: "chat-empty",
            sessionStore: store,
            messageCount: 0
        )
        #expect(action == .none)
    }

    // MARK: - handleFork 成功分叉 (AC2)

    @Test("handleFork 成功分叉 → 返回 .forkSession(newId, sourceId)")
    func handleForkSuccess() async {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let store = SessionStore(sessionsDir: tmpDir)
        // 先保存一个会话以便 fork
        let sourceId = "chat-fork-source"
        let metadata = PartialSessionMetadata(cwd: "/tmp", model: "test")
        try? await store.save(sessionId: sourceId, messages: [], metadata: metadata)

        let action = await SessionWorkflowHandler.handleFork(
            sessionId: sourceId,
            sessionStore: store,
            messageCount: 5
        )
        if case .forkSession(let newId, let srcId) = action {
            #expect(srcId == sourceId)
            #expect(!newId.isEmpty)
            #expect(newId != sourceId)
        } else {
            Issue.record("Expected .forkSession but got \(action)")
        }
    }

    @Test("handleFork 不存在的会话 → 返回 .none")
    func handleForkNonExistent() async {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let store = SessionStore(sessionsDir: tmpDir)

        let action = await SessionWorkflowHandler.handleFork(
            sessionId: "chat-nonexistent",
            sessionStore: store,
            messageCount: 5
        )
        #expect(action == .none)
    }

    @Test("handleArchive 空会话 → 返回 .none + 提示")
    func handleArchiveEmptySession() async {
        let store = SessionStore(sessionsDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)

        let action = await SessionWorkflowHandler.handleArchive(
            sessionId: "chat-empty",
            sessionStore: store,
            messageCount: 0,
            confirmFn: { "y" }
        )
        #expect(action == .none)
    }

    // MARK: - handleArchive 加载失败

    @Test("handleArchive 会话不存在 → 返回 .none (load 失败)")
    func handleArchiveLoadFailure() async {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let store = SessionStore(sessionsDir: tmpDir)

        let action = await SessionWorkflowHandler.handleArchive(
            sessionId: "chat-nonexistent",
            sessionStore: store,
            messageCount: 5,
            confirmFn: { "y" }
        )
        #expect(action == .none)
    }

    // MARK: - formatArchivePrompt (AC3)

    @Test("formatArchivePrompt 包含确认提示")
    func formatArchivePrompt() {
        let output = SessionWorkflowHandler.formatArchivePrompt()
        #expect(output.contains("确认归档"))
        #expect(output.contains("y/N"))
    }

    @Test("formatArchiveCancelled 包含取消提示")
    func formatArchiveCancelled() {
        let output = SessionWorkflowHandler.formatArchiveCancelled()
        #expect(output.contains("已取消归档"))
    }

    @Test("formatArchiveSuccess 包含 session ID")
    func formatArchiveSuccess() {
        let output = SessionWorkflowHandler.formatArchiveSuccess(sessionId: "chat-abc12345")
        #expect(output.contains("已归档"))
        #expect(output.contains("chat-abc"))
    }

    @Test("formatArchiveError 包含错误提示")
    func formatArchiveError() {
        let output = SessionWorkflowHandler.formatArchiveError()
        #expect(output.contains("归档失败"))
    }

    // MARK: - formatAgentBusy (AC6)

    @Test("formatAgentBusy 包含提示信息")
    func formatAgentBusy() {
        let output = SessionWorkflowHandler.formatAgentBusy("new")
        #expect(output.contains("不可用"))
        #expect(output.contains("等待"))
    }

    @Test("formatEmptySession 包含操作名")
    func formatEmptySession() {
        let output = SessionWorkflowHandler.formatEmptySession("fork")
        #expect(output.contains("无内容"))
        #expect(output.contains("fork"))
    }

    // MARK: - SlashCommandAction 新 case (AC1/AC2/AC3)

    @Test("SlashCommandAction.newSession 等价性")
    func actionNewSessionEquality() {
        #expect(SlashCommandAction.newSession == .newSession)
        #expect(SlashCommandAction.newSession != .none)
        #expect(SlashCommandAction.newSession != .exit)
    }

    @Test("SlashCommandAction.forkSession 等价性")
    func actionForkSessionEquality() {
        #expect(SlashCommandAction.forkSession(newId: "a", sourceId: "b") == .forkSession(newId: "a", sourceId: "b"))
        #expect(SlashCommandAction.forkSession(newId: "a", sourceId: "b") != .forkSession(newId: "c", sourceId: "d"))
        #expect(SlashCommandAction.forkSession(newId: "a", sourceId: "b") != .none)
    }

    @Test("SlashCommandAction.archiveSession 等价性")
    func actionArchiveSessionEquality() {
        #expect(SlashCommandAction.archiveSession == .archiveSession)
        #expect(SlashCommandAction.archiveSession != .none)
        #expect(SlashCommandAction.archiveSession != .exit)
    }
}
