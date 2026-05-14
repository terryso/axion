import Testing
import Foundation
@testable import AxionBar

@Suite("BarCreateRunRequest")
struct BarCreateRunRequestTests {

    @Test("encodes task field correctly")
    func encodesTask() throws {
        let request = BarCreateRunRequest(task: "打开计算器")
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["task"] as? String == "打开计算器")
    }

    @Test("decodes from JSON")
    func decodesFromJSON() throws {
        let json = #"{"task":"打开浏览器"}"#
        let data = Data(json.utf8)
        let request = try JSONDecoder().decode(BarCreateRunRequest.self, from: data)
        #expect(request.task == "打开浏览器")
    }

    @Test("round-trip preserves task")
    func roundTrip() throws {
        let original = BarCreateRunRequest(task: "测试任务描述")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BarCreateRunRequest.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("BarCreateRunResponse")
struct BarCreateRunResponseTests {

    @Test("decodes run_id and status from snake_case JSON")
    func decodesSnakeCase() throws {
        let json = #"{"run_id":"20260515-abc123","status":"running"}"#
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(BarCreateRunResponse.self, from: data)
        #expect(response.runId == "20260515-abc123")
        #expect(response.status == "running")
    }

    @Test("round-trip preserves all fields")
    func roundTrip() throws {
        let original = BarCreateRunResponse(runId: "test-id", status: "done")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BarCreateRunResponse.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("BarRunStatusResponse")
struct BarRunStatusResponseTests {

    @Test("decodes full response with snake_case")
    func decodesFullResponse() throws {
        let json = """
        {
            "run_id": "20260515-xyz789",
            "status": "done",
            "task": "打开计算器",
            "total_steps": 3,
            "duration_ms": 5200,
            "replan_count": 0,
            "submitted_at": "2026-05-15T10:00:00.000Z",
            "completed_at": "2026-05-15T10:00:05.200Z",
            "steps": [
                {"index": 0, "tool": "launch_app", "purpose": "启动 Calculator", "success": true}
            ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(BarRunStatusResponse.self, from: data)
        #expect(response.runId == "20260515-xyz789")
        #expect(response.status == "done")
        #expect(response.task == "打开计算器")
        #expect(response.totalSteps == 3)
        #expect(response.durationMs == 5200)
        #expect(response.replanCount == 0)
        #expect(response.steps.count == 1)
        #expect(response.steps[0].tool == "launch_app")
    }

    @Test("decodes with nil optional fields")
    func decodesWithNilOptionals() throws {
        let json = """
        {
            "run_id": "test-id",
            "status": "running",
            "task": "测试",
            "total_steps": 0,
            "duration_ms": null,
            "replan_count": 0,
            "submitted_at": "2026-05-15T10:00:00.000Z",
            "completed_at": null,
            "steps": []
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(BarRunStatusResponse.self, from: data)
        #expect(response.durationMs == nil)
        #expect(response.completedAt == nil)
    }
}

@Suite("BarStepSummary")
struct BarStepSummaryTests {

    @Test("decodes from JSON")
    func decodesFromJSON() throws {
        let json = #"{"index":0,"tool":"launch_app","purpose":"启动应用","success":true}"#
        let data = Data(json.utf8)
        let step = try JSONDecoder().decode(BarStepSummary.self, from: data)
        #expect(step.index == 0)
        #expect(step.tool == "launch_app")
        #expect(step.purpose == "启动应用")
        #expect(step.success == true)
    }

    @Test("round-trip preserves all fields")
    func roundTrip() throws {
        let original = BarStepSummary(index: 2, tool: "click", purpose: "点击按钮", success: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BarStepSummary.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("BarStepStartedData")
struct BarStepStartedDataTests {

    @Test("decodes snake_case fields")
    func decodesSnakeCase() throws {
        let json = #"{"step_index":1,"tool":"type_text"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(BarStepStartedData.self, from: data)
        #expect(decoded.stepIndex == 1)
        #expect(decoded.tool == "type_text")
    }

    @Test("round-trip")
    func roundTrip() throws {
        let original = BarStepStartedData(stepIndex: 5, tool: "screenshot")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BarStepStartedData.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("BarStepCompletedData")
struct BarStepCompletedDataTests {

    @Test("decodes with duration_ms")
    func decodesWithDuration() throws {
        let json = #"{"step_index":0,"tool":"launch_app","purpose":"启动 Calculator","success":true,"duration_ms":320}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(BarStepCompletedData.self, from: data)
        #expect(decoded.stepIndex == 0)
        #expect(decoded.success == true)
        #expect(decoded.durationMs == 320)
    }

    @Test("decodes without duration_ms")
    func decodesWithoutDuration() throws {
        let json = #"{"step_index":0,"tool":"launch_app","purpose":"启动","success":false}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(BarStepCompletedData.self, from: data)
        #expect(decoded.durationMs == nil)
    }
}

@Suite("BarRunCompletedData")
struct BarRunCompletedDataTests {

    @Test("decodes full event")
    func decodesFullEvent() throws {
        let json = #"{"run_id":"20260515-abc","final_status":"done","total_steps":3,"duration_ms":8200,"replan_count":0}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(BarRunCompletedData.self, from: data)
        #expect(decoded.runId == "20260515-abc")
        #expect(decoded.finalStatus == "done")
        #expect(decoded.totalSteps == 3)
        #expect(decoded.durationMs == 8200)
        #expect(decoded.replanCount == 0)
    }

    @Test("round-trip")
    func roundTrip() throws {
        let original = BarRunCompletedData(runId: "id", finalStatus: "failed", totalSteps: 5, durationMs: nil, replanCount: 2)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BarRunCompletedData.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("BarSSEEvent")
struct BarSSEEventTests {

    @Test("eventType returns correct strings")
    func eventTypes() {
        let started = BarSSEEvent.stepStarted(BarStepStartedData(stepIndex: 0, tool: "click"))
        #expect(started.eventType == "step_started")

        let completed = BarSSEEvent.stepCompleted(BarStepCompletedData(stepIndex: 0, tool: "click", purpose: "test", success: true, durationMs: nil))
        #expect(completed.eventType == "step_completed")

        let runCompleted = BarSSEEvent.runCompleted(BarRunCompletedData(runId: "id", finalStatus: "done", totalSteps: 1, durationMs: nil, replanCount: 0))
        #expect(runCompleted.eventType == "run_completed")
    }

    @Test("equality works for same values")
    func equality() {
        let a = BarSSEEvent.stepStarted(BarStepStartedData(stepIndex: 0, tool: "click"))
        let b = BarSSEEvent.stepStarted(BarStepStartedData(stepIndex: 0, tool: "click"))
        #expect(a == b)
    }

    @Test("inequality for different values")
    func inequality() {
        let a = BarSSEEvent.stepStarted(BarStepStartedData(stepIndex: 0, tool: "click"))
        let b = BarSSEEvent.stepStarted(BarStepStartedData(stepIndex: 1, tool: "click"))
        #expect(a != b)
    }
}
