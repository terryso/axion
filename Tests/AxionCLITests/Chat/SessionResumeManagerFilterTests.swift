import AxionCore
import Foundation
import Testing

@testable import AxionCLI

@Suite("SessionResumeManager Archive Filter (38.7)")
struct SessionResumeManagerFilterTests {

    // MARK: - AC4: 默认不显示归档会话

    @Test("formatSessionList 默认过滤归档会话")
    func filterArchivedByDefault() {
        let sessions = [
            SessionInfo(
                sessionId: "chat-active1",
                cwd: "/tmp",
                model: "model",
                messageCount: 5,
                summary: "Active session",
                tag: nil
            ),
            SessionInfo(
                sessionId: "chat-archived1",
                cwd: "/tmp",
                model: "model",
                messageCount: 3,
                summary: "Archived session",
                tag: "archived"
            ),
            SessionInfo(
                sessionId: "chat-active2",
                cwd: "/tmp",
                model: "model",
                messageCount: 2,
                summary: "Another active",
                tag: nil
            )
        ]
        let output = SessionResumeManager.formatSessionList(sessions)
        #expect(output.contains("chat-active1"))
        #expect(output.contains("chat-active2"))
        #expect(!output.contains("chat-archived1"))
    }

    @Test("formatSessionList includeArchived=true 显示全部")
    func includeArchivedShowsAll() {
        let sessions = [
            SessionInfo(
                sessionId: "chat-active1",
                cwd: "/tmp",
                model: "model",
                messageCount: 5,
                summary: "Active session",
                tag: nil
            ),
            SessionInfo(
                sessionId: "chat-archived1",
                cwd: "/tmp",
                model: "model",
                messageCount: 3,
                summary: "Archived session",
                tag: "archived"
            )
        ]
        let output = SessionResumeManager.formatSessionList(sessions, includeArchived: true)
        #expect(output.contains("chat-active1"))
        #expect(output.contains("chat-archived1"))
    }

    @Test("formatSessionList 全部归档时默认显示 '无可恢复的会话'")
    func allArchivedShowsEmpty() {
        let sessions = [
            SessionInfo(
                sessionId: "chat-archived1",
                cwd: "/tmp",
                model: "model",
                tag: "archived"
            ),
            SessionInfo(
                sessionId: "chat-archived2",
                cwd: "/tmp",
                model: "model",
                tag: "archived"
            )
        ]
        let output = SessionResumeManager.formatSessionList(sessions)
        #expect(output.contains("无可恢复的会话"))
    }

    // MARK: - TAG 列显示

    @Test("formatSessionList 表头包含 TAG 列")
    func headerIncludesTagColumn() {
        let sessions = [
            SessionInfo(
                sessionId: "chat-test",
                cwd: "/tmp",
                model: "model"
            )
        ]
        let output = SessionResumeManager.formatSessionList(sessions)
        #expect(output.contains("TAG"))
    }

    @Test("formatSessionList 归档会话 TAG 列显示 'archived'")
    func archivedSessionShowsTag() {
        let sessions = [
            SessionInfo(
                sessionId: "chat-archived1",
                cwd: "/tmp",
                model: "model",
                tag: "archived"
            )
        ]
        let output = SessionResumeManager.formatSessionList(sessions, includeArchived: true)
        #expect(output.contains("archived"))
    }

    @Test("formatSessionList 普通会话 TAG 列为空")
    func normalSessionNoTag() {
        let sessions = [
            SessionInfo(
                sessionId: "chat-normal",
                cwd: "/tmp",
                model: "model",
                tag: nil
            )
        ]
        let output = SessionResumeManager.formatSessionList(sessions)
        #expect(output.contains("chat-normal"))
    }
}
