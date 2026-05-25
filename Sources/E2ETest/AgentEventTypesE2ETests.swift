import Foundation
import OpenAgentSDK

// MARK: - Tests 87-92: Agent Event Types E2E Tests (Story 26.2)

/// E2E tests for session lifecycle event types: construction, Codable round-trip,
/// concurrent usage, existential dispatch, and JSON format validation.
/// No mocks — uses real JSONEncoder/JSONDecoder and real concurrency primitives.
struct AgentEventTypesE2ETests {
    static func run() async {
        section("87-92. Agent Event Types (E2E — Story 26.2)")
        await testSessionCreatedEvent_fullLifecycle()
        await testSessionRestoredEvent_codableRoundTrip()
        await testSessionClosedEvent_allStatuses()
        await testSessionAutoSavedEvent_concurrentUsage()
        await testSessionEvents_existentialDispatch()
        await testSessionEvents_jsonFormatSseCompatible()
    }

    // MARK: Test 87: SessionCreatedEvent full lifecycle

    /// AC1 [P0]: Construct, serialize, deserialize, verify all fields survive round-trip.
    static func testSessionCreatedEvent_fullLifecycle() async {
        let event = SessionCreatedEvent(
            sessionId: "e2e-sess-created-\(UUID().uuidString)",
            task: "Build a real-time event system",
            model: "claude-sonnet-4-6"
        )

        // Verify construction
        guard !event.id.isEmpty else {
            fail("SessionCreatedEvent lifecycle", "id is empty")
            return
        }
        guard event.sessionId != nil else {
            fail("SessionCreatedEvent lifecycle", "sessionId should not be nil")
            return
        }

        // Encode → JSON → Decode
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(SessionCreatedEvent.self, from: data)

            guard decoded.id == event.id else {
                fail("SessionCreatedEvent lifecycle", "id mismatch: \(decoded.id) != \(event.id)")
                return
            }
            guard decoded.sessionId == event.sessionId else {
                fail("SessionCreatedEvent lifecycle", "sessionId mismatch")
                return
            }
            guard decoded.task == event.task else {
                fail("SessionCreatedEvent lifecycle", "task mismatch")
                return
            }
            guard decoded.model == event.model else {
                fail("SessionCreatedEvent lifecycle", "model mismatch")
                return
            }
            pass("87. SessionCreatedEvent full lifecycle (construct → encode → decode → verify)")
        } catch {
            fail("SessionCreatedEvent lifecycle", "Codable error: \(error)")
        }
    }

    // MARK: Test 88: SessionRestoredEvent Codable round-trip with real Date

    /// AC2 [P0]: Verify Date precision survives serialization (originalCreatedAt).
    static func testSessionRestoredEvent_codableRoundTrip() async {
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let event = SessionRestoredEvent(
            sessionId: "e2e-sess-restored-\(UUID().uuidString)",
            messageCount: 42,
            originalCreatedAt: originalDate
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(SessionRestoredEvent.self, from: data)

            guard decoded.messageCount == 42 else {
                fail("SessionRestoredEvent Codable", "messageCount mismatch: \(decoded.messageCount)")
                return
            }
            // ISO 8601 round-trip should preserve the timestamp within 1 second
            let delta = abs(decoded.originalCreatedAt.timeIntervalSince(originalDate))
            guard delta < 1.0 else {
                fail("SessionRestoredEvent Codable", "Date drift: \(delta)s")
                return
            }
            pass("88. SessionRestoredEvent Codable round-trip with Date precision")
        } catch {
            fail("SessionRestoredEvent Codable", "error: \(error)")
        }
    }

    // MARK: Test 89: SessionClosedEvent all final statuses

    /// AC3 [P0]: Create events for each SessionFinalStatus, serialize, verify status survives.
    static func testSessionClosedEvent_allStatuses() async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for status in SessionFinalStatus.allCases {
            let event = SessionClosedEvent(sessionId: "e2e-close-\(status.rawValue)", finalStatus: status)
            do {
                let data = try encoder.encode(event)
                let decoded = try decoder.decode(SessionClosedEvent.self, from: data)
                guard decoded.finalStatus == status else {
                    fail("SessionClosedEvent status \(status.rawValue)", "status mismatch: \(decoded.finalStatus)")
                    return
                }
            } catch {
                fail("SessionClosedEvent status \(status.rawValue)", "error: \(error)")
                return
            }
        }
        pass("89. SessionClosedEvent all 3 final statuses round-trip correctly")
    }

    // MARK: Test 90: SessionAutoSavedEvent concurrent usage

    /// AC4, AC5 [P0]: Events cross actor boundaries safely (Sendable in practice).
    static func testSessionAutoSavedEvent_concurrentUsage() async {
        let event = SessionAutoSavedEvent(sessionId: "e2e-autosave-\(UUID().uuidString)", messageCount: 99)
        let retrieved = await Self.testActor.sendAutoSaved(event)
        guard retrieved.messageCount == 99, retrieved.sessionId == event.sessionId else {
            fail("SessionAutoSavedEvent concurrent", "data corrupted after actor crossing")
            return
        }
        pass("90. SessionAutoSavedEvent concurrent usage across actor boundary")
    }

    // MARK: Test 91: All session events as existential AgentEvent

    /// AC5 [P0]: All 4 event types work as `any AgentEvent` — the pattern EventBus will use.
    static func testSessionEvents_existentialDispatch() async {
        let events: [any AgentEvent] = [
            SessionCreatedEvent(sessionId: "e2e-ex-1", task: "dispatch test", model: "test-model"),
            SessionRestoredEvent(sessionId: "e2e-ex-2", messageCount: 10, originalCreatedAt: Date()),
            SessionClosedEvent(sessionId: "e2e-ex-3", finalStatus: .completed),
            SessionAutoSavedEvent(sessionId: "e2e-ex-4", messageCount: 5),
        ]

        for event in events {
            guard !event.id.isEmpty else {
                fail("Existential dispatch", "event has empty id: \(type(of: event))")
                return
            }
        }

        // Encode as existential (type-erased) — verify each can be stored and accessed
        func dispatch(_ event: any AgentEvent) -> String { event.id }
        let ids = events.map { dispatch($0) }
        guard ids.count == 4, ids.allSatisfy({ !$0.isEmpty }) else {
            fail("Existential dispatch", "id extraction failed")
            return
        }
        pass("91. All 4 session events work as existential AgentEvent")
    }

    // MARK: Test 92: JSON format SSE-compatible (flat structure, snake_case)

    /// AC1-AC4 [P0]: Verify JSON output matches expected SSE format (flat, snake_case keys).
    static func testSessionEvents_jsonFormatSseCompatible() async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // SessionCreatedEvent
        do {
            let event = SessionCreatedEvent(sessionId: "s1", task: "sse test", model: "m")
            let data = try encoder.encode(event)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            guard json["id"] != nil else { fail("SSE format SessionCreated", "missing 'id'"); return }
            guard json["timestamp"] != nil else { fail("SSE format SessionCreated", "missing 'timestamp'"); return }
            guard json["session_id"] != nil else { fail("SSE format SessionCreated", "missing 'session_id'"); return }
            guard json["task"] != nil else { fail("SSE format SessionCreated", "missing 'task'"); return }
            guard json["model"] != nil else { fail("SSE format SessionCreated", "missing 'model'"); return }
            // Should NOT have nested "base" key
            guard json["base"] == nil else { fail("SSE format SessionCreated", "should not have nested 'base'"); return }
        } catch {
            fail("SSE format SessionCreated", "error: \(error)")
            return
        }

        // SessionClosedEvent
        do {
            let event = SessionClosedEvent(sessionId: "s2", finalStatus: .failed)
            let data = try encoder.encode(event)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            guard json["final_status"] != nil else { fail("SSE format SessionClosed", "missing 'final_status'"); return }
            guard json["base"] == nil else { fail("SSE format SessionClosed", "should not have nested 'base'"); return }
        } catch {
            fail("SSE format SessionClosed", "error: \(error)")
            return
        }

        // SessionRestoredEvent
        do {
            let event = SessionRestoredEvent(sessionId: "s3", messageCount: 7, originalCreatedAt: Date())
            let data = try encoder.encode(event)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            guard json["message_count"] != nil else { fail("SSE format SessionRestored", "missing 'message_count'"); return }
            guard json["original_created_at"] != nil else { fail("SSE format SessionRestored", "missing 'original_created_at'"); return }
            guard json["base"] == nil else { fail("SSE format SessionRestored", "should not have nested 'base'"); return }
        } catch {
            fail("SSE format SessionRestored", "error: \(error)")
            return
        }

        // SessionAutoSavedEvent
        do {
            let event = SessionAutoSavedEvent(sessionId: "s4", messageCount: 3)
            let data = try encoder.encode(event)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            guard json["message_count"] != nil else { fail("SSE format SessionAutoSaved", "missing 'message_count'"); return }
            guard json["base"] == nil else { fail("SSE format SessionAutoSaved", "should not have nested 'base'"); return }
        } catch {
            fail("SSE format SessionAutoSaved", "error: \(error)")
            return
        }

        pass("92. JSON format SSE-compatible (flat, snake_case, no nested base)")
    }
}

// MARK: - E2E Test Helpers

private extension AgentEventTypesE2ETests {
    actor TestActor {
        func sendAutoSaved(_ event: SessionAutoSavedEvent) -> SessionAutoSavedEvent { event }
    }
    static let testActor = TestActor()
}
