import Foundation
import Testing
@testable import AxionCore

@Suite("Plan")
struct PlanTests {

    // MARK: - Plan Codable Round-Trip

    @Test("plan codable round trip preserves all fields")
    func planCodableRoundTripPreservesAllFields() throws {
        let plan = Plan(
            id: UUID(),
            task: "Open Safari and navigate to example.com",
            steps: [
                Step(index: 0, tool: "launch_app", parameters: ["name": .string("Safari")], purpose: "Launch Safari", expectedChange: "Safari is open"),
                Step(index: 1, tool: "type_text", parameters: ["text": .string("example.com"), "placeholder": .placeholder("$url_field")], purpose: "Type URL", expectedChange: "URL entered"),
            ],
            stopWhen: [StopCondition(type: .textAppears, value: "Example Domain")],
            maxRetries: 3
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(plan)
        let decoded = try JSONDecoder().decode(Plan.self, from: data)

        #expect(decoded.id == plan.id)
        #expect(decoded.task == plan.task)
        #expect(decoded.steps.count == plan.steps.count)
        #expect(decoded.steps[0].tool == "launch_app")
        #expect(decoded.steps[1].parameters["placeholder"] == .placeholder("$url_field"))
        #expect(decoded.stopWhen.count == 1)
        #expect(decoded.stopWhen[0].type == .textAppears)
        #expect(decoded.maxRetries == 3)
    }

    // MARK: - Value Codable Round-Trip

    @Test("value string round trip")
    func valueStringRoundTrip() throws {
        let value = Value.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("value int round trip")
    func valueIntRoundTrip() throws {
        let value = Value.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("value bool round trip")
    func valueBoolRoundTrip() throws {
        let value = Value.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("value placeholder round trip")
    func valuePlaceholderRoundTrip() throws {
        let value = Value.placeholder("$pid")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("value placeholder preserves dollar sign")
    func valuePlaceholderPreservesDollarSign() throws {
        let value = Value.placeholder("$window_id")
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "placeholder")
        #expect(json["value"] as? String == "$window_id")

        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    // MARK: - Step Codable

    @Test("step codable round trip")
    func stepCodableRoundTrip() throws {
        let step = Step(
            index: 2,
            tool: "click",
            parameters: ["x": .int(100), "y": .int(200), "usePlaceholder": .bool(true), "ref": .placeholder("$button")],
            purpose: "Click the submit button",
            expectedChange: "Form submitted"
        )

        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(Step.self, from: data)

        #expect(decoded.index == 2)
        #expect(decoded.tool == "click")
        #expect(decoded.parameters["x"] == .int(100))
        #expect(decoded.parameters["usePlaceholder"] == .bool(true))
        #expect(decoded.parameters["ref"] == .placeholder("$button"))
        #expect(decoded.purpose == "Click the submit button")
    }
}
