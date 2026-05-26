import Testing
import Foundation
@testable import AxionCore

@Suite("SessionInfo")
struct SessionInfoTests {

    @Test("SessionInfo construction with defaults")
    func constructionWithDefaults() {
        let info = SessionInfo(
            sessionId: "test-123",
            cwd: "/tmp",
            model: "claude-sonnet"
        )
        #expect(info.sessionId == "test-123")
        #expect(info.cwd == "/tmp")
        #expect(info.model == "claude-sonnet")
        #expect(info.createdAt == nil)
        #expect(info.updatedAt == nil)
        #expect(info.messageCount == 0)
        #expect(info.summary == nil)
        #expect(info.status == "unknown")
        #expect(info.totalSteps == 0)
        #expect(info.durationMs == nil)
    }

    @Test("SessionInfo construction with all fields")
    func constructionWithAllFields() {
        let now = Date()
        let info = SessionInfo(
            sessionId: "s-1",
            cwd: "/home",
            model: "opus",
            createdAt: now,
            updatedAt: now,
            messageCount: 5,
            summary: "test session",
            status: "completed",
            totalSteps: 10,
            durationMs: 5000
        )
        #expect(info.sessionId == "s-1")
        #expect(info.status == "completed")
        #expect(info.totalSteps == 10)
        #expect(info.durationMs == 5000)
        #expect(info.messageCount == 5)
        #expect(info.summary == "test session")
    }

    @Test("SessionInfo Equatable conformance")
    func equatable() {
        let a = SessionInfo(sessionId: "1", cwd: "/tmp", model: "m", status: "running", totalSteps: 3)
        let b = SessionInfo(sessionId: "1", cwd: "/tmp", model: "m", status: "running", totalSteps: 3)
        let c = SessionInfo(sessionId: "2", cwd: "/tmp", model: "m", status: "running", totalSteps: 3)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("SessionInfo Codable round-trip")
    func codable() throws {
        let info = SessionInfo(
            sessionId: "sid-123",
            cwd: "/root",
            model: "haiku",
            messageCount: 7,
            status: "completed",
            totalSteps: 42,
            durationMs: 3000
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(SessionInfo.self, from: data)
        #expect(decoded == info)
    }

    @Test("SessionInfo without overlay uses defaults (AC #7)")
    func withoutOverlay() {
        let info = SessionInfo(
            sessionId: "sdk-only",
            cwd: "/tmp",
            model: "sonnet",
            messageCount: 3
        )
        #expect(info.status == "unknown")
        #expect(info.totalSteps == 0)
        #expect(info.durationMs == nil)
    }
}

@Suite("AxionStateOverlay")
struct AxionStateOverlayTests {

    @Test("AxionStateOverlay Codable round-trip")
    func codable() throws {
        let overlay = AxionStateOverlay(
            status: "completed",
            totalSteps: 15,
            durationMs: 8000,
            updatedAt: "2026-05-27T12:00:00Z"
        )
        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(AxionStateOverlay.self, from: data)
        #expect(decoded.status == "completed")
        #expect(decoded.totalSteps == 15)
        #expect(decoded.durationMs == 8000)
        #expect(decoded.updatedAt == "2026-05-27T12:00:00Z")
    }

    @Test("AxionStateOverlay with nil durationMs")
    func nilDurationMs() throws {
        let overlay = AxionStateOverlay(
            status: "created",
            totalSteps: 0,
            durationMs: nil,
            updatedAt: "2026-05-27T00:00:00Z"
        )
        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(AxionStateOverlay.self, from: data)
        #expect(decoded.durationMs == nil)
    }
}
