import XCTest
@testable import OpenAgentSDK

final class AgentEventTypesTests: XCTestCase {

    // MARK: - AgentEvent Protocol (AC1)

    func testAgentEventProtocolConformance() {
        func acceptEvent<T: AgentEvent>(_ event: T) {
            XCTAssertFalse(event.id.isEmpty)
            XCTAssertNotNil(event.timestamp)
        }
        let event = BaseAgentEvent()
        acceptEvent(event)
    }

    func testAgentEventProtocolIsSendable() {
        func acceptSendable<T: Sendable>(_ value: T) {
            _ = value
        }
        acceptSendable(BaseAgentEvent())
    }

    // MARK: - BaseAgentEvent (AC2)

    func testBaseAgentEventDefaultId() {
        let event = BaseAgentEvent()
        XCTAssertFalse(event.id.isEmpty)
        // Should be a valid UUID string
        XCTAssertNotNil(UUID(uuidString: event.id))
    }

    func testBaseAgentEventDefaultTimestamp() {
        let before = Date()
        let event = BaseAgentEvent()
        let after = Date()
        XCTAssertGreaterThanOrEqual(event.timestamp, before)
        XCTAssertLessThanOrEqual(event.timestamp, after)
    }

    func testBaseAgentEventUniqueIds() {
        let event1 = BaseAgentEvent()
        let event2 = BaseAgentEvent()
        XCTAssertNotEqual(event1.id, event2.id)
    }

    func testBaseAgentEventCustomInit() {
        let customId = "custom-id-123"
        let customDate = Date(timeIntervalSince1970: 1000000)
        let event = BaseAgentEvent(id: customId, timestamp: customDate)
        XCTAssertEqual(event.id, customId)
        XCTAssertEqual(event.timestamp, customDate)
    }

    // MARK: - BaseAgentEvent Codable (AC4)

    func testBaseAgentEventCodableRoundTrip() throws {
        let event = BaseAgentEvent(id: "test-id", timestamp: Date(timeIntervalSince1970: 1700000000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BaseAgentEvent.self, from: data)

        XCTAssertEqual(decoded.id, event.id)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince(event.timestamp), 0, accuracy: 1.0)
    }

    // MARK: - BaseAgentEvent Equatable (AC4)

    func testBaseAgentEventEquatableSameValues() {
        let id = "same-id"
        let ts = Date(timeIntervalSince1970: 1700000000)
        let event1 = BaseAgentEvent(id: id, timestamp: ts)
        let event2 = BaseAgentEvent(id: id, timestamp: ts)
        XCTAssertEqual(event1, event2)
    }

    func testBaseAgentEventEquatableDifferentIds() {
        let ts = Date(timeIntervalSince1970: 1700000000)
        let event1 = BaseAgentEvent(id: "id-1", timestamp: ts)
        let event2 = BaseAgentEvent(id: "id-2", timestamp: ts)
        XCTAssertNotEqual(event1, event2)
    }

    func testBaseAgentEventEquatableDifferentTimestamps() {
        let event1 = BaseAgentEvent(id: "same", timestamp: Date(timeIntervalSince1970: 1000))
        let event2 = BaseAgentEvent(id: "same", timestamp: Date(timeIntervalSince1970: 2000))
        XCTAssertNotEqual(event1, event2)
    }

    // MARK: - AgentEventCategory (AC3)

    func testAgentEventCategoryAllCases() {
        let allCases = AgentEventCategory.allCases
        XCTAssertEqual(allCases.count, 6)
        XCTAssertTrue(allCases.contains(.session))
        XCTAssertTrue(allCases.contains(.agent))
        XCTAssertTrue(allCases.contains(.tool))
        XCTAssertTrue(allCases.contains(.llm))
        XCTAssertTrue(allCases.contains(.memory))
        XCTAssertTrue(allCases.contains(.subAgent))
    }

    func testAgentEventCategoryRawValues() {
        XCTAssertEqual(AgentEventCategory.session.rawValue, "session")
        XCTAssertEqual(AgentEventCategory.agent.rawValue, "agent")
        XCTAssertEqual(AgentEventCategory.tool.rawValue, "tool")
        XCTAssertEqual(AgentEventCategory.llm.rawValue, "llm")
        XCTAssertEqual(AgentEventCategory.memory.rawValue, "memory")
        XCTAssertEqual(AgentEventCategory.subAgent.rawValue, "subAgent")
    }

