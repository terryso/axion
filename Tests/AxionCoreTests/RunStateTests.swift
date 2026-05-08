import XCTest
@testable import AxionCore

final class RunStateTests: XCTestCase {

    // MARK: - All Cases Exist

    func test_runState_containsAllNineCases() {
        let allCases = RunState.allCases
        XCTAssertEqual(allCases.count, 9)
    }

    func test_runState_allExpectedCasesExist() {
        let expected: Set<RunState> = [
            .planning, .executing, .verifying, .replanning,
            .done, .blocked, .needsClarification, .cancelled, .failed,
        ]
        let actual = Set(RunState.allCases)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - Raw Values

    func test_runState_rawValues_matchCamelCase() {
        XCTAssertEqual(RunState.planning.rawValue, "planning")
        XCTAssertEqual(RunState.executing.rawValue, "executing")
        XCTAssertEqual(RunState.verifying.rawValue, "verifying")
        XCTAssertEqual(RunState.replanning.rawValue, "replanning")
        XCTAssertEqual(RunState.done.rawValue, "done")
        XCTAssertEqual(RunState.blocked.rawValue, "blocked")
        XCTAssertEqual(RunState.needsClarification.rawValue, "needsClarification")
        XCTAssertEqual(RunState.cancelled.rawValue, "cancelled")
        XCTAssertEqual(RunState.failed.rawValue, "failed")
    }

    // MARK: - Codable Round-Trip

    func test_runState_codable_roundTrip() throws {
        for state in RunState.allCases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(RunState.self, from: data)
            XCTAssertEqual(decoded, state)
        }
    }

    func test_runState_jsonEncoding_producesStringValue() throws {
        let state = RunState.needsClarification
        let data = try JSONEncoder().encode(state)
        let jsonString = String(data: data, encoding: .utf8)!
        XCTAssertEqual(jsonString, "\"needsClarification\"")
    }
}
