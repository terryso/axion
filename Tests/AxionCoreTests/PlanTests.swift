import XCTest
@testable import AxionCore

final class PlanTests: XCTestCase {

    // MARK: - Plan Codable Round-Trip

    func test_plan_codable_roundTrip_preservesAllFields() throws {
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

        XCTAssertEqual(decoded.id, plan.id)
        XCTAssertEqual(decoded.task, plan.task)
        XCTAssertEqual(decoded.steps.count, plan.steps.count)
        XCTAssertEqual(decoded.steps[0].tool, "launch_app")
        XCTAssertEqual(decoded.steps[1].parameters["placeholder"], .placeholder("$url_field"))
        XCTAssertEqual(decoded.stopWhen.count, 1)
        XCTAssertEqual(decoded.stopWhen[0].type, .textAppears)
        XCTAssertEqual(decoded.maxRetries, 3)
    }

    // MARK: - Value Codable Round-Trip

    func test_value_string_roundTrip() throws {
        let value = Value.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_value_int_roundTrip() throws {
        let value = Value.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_value_bool_roundTrip() throws {
        let value = Value.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_value_placeholder_roundTrip() throws {
        let value = Value.placeholder("$pid")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_value_placeholder_preservesDollarSign() throws {
        let value = Value.placeholder("$window_id")
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)

        // Verify JSON contains the placeholder type discriminator
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "placeholder")
        XCTAssertEqual(json["value"] as? String, "$window_id")

        // Verify round-trip
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    // MARK: - Step Codable

    func test_step_codable_roundTrip() throws {
        let step = Step(
            index: 2,
            tool: "click",
            parameters: ["x": .int(100), "y": .int(200), "usePlaceholder": .bool(true), "ref": .placeholder("$button")],
            purpose: "Click the submit button",
            expectedChange: "Form submitted"
        )

        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(Step.self, from: data)

        XCTAssertEqual(decoded.index, 2)
        XCTAssertEqual(decoded.tool, "click")
        XCTAssertEqual(decoded.parameters["x"], .int(100))
        XCTAssertEqual(decoded.parameters["usePlaceholder"], .bool(true))
        XCTAssertEqual(decoded.parameters["ref"], .placeholder("$button"))
        XCTAssertEqual(decoded.purpose, "Click the submit button")
    }
}
