import Foundation
import Testing
@testable import AxionCore

@Suite("RunState")
struct RunStateTests {

    // MARK: - All Cases Exist

    @Test("runState contains all nine cases")
    func runStateContainsAllNineCases() {
        let allCases = RunState.allCases
        #expect(allCases.count == 9)
    }

    @Test("runState all expected cases exist")
    func runStateAllExpectedCasesExist() {
        let expected: Set<RunState> = [
            .planning, .executing, .verifying, .replanning,
            .done, .blocked, .needsClarification, .cancelled, .failed,
        ]
        let actual = Set(RunState.allCases)
        #expect(actual == expected)
    }

    // MARK: - Raw Values

    @Test("runState raw values match camelCase")
    func runStateRawValuesMatchCamelCase() {
        #expect(RunState.planning.rawValue == "planning")
        #expect(RunState.executing.rawValue == "executing")
        #expect(RunState.verifying.rawValue == "verifying")
        #expect(RunState.replanning.rawValue == "replanning")
        #expect(RunState.done.rawValue == "done")
        #expect(RunState.blocked.rawValue == "blocked")
        #expect(RunState.needsClarification.rawValue == "needsClarification")
        #expect(RunState.cancelled.rawValue == "cancelled")
        #expect(RunState.failed.rawValue == "failed")
    }

    // MARK: - Codable Round-Trip

    @Test("runState codable round trip")
    func runStateCodableRoundTrip() throws {
        for state in RunState.allCases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(RunState.self, from: data)
            #expect(decoded == state)
        }
    }

    @Test("runState json encoding produces string value")
    func runStateJsonEncodingProducesStringValue() throws {
        let state = RunState.needsClarification
        let data = try JSONEncoder().encode(state)
        let jsonString = String(data: data, encoding: .utf8)!
        #expect(jsonString == "\"needsClarification\"")
    }
}
