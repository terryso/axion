import XCTest
@testable import AxionCore

final class StopConditionTests: XCTestCase {

    // MARK: - StopType Cases

    func test_stopType_allCases() {
        let expected: [StopType] = [
            .windowAppears, .windowDisappears, .fileExists,
            .textAppears, .processExits, .maxStepsReached, .custom,
        ]
        XCTAssertEqual(expected.count, 7)
    }

    func test_stopType_rawValues() {
        XCTAssertEqual(StopType.windowAppears.rawValue, "windowAppears")
        XCTAssertEqual(StopType.windowDisappears.rawValue, "windowDisappears")
        XCTAssertEqual(StopType.fileExists.rawValue, "fileExists")
        XCTAssertEqual(StopType.textAppears.rawValue, "textAppears")
        XCTAssertEqual(StopType.processExits.rawValue, "processExits")
        XCTAssertEqual(StopType.maxStepsReached.rawValue, "maxStepsReached")
        XCTAssertEqual(StopType.custom.rawValue, "custom")
    }

    func test_stopType_initFromRawValue() {
        XCTAssertEqual(StopType(rawValue: "windowAppears"), .windowAppears)
        XCTAssertEqual(StopType(rawValue: "custom"), .custom)
        XCTAssertNil(StopType(rawValue: "nonexistent"))
    }

    // MARK: - StopCondition Codable

    func test_stopCondition_roundTrip_withValue() throws {
        let condition = StopCondition(type: .textAppears, value: "Example Domain")
        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(StopCondition.self, from: data)
        XCTAssertEqual(decoded, condition)
    }

    func test_stopCondition_roundTrip_nilValue() throws {
        let condition = StopCondition(type: .maxStepsReached, value: nil)
        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(StopCondition.self, from: data)
        XCTAssertEqual(decoded.type, .maxStepsReached)
        XCTAssertNil(decoded.value)
    }

    func test_stopCondition_roundTrip_emptyValue() throws {
        let condition = StopCondition(type: .custom, value: "")
        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(StopCondition.self, from: data)
        XCTAssertEqual(decoded.value, "")
    }

    func test_stopCondition_jsonStructure() throws {
        let condition = StopCondition(type: .fileExists, value: "/tmp/test.txt")
        let data = try JSONEncoder().encode(condition)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "fileExists")
        XCTAssertEqual(json["value"] as? String, "/tmp/test.txt")
    }

    // MARK: - Equality

    func test_stopCondition_equality() {
        let a = StopCondition(type: .textAppears, value: "hello")
        let b = StopCondition(type: .textAppears, value: "hello")
        let c = StopCondition(type: .textAppears, value: "world")
        let d = StopCondition(type: .windowAppears, value: "hello")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }

    func test_stopCondition_allTypes_roundTrip() throws {
        let types: [StopType] = [
            .windowAppears, .windowDisappears, .fileExists,
            .textAppears, .processExits, .maxStepsReached, .custom,
        ]
        for type in types {
            let condition = StopCondition(type: type, value: "test_\(type.rawValue)")
            let data = try JSONEncoder().encode(condition)
            let decoded = try JSONDecoder().decode(StopCondition.self, from: data)
            XCTAssertEqual(decoded, condition, "Round-trip failed for \(type.rawValue)")
        }
    }
}