    func testAgentEventCategoryCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for category in AgentEventCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(AgentEventCategory.self, from: data)
            XCTAssertEqual(decoded, category)
        }
    }

    func testAgentEventCategoryEquatable() {
        XCTAssertEqual(AgentEventCategory.session, AgentEventCategory.session)
        XCTAssertNotEqual(AgentEventCategory.session, AgentEventCategory.agent)
    }

    func testAgentEventCategorySendable() {
        func acceptSendable<T: Sendable>(_ value: T) {
            _ = value
        }
        acceptSendable(AgentEventCategory.tool)
    }

    // MARK: - Struct value type (AC4)

    func testBaseAgentEventIsValueType() {
        let event1 = BaseAgentEvent(id: "orig", timestamp: Date())
        let event2 = event1
        XCTAssertEqual(event1, event2)
    }

    // MARK: - Composition Pattern (AC1, AC2)

    /// Verifies the intended usage pattern: a custom struct composes BaseAgentEvent
    /// and forwards id/timestamp, rather than inheriting from a base class.
    func testCompositionPatternCustomEvent() {
        struct ToolCallEvent: AgentEvent, Codable {
            let base: BaseAgentEvent
            let toolName: String
            var id: String { base.id }
            var timestamp: Date { base.timestamp }
        }

        let event = ToolCallEvent(
            base: BaseAgentEvent(),
            toolName: "readFile"
        )
        XCTAssertFalse(event.id.isEmpty)
        XCTAssertNotNil(event.timestamp)
        XCTAssertEqual(event.toolName, "readFile")
    }

    func testCompositionPatternSendableConformance() {
        struct CustomEvent: AgentEvent, Codable {
            let base: BaseAgentEvent
            var id: String { base.id }
            var timestamp: Date { base.timestamp }
        }
        func acceptSendable<T: Sendable>(_ value: T) { _ = value }
        acceptSendable(CustomEvent(base: BaseAgentEvent()))
    }

    // MARK: - Existential Usage (AC1)

    /// Verifies that `any AgentEvent` works as an existential type —
    /// this is how EventBus will store and dispatch events.
    func testAgentEventExistentialUsage() {
        let events: [any AgentEvent] = [
            BaseAgentEvent(),
            BaseAgentEvent(id: "custom", timestamp: Date())
        ]
        XCTAssertEqual(events.count, 2)
        for event in events {
            XCTAssertFalse(event.id.isEmpty)
        }
    }

    func testAgentEventExistentialTypeErasure() {
        func getEvent() -> any AgentEvent {
            BaseAgentEvent(id: "erased", timestamp: Date(timeIntervalSince1970: 0))
        }
        let event = getEvent()
        XCTAssertEqual(event.id, "erased")
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 0))
    }

    // MARK: - JSON Key Structure (AC4)

    /// Verifies encoded JSON uses expected key names "id" and "timestamp".
    /// Epic 28 will rely on these key names for SSE mapping.
    func testBaseAgentEventJsonKeyStructure() throws {
        let event = BaseAgentEvent(id: "json-test", timestamp: Date(timeIntervalSince1970: 1700000000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["id"], "JSON should contain 'id' key")
        XCTAssertNotNil(json["timestamp"], "JSON should contain 'timestamp' key")
        XCTAssertEqual(json["id"] as? String, "json-test")
    }

    func testBaseAgentEventDecodingFromJson() throws {
        let jsonString = """
        {"id":"decoded-id","timestamp":"2023-11-15T00:00:00Z"}
        """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(BaseAgentEvent.self, from: data)

        XCTAssertEqual(event.id, "decoded-id")
    }

    // MARK: - Category JSON String Format (AC3)

    /// Verifies each category encodes to its raw string value in JSON.
    func testAgentEventCategoryJsonStringValue() throws {
        let encoder = JSONEncoder()
        for category in AgentEventCategory.allCases {
            let data = try encoder.encode(category)
            let jsonString = String(data: data, encoding: .utf8)!
            // JSONEncoder wraps strings in quotes
            XCTAssertEqual(jsonString, "\"\(category.rawValue)\"")
        }
    }

    // MARK: - Edge Cases

    func testBaseAgentEventEmptyStringId() {
        let event = BaseAgentEvent(id: "", timestamp: Date())
        XCTAssertTrue(event.id.isEmpty)
    }

    func testBaseAgentEventDistantPastTimestamp() {
        let event = BaseAgentEvent(timestamp: Date.distantPast)
        XCTAssertEqual(event.timestamp, Date.distantPast)
    }

    func testBaseAgentEventDistantFutureTimestamp() {
        let event = BaseAgentEvent(timestamp: Date.distantFuture)
        XCTAssertEqual(event.timestamp, Date.distantFuture)
    }

    // MARK: - Concurrent Access (AC4)

    /// Verifies BaseAgentEvent can safely cross actor boundaries.
    func testBaseAgentEventSendableAcrossActor() async {
        let event = BaseAgentEvent(id: "concurrent-test", timestamp: Date())
        let retrieved = await Self.echoActor.send(event)
        XCTAssertEqual(retrieved.id, "concurrent-test")
    }

    /// Verifies AgentEventCategory can safely cross actor boundaries.
    func testAgentEventCategorySendableAcrossActor() async {
        let category = AgentEventCategory.tool
        let retrieved = await Self.echoActor.sendCategory(category)
        XCTAssertEqual(retrieved, .tool)
    }
}

// MARK: - Test Helpers

private extension AgentEventTypesTests {
    actor EchoActor {
        func send(_ event: BaseAgentEvent) -> BaseAgentEvent { event }
        func sendCategory(_ category: AgentEventCategory) -> AgentEventCategory { category }
    }

    static let echoActor = EchoActor()
}
