import Foundation
import Testing
@testable import AxionCore

@Suite("StopCondition")
struct StopConditionTests {

    // MARK: - StopType Cases

    @Test("stopType all cases")
    func stopTypeAllCases() {
        let expected: [StopType] = [
            .windowAppears, .windowDisappears, .fileExists,
            .textAppears, .processExits, .maxStepsReached, .custom,
        ]
        #expect(expected.count == 7)
    }

    @Test("stopType raw values")
    func stopTypeRawValues() {
        #expect(StopType.windowAppears.rawValue == "windowAppears")
        #expect(StopType.windowDisappears.rawValue == "windowDisappears")
        #expect(StopType.fileExists.rawValue == "fileExists")
        #expect(StopType.textAppears.rawValue == "textAppears")
        #expect(StopType.processExits.rawValue == "processExits")
        #expect(StopType.maxStepsReached.rawValue == "maxStepsReached")
        #expect(StopType.custom.rawValue == "custom")
    }

    @Test("stopType init from raw value")
    func stopTypeInitFromRawValue() {
        #expect(StopType(rawValue: "windowAppears") == .windowAppears)
        #expect(StopType(rawValue: "custom") == .custom)
        #expect(StopType(rawValue: "nonexistent") == nil)
    }

    // MARK: - StopCondition Codable

    @Test("stopCondition round trip with value")
    func stopConditionRoundTripWithValue() throws {
        let condition = StopCondition(type: .textAppears, value: "Example Domain")
        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(StopCondition.self, from: data)
        #expect(decoded == condition)
    }

    @Test("stopCondition round trip nil value")
    func stopConditionRoundTripNilValue() throws {
        let condition = StopCondition(type: .maxStepsReached, value: nil)
        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(StopCondition.self, from: data)
        #expect(decoded.type == .maxStepsReached)
        #expect(decoded.value == nil)
    }

    @Test("stopCondition round trip empty value")
    func stopConditionRoundTripEmptyValue() throws {
        let condition = StopCondition(type: .custom, value: "")
        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(StopCondition.self, from: data)
        #expect(decoded.value == "")
    }

    @Test("stopCondition json structure")
    func stopConditionJsonStructure() throws {
        let condition = StopCondition(type: .fileExists, value: "/tmp/test.txt")
        let data = try JSONEncoder().encode(condition)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "fileExists")
        #expect(json["value"] as? String == "/tmp/test.txt")
    }

    // MARK: - Equality

    @Test("stopCondition equality")
    func stopConditionEquality() {
        let a = StopCondition(type: .textAppears, value: "hello")
        let b = StopCondition(type: .textAppears, value: "hello")
        let c = StopCondition(type: .textAppears, value: "world")
        let d = StopCondition(type: .windowAppears, value: "hello")

        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    @Test("stopCondition all types round trip")
    func stopConditionAllTypesRoundTrip() throws {
        let types: [StopType] = [
            .windowAppears, .windowDisappears, .fileExists,
            .textAppears, .processExits, .maxStepsReached, .custom,
        ]
        for type in types {
            let condition = StopCondition(type: type, value: "test_\(type.rawValue)")
            let data = try JSONEncoder().encode(condition)
            let decoded = try JSONDecoder().decode(StopCondition.self, from: data)
            #expect(decoded == condition, "Round-trip failed for \(type.rawValue)")
        }
    }
}
