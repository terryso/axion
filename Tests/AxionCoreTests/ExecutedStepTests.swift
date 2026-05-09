import Foundation
import XCTest
@testable import AxionCore

final class ExecutedStepTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1700000000)

    func test_roundTrip_withAllFieldTypes() throws {
        let step = ExecutedStep(
            stepIndex: 0,
            tool: "click",
            parameters: [
                "x": .int(100),
                "y": .int(200),
                "label": .string("submit"),
                "verified": .bool(true),
                "ref": .placeholder("$window"),
            ],
            result: "Clicked at (100, 200)",
            success: true,
            timestamp: fixedDate
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(ExecutedStep.self, from: data)
        XCTAssertEqual(decoded.stepIndex, 0)
        XCTAssertEqual(decoded.tool, "click")
        XCTAssertEqual(decoded.parameters["x"], .int(100))
        XCTAssertEqual(decoded.parameters["label"], .string("submit"))
        XCTAssertEqual(decoded.parameters["verified"], .bool(true))
        XCTAssertEqual(decoded.result, "Clicked at (100, 200)")
        XCTAssertTrue(decoded.success)
    }

    func test_roundTrip_failedStep() throws {
        let step = ExecutedStep(
            stepIndex: 3,
            tool: "launch_app",
            parameters: ["name": .string("NoApp")],
            result: "App not found",
            success: false,
            timestamp: fixedDate
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(ExecutedStep.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.stepIndex, 3)
    }

    func test_roundTrip_emptyParameters() throws {
        let step = ExecutedStep(
            stepIndex: 0,
            tool: "list_apps",
            parameters: [:],
            result: "[]",
            success: true,
            timestamp: fixedDate
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(ExecutedStep.self, from: data)
        XCTAssertTrue(decoded.parameters.isEmpty)
    }

    func test_equality_sameSteps() {
        let step = ExecutedStep(
            stepIndex: 1, tool: "click",
            parameters: ["x": .int(10)],
            result: "ok", success: true,
            timestamp: fixedDate
        )
        let step2 = ExecutedStep(
            stepIndex: 1, tool: "click",
            parameters: ["x": .int(10)],
            result: "ok", success: true,
            timestamp: fixedDate
        )
        XCTAssertEqual(step, step2)
    }

    func test_equality_differentSteps() {
        let a = ExecutedStep(
            stepIndex: 0, tool: "click",
            parameters: [:], result: "a", success: true,
            timestamp: fixedDate
        )
        let b = ExecutedStep(
            stepIndex: 1, tool: "click",
            parameters: [:], result: "b", success: true,
            timestamp: fixedDate
        )
        XCTAssertNotEqual(a, b)
    }

    func test_jsonStructure_hasExpectedKeys() throws {
        let step = ExecutedStep(
            stepIndex: 0, tool: "click",
            parameters: ["x": .int(1)],
            result: "ok", success: true,
            timestamp: fixedDate
        )
        let data = try JSONEncoder().encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["stepIndex"])
        XCTAssertNotNil(json["tool"])
        XCTAssertNotNil(json["parameters"])
        XCTAssertNotNil(json["result"])
        XCTAssertNotNil(json["success"])
        XCTAssertNotNil(json["timestamp"])
    }
}
