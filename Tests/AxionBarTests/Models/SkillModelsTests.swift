import Testing
import Foundation
@testable import AxionBar

@Suite("BarSkillSummary")
struct BarSkillSummaryTests {

    @Test("decodes from snake_case JSON")
    func decodesFromJSON() throws {
        let json = """
        {
            "name": "open_calculator",
            "description": "打开计算器",
            "parameter_count": 1,
            "step_count": 3,
            "last_used_at": "2026-05-15T10:00:00.000Z",
            "execution_count": 5
        }
        """
        let data = Data(json.utf8)
        let summary = try JSONDecoder().decode(BarSkillSummary.self, from: data)
        #expect(summary.name == "open_calculator")
        #expect(summary.description == "打开计算器")
        #expect(summary.parameterCount == 1)
        #expect(summary.stepCount == 3)
        #expect(summary.lastUsedAt == "2026-05-15T10:00:00.000Z")
        #expect(summary.executionCount == 5)
    }

    @Test("round-trip preserves all fields")
    func roundTrip() throws {
        let original = BarSkillSummary(
            name: "test_skill",
            description: "Test",
            parameterCount: 2,
            stepCount: 4,
            lastUsedAt: nil,
            executionCount: 0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BarSkillSummary.self, from: data)
        #expect(decoded == original)
    }

    @Test("decodes with nil optional fields")
    func decodesNilOptionals() throws {
        let json = """
        {
            "name": "skill",
            "description": "desc",
            "parameter_count": 0,
            "step_count": 1,
            "last_used_at": null,
            "execution_count": 0
        }
        """
        let data = Data(json.utf8)
        let summary = try JSONDecoder().decode(BarSkillSummary.self, from: data)
        #expect(summary.lastUsedAt == nil)
    }

    @Test("is Hashable")
    func hashable() {
        let a = BarSkillSummary(name: "x", description: "", parameterCount: 0, stepCount: 0, lastUsedAt: nil, executionCount: 0)
        let b = BarSkillSummary(name: "x", description: "", parameterCount: 0, stepCount: 0, lastUsedAt: nil, executionCount: 0)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}

@Suite("BarSkillDetail")
struct BarSkillDetailTests {

    @Test("decodes full detail with parameters")
    func decodesFullDetail() throws {
        let json = """
        {
            "name": "open_calculator",
            "description": "打开计算器",
            "version": 1,
            "parameters": [
                {"name": "url", "default_value": null, "description": "URL parameter"}
            ],
            "step_count": 3,
            "last_used_at": null,
            "execution_count": 0
        }
        """
        let data = Data(json.utf8)
        let detail = try JSONDecoder().decode(BarSkillDetail.self, from: data)
        #expect(detail.name == "open_calculator")
        #expect(detail.parameters.count == 1)
        #expect(detail.parameters[0].name == "url")
        #expect(detail.parameters[0].defaultValue == nil)
    }

    @Test("round-trip preserves all fields")
    func roundTrip() throws {
        let original = BarSkillDetail(
            name: "test",
            description: "desc",
            version: 2,
            parameters: [BarSkillParameter(name: "p", defaultValue: "v", description: "d")],
            stepCount: 5,
            lastUsedAt: "2026-01-01T00:00:00Z",
            executionCount: 10
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BarSkillDetail.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("BarSkillRunRequest")
struct BarSkillRunRequestTests {

    @Test("encodes params")
    func encodesParams() throws {
        let req = BarSkillRunRequest(params: ["key": "value"])
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((json?["params"] as? [String: String])?["key"] == "value")
    }

    @Test("encodes nil params")
    func encodesNilParams() throws {
        let req = BarSkillRunRequest(params: nil)
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["params"] == nil)
    }
}

@Suite("BarSkillRunResponse")
struct BarSkillRunResponseTests {

    @Test("decodes run_id and status")
    func decodesResponse() throws {
        let json = #"{"run_id":"20260515-abc","status":"running"}"#
        let data = Data(json.utf8)
        let resp = try JSONDecoder().decode(BarSkillRunResponse.self, from: data)
        #expect(resp.runId == "20260515-abc")
        #expect(resp.status == "running")
    }

    @Test("round-trip")
    func roundTrip() throws {
        let original = BarSkillRunResponse(runId: "id", status: "done")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BarSkillRunResponse.self, from: data)
        #expect(decoded == original)
    }
}
