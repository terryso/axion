import ArgumentParser
import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

@Suite("SessionsCommand")
struct SessionsCommandTests {

    // MARK: - Mock

    actor MockSessionLister: SessionListing {
        let sessions: [SessionInfo]
        init(_ sessions: [SessionInfo]) { self.sessions = sessions }
        func listSessions(limit: Int?) async throws -> [SessionInfo] { sessions }
    }

    // MARK: - Helpers

    private func makeSession(
        id: String = "a1b2c3d4e5f67890",
        summary: String? = "refactor auth module",
        status: String = "completed",
        totalSteps: Int = 12,
        durationMs: Int? = 34000,
        createdAt: Date? = Date(timeIntervalSince1970: 1_748_331_120)
    ) -> SessionInfo {
        SessionInfo(
            sessionId: id,
            cwd: "/tmp",
            model: "claude-sonnet-4-6",
            createdAt: createdAt,
            summary: summary,
            status: status,
            totalSteps: totalSteps,
            durationMs: durationMs
        )
    }

    // MARK: - run() Integration

    @Test("run() renders sessions from injected lister")
    func test_run_rendersFromLister() async throws {
        let sessions = [
            makeSession(id: "run1", summary: "task 1", status: "completed"),
            makeSession(id: "run2", summary: "task 2", status: "failed"),
        ]
        SessionsCommand.createLister = { MockSessionLister(sessions) }
        defer { SessionsCommand.createLister = { AxionRuntime() } }

        let cmd = try SessionsCommand.parse([])
        try await cmd.run()
    }

    @Test("run() with empty sessions prints no sessions message")
    func test_run_emptySessions() async throws {
        SessionsCommand.createLister = { MockSessionLister([]) }
        defer { SessionsCommand.createLister = { AxionRuntime() } }

        let cmd = try SessionsCommand.parse([])
        try await cmd.run()
    }

