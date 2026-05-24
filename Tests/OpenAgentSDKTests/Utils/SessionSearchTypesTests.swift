import XCTest
@testable import OpenAgentSDK

final class SessionSearchTypesTests: XCTestCase {

    // MARK: - SessionSearchMode

    func testSessionSearchModeAllCases() {
        XCTAssertEqual(SessionSearchMode.allCases.count, 3)
        XCTAssertTrue(SessionSearchMode.allCases.contains(.discover))
        XCTAssertTrue(SessionSearchMode.allCases.contains(.scroll))
        XCTAssertTrue(SessionSearchMode.allCases.contains(.browse))
    }

    func testSessionSearchModeRawValues() {
        XCTAssertEqual(SessionSearchMode.discover.rawValue, "discover")
        XCTAssertEqual(SessionSearchMode.scroll.rawValue, "scroll")
        XCTAssertEqual(SessionSearchMode.browse.rawValue, "browse")
    }

    func testSessionSearchModeRawValueRoundTrip() {
        for mode in SessionSearchMode.allCases {
            XCTAssertEqual(SessionSearchMode(rawValue: mode.rawValue), mode)
        }
    }

    func testSessionSearchModeCodable() throws {
        for mode in SessionSearchMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(SessionSearchMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - SessionSearchQuery

    func testDiscoverQueryValid() throws {
        let query = SessionSearchQuery(mode: .discover, query: "test search")
        XCTAssertNoThrow(try query.validate())
    }

    func testDiscoverQueryWithoutQueryThrows() {
        let query = SessionSearchQuery(mode: .discover, query: nil)
        XCTAssertThrowsError(try query.validate()) { error in
            guard let sdkError = error as? SDKError else { return XCTFail("Expected SDKError") }
            if case .invalidConfiguration(let msg) = sdkError {
                XCTAssertTrue(msg.contains("discover"))
            } else {
                XCTFail("Expected invalidConfiguration")
            }
        }
    }

    func testScrollQueryValid() throws {
        let query = SessionSearchQuery(mode: .scroll, sessionId: "sess-123")
        XCTAssertNoThrow(try query.validate())
    }

    func testScrollQueryWithoutSessionIdThrows() {
        let query = SessionSearchQuery(mode: .scroll, sessionId: nil)
        XCTAssertThrowsError(try query.validate()) { error in
            guard let sdkError = error as? SDKError else { return XCTFail("Expected SDKError") }
            if case .invalidConfiguration(let msg) = sdkError {
                XCTAssertTrue(msg.contains("scroll"))
            } else {
                XCTFail("Expected invalidConfiguration")
            }
        }
    }

    func testBrowseQueryValid() throws {
        let query = SessionSearchQuery(mode: .browse)
        XCTAssertNoThrow(try query.validate())
    }

    func testBrowseQueryWithQueryThrows() {
        let query = SessionSearchQuery(mode: .browse, query: "should fail")
        XCTAssertThrowsError(try query.validate()) { error in
            guard let sdkError = error as? SDKError else { return XCTFail("Expected SDKError") }
            if case .invalidConfiguration = sdkError {
                // expected
            } else {
                XCTFail("Expected invalidConfiguration")
            }
        }
    }

    func testBrowseQueryWithSessionIdThrows() {
        let query = SessionSearchQuery(mode: .browse, sessionId: "should-fail")
        XCTAssertThrowsError(try query.validate()) { error in
            guard let sdkError = error as? SDKError else { return XCTFail("Expected SDKError") }
            if case .invalidConfiguration = sdkError {
                // expected
            } else {
                XCTFail("Expected invalidConfiguration")
            }
        }
    }

    func testQueryDefaultLimit() {
        let query = SessionSearchQuery(mode: .browse)
        XCTAssertEqual(query.limit, 10)
    }

    func testQueryCustomLimit() {
        let query = SessionSearchQuery(mode: .browse, limit: 5)
        XCTAssertEqual(query.limit, 5)
    }

    func testQueryEquality() {
        let q1 = SessionSearchQuery(mode: .discover, query: "test", limit: 5)
        let q2 = SessionSearchQuery(mode: .discover, query: "test", limit: 5)
        XCTAssertEqual(q1, q2)
    }

    func testQueryInequality() {
        let q1 = SessionSearchQuery(mode: .discover, query: "test")
        let q2 = SessionSearchQuery(mode: .discover, query: "other")
        XCTAssertNotEqual(q1, q2)
    }

    // MARK: - SessionSearchResult

    func testResultConstruction() {
        let result = SessionSearchResult(
            mode: .discover,
            matchedSessionId: "sess-1",
            matchedMessageIndex: 3,
            messages: [],
            totalMatches: 1,
            hasMore: false
        )
        XCTAssertEqual(result.mode, .discover)
        XCTAssertEqual(result.matchedSessionId, "sess-1")
        XCTAssertEqual(result.matchedMessageIndex, 3)
        XCTAssertTrue(result.messages.isEmpty)
        XCTAssertEqual(result.totalMatches, 1)
        XCTAssertFalse(result.hasMore)
    }

    func testResultDefaultValues() {
        let result = SessionSearchResult(mode: .browse)
        XCTAssertNil(result.matchedSessionId)
        XCTAssertNil(result.matchedMessageIndex)
        XCTAssertTrue(result.messages.isEmpty)
        XCTAssertNil(result.totalMatches)
        XCTAssertFalse(result.hasMore)
    }

    func testResultEquality() {
        let msg = SessionMessage(role: .user, content: "hello")
        let r1 = SessionSearchResult(mode: .discover, matchedSessionId: "s1", messages: [msg], totalMatches: 1, hasMore: false)
        let r2 = SessionSearchResult(mode: .discover, matchedSessionId: "s1", messages: [msg], totalMatches: 1, hasMore: false)
        XCTAssertEqual(r1, r2)
    }

    func testResultInequality() {
        let r1 = SessionSearchResult(mode: .discover, matchedSessionId: "s1")
        let r2 = SessionSearchResult(mode: .discover, matchedSessionId: "s2")
        XCTAssertNotEqual(r1, r2)
    }
}
