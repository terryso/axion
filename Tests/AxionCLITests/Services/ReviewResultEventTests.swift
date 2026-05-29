import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI

@Suite("ReviewResultEvent")
struct ReviewResultEventTests {

    @Test("Constructor sets all fields correctly")
    func testConstructor() {
        let event = ReviewResultEvent(
            summary: "review done",
            memoryChanges: ["mem-1", "mem-2"],
            skillChanges: ["skill-1"],
            success: true,
            durationMs: 500,
            sessionId: "s-123"
        )

        #expect(event.summary == "review done")
        #expect(event.memoryChanges == ["mem-1", "mem-2"])
        #expect(event.skillChanges == ["skill-1"])
        #expect(event.success == true)
        #expect(event.durationMs == 500)
        #expect(event.sessionId == "s-123")
        #expect(!event.id.isEmpty)
    }

    @Test("Failure event has success=false")
    func testFailureEvent() {
        let event = ReviewResultEvent(
            summary: "review agent returned nil",
            memoryChanges: [],
            skillChanges: [],
            success: false,
            durationMs: 100,
            sessionId: "s-fail"
        )

        #expect(event.success == false)
        #expect(event.memoryChanges.isEmpty)
        #expect(event.skillChanges.isEmpty)
    }

    @Test("Codable round-trip preserves all fields")
    func testCodableRoundTrip() throws {
        let event = ReviewResultEvent(
            summary: "summary text",
            memoryChanges: ["m1"],
            skillChanges: ["s1", "s2"],
            success: true,
            durationMs: 1234,
            sessionId: "sess-abc"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ReviewResultEvent.self, from: data)

        #expect(decoded.summary == event.summary)
        #expect(decoded.memoryChanges == event.memoryChanges)
        #expect(decoded.skillChanges == event.skillChanges)
        #expect(decoded.success == event.success)
        #expect(decoded.durationMs == event.durationMs)
        #expect(decoded.sessionId == event.sessionId)
        #expect(decoded.id == event.id)
    }

    @Test("JSON encoding uses snake_case keys")
    func testSnakeCaseKeys() throws {
        let event = ReviewResultEvent(
            summary: "test",
            memoryChanges: [],
            skillChanges: [],
            success: true,
            durationMs: 0,
            sessionId: "s1"
        )

        let data = try JSONEncoder().encode(event)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"memory_changes\""))
        #expect(json.contains("\"skill_changes\""))
        #expect(json.contains("\"duration_ms\""))
        #expect(json.contains("\"session_id\""))
    }
}
