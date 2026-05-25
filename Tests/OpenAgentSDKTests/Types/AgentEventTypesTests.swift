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

// MARK: - Session Lifecycle Events

extension AgentEventTypesTests {

    // MARK: - SessionFinalStatus (AC3)

    func testSessionFinalStatusAllCases() {
        let allCases = SessionFinalStatus.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.completed))
        XCTAssertTrue(allCases.contains(.failed))
        XCTAssertTrue(allCases.contains(.interrupted))
    }

    func testSessionFinalStatusRawValues() {
        XCTAssertEqual(SessionFinalStatus.completed.rawValue, "completed")
        XCTAssertEqual(SessionFinalStatus.failed.rawValue, "failed")
        XCTAssertEqual(SessionFinalStatus.interrupted.rawValue, "interrupted")
    }

    func testSessionFinalStatusCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for status in SessionFinalStatus.allCases {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(SessionFinalStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testSessionFinalStatusSendable() {
        func acceptSendable<T: Sendable>(_ value: T) { _ = value }
        acceptSendable(SessionFinalStatus.completed)
    }

    // MARK: - SessionCreatedEvent (AC1)

    func testSessionCreatedEventConstruction() {
        let event = SessionCreatedEvent(sessionId: "sess-1", task: "build app", model: "claude-sonnet-4-6")
        XCTAssertEqual(event.sessionId, "sess-1")
        XCTAssertEqual(event.task, "build app")
        XCTAssertEqual(event.model, "claude-sonnet-4-6")
        XCTAssertFalse(event.id.isEmpty)
        XCTAssertNotNil(event.timestamp)
    }

    func testSessionCreatedEventNilSessionId() {
        let event = SessionCreatedEvent(sessionId: nil, task: "hello", model: "gpt-4")
        XCTAssertNil(event.sessionId)
    }

    func testSessionCreatedEventAgentEventConformance() {
        func acceptEvent<T: AgentEvent>(_ event: T) {
            XCTAssertFalse(event.id.isEmpty)
            XCTAssertNotNil(event.timestamp)
        }
        let event = SessionCreatedEvent(sessionId: "s", task: "t", model: "m")
        acceptEvent(event)
    }

    func testSessionCreatedEventSendable() {
        func acceptSendable<T: Sendable>(_ value: T) { _ = value }
        acceptSendable(SessionCreatedEvent(sessionId: nil, task: "t", model: "m"))
    }

    func testSessionCreatedEventCodableRoundTrip() throws {
        let event = SessionCreatedEvent(sessionId: "sess-42", task: "write tests", model: "claude-sonnet-4-6")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionCreatedEvent.self, from: data)

        XCTAssertEqual(decoded.id, event.id)
        XCTAssertEqual(decoded.sessionId, event.sessionId)
        XCTAssertEqual(decoded.task, event.task)
        XCTAssertEqual(decoded.model, event.model)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince(event.timestamp), 0, accuracy: 1.0)
    }

    func testSessionCreatedEventSnakeCaseJsonKeys() throws {
        let event = SessionCreatedEvent(sessionId: "s1", task: "t", model: "m")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["session_id"], "JSON should use snake_case 'session_id'")
        XCTAssertNotNil(json["task"])
        XCTAssertNotNil(json["model"])
        XCTAssertNotNil(json["id"])
        XCTAssertNotNil(json["timestamp"])
    }

    func testSessionCreatedEventEquatable() {
        let id = "same-id"
        let ts = Date(timeIntervalSince1970: 1700000000)
        let e1 = SessionCreatedEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", task: "t", model: "m")
        let e2 = SessionCreatedEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", task: "t", model: "m")
        XCTAssertEqual(e1, e2)
    }

    func testSessionCreatedEventInitWithBase() {
        let event = SessionCreatedEvent(base: BaseAgentEvent(id: "custom", timestamp: Date(timeIntervalSince1970: 0)), sessionId: "s", task: "t", model: "m")
        XCTAssertEqual(event.id, "custom")
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 0))
    }

    // MARK: - SessionRestoredEvent (AC2)

    func testSessionRestoredEventConstruction() {
        let createdAt = Date(timeIntervalSince1970: 1700000000)
        let event = SessionRestoredEvent(sessionId: "sess-1", messageCount: 5, originalCreatedAt: createdAt)
        XCTAssertEqual(event.sessionId, "sess-1")
        XCTAssertEqual(event.messageCount, 5)
        XCTAssertEqual(event.originalCreatedAt, createdAt)
        XCTAssertFalse(event.id.isEmpty)
    }

    func testSessionRestoredEventNilSessionId() {
        let event = SessionRestoredEvent(sessionId: nil, messageCount: 0, originalCreatedAt: Date())
        XCTAssertNil(event.sessionId)
    }

    func testSessionRestoredEventAgentEventConformance() {
        func acceptEvent<T: AgentEvent>(_ event: T) {
            XCTAssertFalse(event.id.isEmpty)
        }
        let event = SessionRestoredEvent(sessionId: "s", messageCount: 3, originalCreatedAt: Date())
        acceptEvent(event)
    }

    func testSessionRestoredEventSendable() {
        func acceptSendable<T: Sendable>(_ value: T) { _ = value }
        acceptSendable(SessionRestoredEvent(sessionId: nil, messageCount: 0, originalCreatedAt: Date()))
    }

    func testSessionRestoredEventCodableRoundTrip() throws {
        let createdAt = Date(timeIntervalSince1970: 1700000000)
        let event = SessionRestoredEvent(sessionId: "sess-1", messageCount: 10, originalCreatedAt: createdAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionRestoredEvent.self, from: data)

        XCTAssertEqual(decoded.sessionId, event.sessionId)
        XCTAssertEqual(decoded.messageCount, event.messageCount)
        XCTAssertEqual(decoded.originalCreatedAt.timeIntervalSince(event.originalCreatedAt), 0, accuracy: 1.0)
    }

    func testSessionRestoredEventSnakeCaseJsonKeys() throws {
        let event = SessionRestoredEvent(sessionId: "s", messageCount: 5, originalCreatedAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["session_id"])
        XCTAssertNotNil(json["message_count"])
        XCTAssertNotNil(json["original_created_at"])
    }

    // MARK: - SessionClosedEvent (AC3)

    func testSessionClosedEventConstruction() {
        let event = SessionClosedEvent(sessionId: "sess-1", finalStatus: .completed)
        XCTAssertEqual(event.sessionId, "sess-1")
        XCTAssertEqual(event.finalStatus, .completed)
    }

    func testSessionClosedEventAllFinalStatuses() {
        for status in SessionFinalStatus.allCases {
            let event = SessionClosedEvent(sessionId: nil, finalStatus: status)
            XCTAssertEqual(event.finalStatus, status)
        }
    }

    func testSessionClosedEventAgentEventConformance() {
        func acceptEvent<T: AgentEvent>(_ event: T) {
            XCTAssertFalse(event.id.isEmpty)
        }
        let event = SessionClosedEvent(sessionId: "s", finalStatus: .failed)
        acceptEvent(event)
    }

    func testSessionClosedEventSendable() {
        func acceptSendable<T: Sendable>(_ value: T) { _ = value }
        acceptSendable(SessionClosedEvent(sessionId: nil, finalStatus: .interrupted))
    }

    func testSessionClosedEventCodableRoundTrip() throws {
        let event = SessionClosedEvent(sessionId: "sess-1", finalStatus: .failed)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionClosedEvent.self, from: data)

        XCTAssertEqual(decoded.sessionId, event.sessionId)
        XCTAssertEqual(decoded.finalStatus, event.finalStatus)
    }

    func testSessionClosedEventSnakeCaseJsonKeys() throws {
        let event = SessionClosedEvent(sessionId: "s", finalStatus: .completed)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["session_id"])
        XCTAssertNotNil(json["final_status"])
    }

    // MARK: - SessionAutoSavedEvent (AC4)

    func testSessionAutoSavedEventConstruction() {
        let event = SessionAutoSavedEvent(sessionId: "sess-1", messageCount: 12)
        XCTAssertEqual(event.sessionId, "sess-1")
        XCTAssertEqual(event.messageCount, 12)
        XCTAssertFalse(event.id.isEmpty)
    }

    func testSessionAutoSavedEventNilSessionId() {
        let event = SessionAutoSavedEvent(sessionId: nil, messageCount: 0)
        XCTAssertNil(event.sessionId)
    }

    func testSessionAutoSavedEventAgentEventConformance() {
        func acceptEvent<T: AgentEvent>(_ event: T) {
            XCTAssertFalse(event.id.isEmpty)
        }
        let event = SessionAutoSavedEvent(sessionId: "s", messageCount: 5)
        acceptEvent(event)
    }

    func testSessionAutoSavedEventSendable() {
        func acceptSendable<T: Sendable>(_ value: T) { _ = value }
        acceptSendable(SessionAutoSavedEvent(sessionId: nil, messageCount: 0))
    }

    func testSessionAutoSavedEventCodableRoundTrip() throws {
        let event = SessionAutoSavedEvent(sessionId: "sess-1", messageCount: 7)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionAutoSavedEvent.self, from: data)

        XCTAssertEqual(decoded.sessionId, event.sessionId)
        XCTAssertEqual(decoded.messageCount, event.messageCount)
    }

    func testSessionAutoSavedEventSnakeCaseJsonKeys() throws {
        let event = SessionAutoSavedEvent(sessionId: "s", messageCount: 3)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["session_id"])
        XCTAssertNotNil(json["message_count"])
    }

    // MARK: - Session Events Existential Usage (AC5)

    func testSessionEventsAsAgentEventExistential() {
        let events: [any AgentEvent] = [
            SessionCreatedEvent(sessionId: "s1", task: "t", model: "m"),
            SessionRestoredEvent(sessionId: "s2", messageCount: 3, originalCreatedAt: Date()),
            SessionClosedEvent(sessionId: "s3", finalStatus: .completed),
            SessionAutoSavedEvent(sessionId: "s4", messageCount: 5)
        ]
        XCTAssertEqual(events.count, 4)
        for event in events {
            XCTAssertFalse(event.id.isEmpty)
            XCTAssertNotNil(event.timestamp)
        }
    }

    func testSessionEventsSendableAcrossActor() async {
        let event = SessionCreatedEvent(sessionId: "s", task: "t", model: "m")
        let retrieved = await Self.sessionEchoActor.send(event)
        XCTAssertEqual(retrieved.task, "t")
    }

    // MARK: - All Payload Fields Are Immutable (AC5)

    func testSessionCreatedEventImmutablePayload() {
        let event = SessionCreatedEvent(sessionId: "s", task: "t", model: "m")
        // These are `let` properties — compilation proves immutability
        XCTAssertEqual(event.sessionId, "s")
        XCTAssertEqual(event.task, "t")
        XCTAssertEqual(event.model, "m")
    }

    func testSessionClosedEventImmutablePayload() {
        let event = SessionClosedEvent(sessionId: "s", finalStatus: .failed)
        XCTAssertEqual(event.finalStatus, .failed)
    }

    func testSessionRestoredEventImmutablePayload() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let event = SessionRestoredEvent(sessionId: "s", messageCount: 5, originalCreatedAt: date)
        XCTAssertEqual(event.sessionId, "s")
        XCTAssertEqual(event.messageCount, 5)
        XCTAssertEqual(event.originalCreatedAt, date)
    }

    func testSessionAutoSavedEventImmutablePayload() {
        let event = SessionAutoSavedEvent(sessionId: "s", messageCount: 7)
        XCTAssertEqual(event.sessionId, "s")
        XCTAssertEqual(event.messageCount, 7)
    }

    // MARK: - SessionRestoredEvent Equatable (AC2)

    func testSessionRestoredEventEquatable() {
        let id = "eq-id"
        let ts = Date(timeIntervalSince1970: 1700000000)
        let createdAt = Date(timeIntervalSince1970: 1600000000)
        let e1 = SessionRestoredEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", messageCount: 3, originalCreatedAt: createdAt)
        let e2 = SessionRestoredEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", messageCount: 3, originalCreatedAt: createdAt)
        XCTAssertEqual(e1, e2)
    }

    func testSessionRestoredEventNotEqualDifferentMessageCount() {
        let id = "eq-id"
        let ts = Date(timeIntervalSince1970: 1700000000)
        let createdAt = Date(timeIntervalSince1970: 1600000000)
        let e1 = SessionRestoredEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", messageCount: 3, originalCreatedAt: createdAt)
        let e2 = SessionRestoredEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", messageCount: 5, originalCreatedAt: createdAt)
        XCTAssertNotEqual(e1, e2)
    }

    // MARK: - SessionClosedEvent Equatable (AC3)

    func testSessionClosedEventEquatable() {
        let id = "eq-id"
        let ts = Date(timeIntervalSince1970: 1700000000)
        let e1 = SessionClosedEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", finalStatus: .completed)
        let e2 = SessionClosedEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", finalStatus: .completed)
        XCTAssertEqual(e1, e2)
    }

    func testSessionClosedEventNotEqualDifferentStatus() {
        let id = "eq-id"
        let ts = Date(timeIntervalSince1970: 1700000000)
        let e1 = SessionClosedEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", finalStatus: .completed)
        let e2 = SessionClosedEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", finalStatus: .failed)
        XCTAssertNotEqual(e1, e2)
    }

    // MARK: - SessionAutoSavedEvent Equatable (AC4)

    func testSessionAutoSavedEventEquatable() {
        let id = "eq-id"
        let ts = Date(timeIntervalSince1970: 1700000000)
        let e1 = SessionAutoSavedEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", messageCount: 5)
        let e2 = SessionAutoSavedEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", messageCount: 5)
        XCTAssertEqual(e1, e2)
    }

    func testSessionAutoSavedEventNotEqualDifferentCount() {
        let id = "eq-id"
        let ts = Date(timeIntervalSince1970: 1700000000)
        let e1 = SessionAutoSavedEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", messageCount: 3)
        let e2 = SessionAutoSavedEvent(base: BaseAgentEvent(id: id, timestamp: ts), sessionId: "s", messageCount: 7)
        XCTAssertNotEqual(e1, e2)
    }

    // MARK: - Init with Base (AC5)

    func testSessionRestoredEventInitWithBase() {
        let event = SessionRestoredEvent(
            base: BaseAgentEvent(id: "custom-base", timestamp: Date(timeIntervalSince1970: 0)),
            sessionId: "s", messageCount: 10, originalCreatedAt: Date(timeIntervalSince1970: 999)
        )
        XCTAssertEqual(event.id, "custom-base")
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(event.messageCount, 10)
    }

    func testSessionClosedEventInitWithBase() {
        let event = SessionClosedEvent(
            base: BaseAgentEvent(id: "closed-base", timestamp: Date(timeIntervalSince1970: 42)),
            sessionId: nil, finalStatus: .interrupted
        )
        XCTAssertEqual(event.id, "closed-base")
        XCTAssertEqual(event.finalStatus, .interrupted)
    }

    func testSessionAutoSavedEventInitWithBase() {
        let event = SessionAutoSavedEvent(
            base: BaseAgentEvent(id: "autosave-base", timestamp: Date(timeIntervalSince1970: 100)),
            sessionId: "s", messageCount: 20
        )
        XCTAssertEqual(event.id, "autosave-base")
        XCTAssertEqual(event.messageCount, 20)
    }

    // MARK: - Codable Decode from Raw JSON (AC1-AC4)

    func testSessionCreatedEventDecodeFromRawJson() throws {
        let jsonString = """
        {"id":"raw-id","timestamp":"2024-01-15T12:00:00Z","session_id":"raw-sess","task":"raw task","model":"raw-model"}
        """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(SessionCreatedEvent.self, from: data)

        XCTAssertEqual(event.id, "raw-id")
        XCTAssertEqual(event.sessionId, "raw-sess")
        XCTAssertEqual(event.task, "raw task")
        XCTAssertEqual(event.model, "raw-model")
    }

    func testSessionRestoredEventDecodeFromRawJson() throws {
        let jsonString = """
        {"id":"rest-id","timestamp":"2024-01-15T12:00:00Z","session_id":"rest-sess","message_count":15,"original_created_at":"2023-06-01T00:00:00Z"}
        """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(SessionRestoredEvent.self, from: data)

        XCTAssertEqual(event.id, "rest-id")
        XCTAssertEqual(event.messageCount, 15)
        XCTAssertEqual(event.originalCreatedAt, Date(timeIntervalSince1970: 1685577600))
    }

    func testSessionClosedEventDecodeFromRawJson() throws {
        let jsonString = """
        {"id":"close-id","timestamp":"2024-01-15T12:00:00Z","session_id":"close-sess","final_status":"interrupted"}
        """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(SessionClosedEvent.self, from: data)

        XCTAssertEqual(event.id, "close-id")
        XCTAssertEqual(event.finalStatus, .interrupted)
    }

    func testSessionAutoSavedEventDecodeFromRawJson() throws {
        let jsonString = """
        {"id":"auto-id","timestamp":"2024-01-15T12:00:00Z","session_id":"auto-sess","message_count":8}
        """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(SessionAutoSavedEvent.self, from: data)

        XCTAssertEqual(event.id, "auto-id")
        XCTAssertEqual(event.messageCount, 8)
    }

    // MARK: - Nil SessionId Codable Decode (AC3, AC4)

    func testSessionClosedEventDecodeNilSessionId() throws {
        let jsonString = """
        {"id":"n","timestamp":"2024-01-15T12:00:00Z","session_id":null,"final_status":"completed"}
        """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(SessionClosedEvent.self, from: data)
        XCTAssertNil(event.sessionId)
        XCTAssertEqual(event.finalStatus, .completed)
    }

    func testSessionAutoSavedEventDecodeNilSessionId() throws {
        let jsonString = """
        {"id":"n","timestamp":"2024-01-15T12:00:00Z","session_id":null,"message_count":3}
        """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(SessionAutoSavedEvent.self, from: data)
        XCTAssertNil(event.sessionId)
        XCTAssertEqual(event.messageCount, 3)
    }

    // MARK: - Codable Error Cases (AC1-AC4)

    func testSessionCreatedEventDecodeMissingRequiredField() {
        let jsonString = """
        {"id":"bad","timestamp":"2024-01-15T12:00:00Z"}
        """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(SessionCreatedEvent.self, from: data))
    }

    func testSessionClosedEventDecodeInvalidFinalStatus() {
        let jsonString = """
        {"id":"bad","timestamp":"2024-01-15T12:00:00Z","final_status":"unknown_status"}
        """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(SessionClosedEvent.self, from: data))
    }

    func testSessionFinalStatusDecodeFromInvalidString() {
        let jsonString = "\"not_a_status\""
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(SessionFinalStatus.self, from: data))
    }

    // MARK: - SessionRestoredEvent Codable nil sessionId decode (AC2)

    func testSessionRestoredEventDecodeNilSessionId() throws {
        let jsonString = """
        {"id":"n","timestamp":"2024-01-15T12:00:00Z","session_id":null,"message_count":0,"original_created_at":"2024-01-01T00:00:00Z"}
        """
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(SessionRestoredEvent.self, from: data)
        XCTAssertNil(event.sessionId)
    }

    // MARK: - Actor Boundary for All Event Types (AC5)

    func testSessionRestoredEventSendableAcrossActor() async {
        let event = SessionRestoredEvent(sessionId: "s", messageCount: 3, originalCreatedAt: Date())
        let retrieved = await Self.sessionRestoredEchoActor.send(event)
        XCTAssertEqual(retrieved.messageCount, 3)
    }

    func testSessionClosedEventSendableAcrossActor() async {
        let event = SessionClosedEvent(sessionId: "s", finalStatus: .failed)
        let retrieved = await Self.sessionClosedEchoActor.send(event)
        XCTAssertEqual(retrieved.finalStatus, .failed)
    }

    func testSessionAutoSavedEventSendableAcrossActor() async {
        let event = SessionAutoSavedEvent(sessionId: "s", messageCount: 42)
        let retrieved = await Self.sessionAutoSavedEchoActor.send(event)
        XCTAssertEqual(retrieved.messageCount, 42)
    }

    // MARK: - Edge Cases

    func testSessionCreatedEventEmptyTask() {
        let event = SessionCreatedEvent(sessionId: "s", task: "", model: "m")
        XCTAssertEqual(event.task, "")
    }

    func testSessionRestoredEventZeroMessageCount() {
        let event = SessionRestoredEvent(sessionId: nil, messageCount: 0, originalCreatedAt: Date())
        XCTAssertEqual(event.messageCount, 0)
    }

    func testSessionAutoSavedEventZeroMessageCount() {
        let event = SessionAutoSavedEvent(sessionId: nil, messageCount: 0)
        XCTAssertEqual(event.messageCount, 0)
    }

    func testSessionCreatedEventEncodedJsonValueTypes() throws {
        let event = SessionCreatedEvent(sessionId: "s1", task: "t", model: "m")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertTrue(json["id"] is String)
        XCTAssertTrue(json["timestamp"] is String)
        XCTAssertTrue(json["session_id"] is String)
        XCTAssertTrue(json["task"] is String)
        XCTAssertTrue(json["model"] is String)
        XCTAssertEqual(json["session_id"] as? String, "s1")
        XCTAssertEqual(json["task"] as? String, "t")
        XCTAssertEqual(json["model"] as? String, "m")
    }

    func testSessionClosedEventEncodedFinalStatusValue() throws {
        let event = SessionClosedEvent(sessionId: "s", finalStatus: .completed)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["final_status"] as? String, "completed")
    }
}

// MARK: - Session Event Test Helpers

private extension AgentEventTypesTests {
    actor SessionEchoActor {
        func send(_ event: SessionCreatedEvent) -> SessionCreatedEvent { event }
    }

    actor SessionRestoredEchoActor {
        func send(_ event: SessionRestoredEvent) -> SessionRestoredEvent { event }
    }

    actor SessionClosedEchoActor {
        func send(_ event: SessionClosedEvent) -> SessionClosedEvent { event }
    }

    actor SessionAutoSavedEchoActor {
        func send(_ event: SessionAutoSavedEvent) -> SessionAutoSavedEvent { event }
    }

    static let sessionEchoActor = SessionEchoActor()
    static let sessionRestoredEchoActor = SessionRestoredEchoActor()
    static let sessionClosedEchoActor = SessionClosedEchoActor()
    static let sessionAutoSavedEchoActor = SessionAutoSavedEchoActor()
}