    @Test("validate() rejects --limit 0")
    func test_validate_rejectsZeroLimit() {
        #expect(throws: (any Error).self) {
            try SessionsCommand.parse(["--limit", "0"])
        }
    }

    @Test("validate() rejects --limit -1")
    func test_validate_rejectsNegativeLimit() {
        #expect(throws: (any Error).self) {
            try SessionsCommand.parse(["--limit=-1"])
        }
    }

    // MARK: - Table Rendering: Header

    @Test("renderTable includes column headers")
    func test_renderTable_includesHeaders() {
        let session = makeSession()
        let output = SessionsCommand.renderTable([session])
        #expect(output.contains("SESSION"))
        #expect(output.contains("TASK"))
        #expect(output.contains("STATUS"))
        #expect(output.contains("STEPS"))
        #expect(output.contains("DURATION"))
        #expect(output.contains("CREATED"))
    }

    // MARK: - Table Rendering: Empty Sessions

    @Test("renderTable with no sessions returns empty message")
    func test_renderTable_noSessions() {
        let output = SessionsCommand.renderTable([])
        #expect(output.contains("No sessions found"))
    }

    // MARK: - Table Rendering: Single Session

    @Test("renderTable formats a single session correctly")
    func test_renderTable_singleSession() {
        let session = makeSession()
        let output = SessionsCommand.renderTable([session])

        #expect(output.contains("a1b2c3d4"))
        #expect(output.contains("refactor auth module"))
        #expect(output.contains("completed"))
        #expect(output.contains("12"))
        #expect(output.contains("34s"))
    }

    // MARK: - Table Rendering: Session ID Truncation

    @Test("renderTable truncates long session IDs")
    func test_renderTable_truncatesLongSessionID() {
        let session = makeSession(id: "abcdefghijklmnopqrstuvwxyz1234567890")
        let output = SessionsCommand.renderTable([session])

        #expect(output.contains("abcdefgh"))
        #expect(!output.contains("abcdefghijklmnopqrstuvwxyz1234567890"))
    }

    // MARK: - Table Rendering: Task Truncation

    @Test("renderTable truncates long task descriptions")
    func test_renderTable_truncatesLongTask() {
        let longTask = String(repeating: "x", count: 50)
        let session = makeSession(summary: longTask)
        let output = SessionsCommand.renderTable([session])

        #expect(output.contains(String(longTask.prefix(27)) + "..."))
    }

    // MARK: - Table Rendering: Duration Formatting

    @Test("renderTable formats seconds-only duration")
    func test_renderTable_durationSeconds() {
        let session = makeSession(durationMs: 5000)
        let output = SessionsCommand.renderTable([session])
        #expect(output.contains("5s"))
    }

    @Test("renderTable formats minutes and seconds duration")
    func test_renderTable_durationMinutesSeconds() {
        let session = makeSession(durationMs: 135_000) // 2m 15s
        let output = SessionsCommand.renderTable([session])
        #expect(output.contains("2m 15s"))
    }

    @Test("renderTable handles nil duration")
    func test_renderTable_nilDuration() {
        let session = makeSession(durationMs: nil)
        let output = SessionsCommand.renderTable([session])
        #expect(output.contains("-"))
    }

    @Test("renderTable shows <1s for sub-second duration")
    func test_renderTable_subSecondDuration() {
        let session = makeSession(durationMs: 500)
        let output = SessionsCommand.renderTable([session])
        #expect(output.contains("<1s"))
    }

    // MARK: - Table Rendering: Date Formatting

    @Test("renderTable formats date as yyyy-MM-dd HH:mm")
    func test_renderTable_dateFormat() {
        let date = DateComponents(
            calendar: .current,
            year: 2025, month: 5, day: 27,
            hour: 14, minute: 32
        ).date!
        let session = makeSession(createdAt: date)
        let output = SessionsCommand.renderTable([session])
        #expect(output.contains("2025-05-27"))
        #expect(output.contains("14:32"))
    }

    @Test("renderTable handles nil date")
    func test_renderTable_nilDate() {
        let session = makeSession(createdAt: nil)
        let output = SessionsCommand.renderTable([session])
        #expect(output.contains("-"))
    }

    // MARK: - Table Rendering: Nil Summary

    @Test("renderTable handles nil summary")
    func test_renderTable_nilSummary() {
        let session = makeSession(summary: nil)
        let output = SessionsCommand.renderTable([session])
        #expect(output.contains("-"))
    }

    // MARK: - Filtering: Active Only

    @Test("filterActive returns only running sessions")
    func test_filterActive_returnsRunningOnly() {
        let sessions = [
            makeSession(id: "1", status: "completed"),
            makeSession(id: "2", status: "running"),
            makeSession(id: "3", status: "failed"),
            makeSession(id: "4", status: "running"),
        ]
        let active = SessionsCommand.filterActive(sessions)
        #expect(active.count == 2)
        #expect(active.allSatisfy { $0.status == "running" })
    }

    @Test("filterActive returns empty when none running")
    func test_filterActive_noneRunning() {
        let sessions = [
            makeSession(id: "1", status: "completed"),
            makeSession(id: "2", status: "failed"),
        ]
        let active = SessionsCommand.filterActive(sessions)
        #expect(active.isEmpty)
    }

    // MARK: - Limit

    @Test("applyLimit truncates to given limit")
    func test_applyLimit_truncates() {
        let sessions = (0..<25).map { makeSession(id: "s\($0)") }
        let limited = SessionsCommand.applyLimit(sessions, limit: 5)
        #expect(limited.count == 5)
    }

    @Test("applyLimit returns all when under limit")
    func test_applyLimit_underLimit() {
        let sessions = (0..<3).map { makeSession(id: "s\($0)") }
        let limited = SessionsCommand.applyLimit(sessions, limit: 20)
        #expect(limited.count == 3)
    }

    // MARK: - Sorting

    @Test("sortByMostRecent sorts by createdAt descending")
    func test_sortByMostRecent() {
        let older = makeSession(id: "old", createdAt: Date(timeIntervalSince1970: 1000))
        let newer = makeSession(id: "new", createdAt: Date(timeIntervalSince1970: 2000))
        let nilDate = makeSession(id: "nil", createdAt: nil)

        let sorted = SessionsCommand.sortByMostRecent([older, newer, nilDate])
        #expect(sorted[0].sessionId == "new")
        #expect(sorted[1].sessionId == "old")
        #expect(sorted[2].sessionId == "nil")
    }

    // MARK: - Full Pipeline

    @Test("renderTable with multiple sessions shows all")
    func test_renderTable_multipleSessions() {
        let sessions = [
            makeSession(id: "aaa1", summary: "task a", status: "completed", totalSteps: 5, durationMs: 10_000),
            makeSession(id: "bbb2", summary: "task b", status: "failed", totalSteps: 2, durationMs: 3000),
        ]
        let output = SessionsCommand.renderTable(sessions)
        #expect(output.contains("aaa1"))
        #expect(output.contains("bbb2"))
        #expect(output.contains("task a"))
        #expect(output.contains("task b"))
        #expect(output.contains("completed"))
        #expect(output.contains("failed"))
    }
}
