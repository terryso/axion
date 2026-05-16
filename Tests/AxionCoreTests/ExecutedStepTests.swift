import Foundation
import Testing
@testable import AxionCore

@Suite("ExecutedStep")
struct ExecutedStepTests {

    private let fixedDate = Date(timeIntervalSince1970: 1700000000)

    @Test("round trip with all field types")
    func roundTripWithAllFieldTypes() throws {
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
        #expect(decoded.stepIndex == 0)
        #expect(decoded.tool == "click")
        #expect(decoded.parameters["x"] == .int(100))
        #expect(decoded.parameters["label"] == .string("submit"))
        #expect(decoded.parameters["verified"] == .bool(true))
        #expect(decoded.result == "Clicked at (100, 200)")
        #expect(decoded.success)
    }

    @Test("round trip failed step")
    func roundTripFailedStep() throws {
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
        #expect(!decoded.success)
        #expect(decoded.stepIndex == 3)
    }

    @Test("round trip empty parameters")
    func roundTripEmptyParameters() throws {
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
        #expect(decoded.parameters.isEmpty)
    }

    @Test("equality same steps")
    func equalitySameSteps() {
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
        #expect(step == step2)
    }

    @Test("equality different steps")
    func equalityDifferentSteps() {
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
        #expect(a != b)
    }

    @Test("json structure has expected keys")
    func jsonStructureHasExpectedKeys() throws {
        let step = ExecutedStep(
            stepIndex: 0, tool: "click",
            parameters: ["x": .int(1)],
            result: "ok", success: true,
            timestamp: fixedDate
        )
        let data = try JSONEncoder().encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["stepIndex"] != nil)
        #expect(json["tool"] != nil)
        #expect(json["parameters"] != nil)
        #expect(json["result"] != nil)
        #expect(json["success"] != nil)
        #expect(json["timestamp"] != nil)
    }
}
