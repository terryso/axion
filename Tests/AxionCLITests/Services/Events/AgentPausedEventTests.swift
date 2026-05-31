import Testing
import Foundation
@testable import AxionCLI

@Suite("AgentPausedEvent")
struct AgentPausedEventTests {

    @Test("AgentPausedEvent round-trip")
    func roundTrip() throws {
        let event = AgentPausedEvent(
            reason: "tool_approval",
            sessionId: "run-abc123",
            canResume: true,
            pendingId: "a1b2c3d4"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentPausedEvent.self, from: data)

        #expect(decoded.reason == "tool_approval")
        #expect(decoded.sessionId == "run-abc123")
        #expect(decoded.canResume == true)
        #expect(decoded.pendingId == "a1b2c3d4")
    }

    @Test("AgentPausedEvent encodes snake_case keys")
    func encoding() throws {
        let event = AgentPausedEvent(
            reason: "clarification_needed",
            sessionId: "s1",
            canResume: false,
            pendingId: "xyz123"
        )

        let data = try JSONEncoder().encode(event)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"session_id\":\"s1\""))
        #expect(json.contains("\"can_resume\":false"))
        #expect(json.contains("\"reason\":\"clarification_needed\""))
        #expect(json.contains("\"pending_id\":\"xyz123\""))
    }

    @Test("AgentPausedEvent has unique id and timestamp")
    func uniqueMetadata() {
        let event1 = AgentPausedEvent(reason: "a", sessionId: "s1", pendingId: "p1")
        let event2 = AgentPausedEvent(reason: "b", sessionId: "s2", pendingId: "p2")

        #expect(event1.id != event2.id)
        #expect(event1.timestamp <= event2.timestamp)
    }

    @Test("AgentPausedEvent canResume defaults to true")
    func canResumeDefault() {
        let event = AgentPausedEvent(reason: "test", sessionId: "s1", pendingId: "p1")
        #expect(event.canResume == true)
    }
}
