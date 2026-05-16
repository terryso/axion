import Testing
import Foundation
@testable import AxionCLI

@Suite("APITypes")
struct APITypesTests {

    @Test("HealthResponse codable round trip preserves all fields")
    func healthResponseCodableRoundTripPreservesAllFields() throws {
        let response = HealthResponse(status: "ok", version: "0.1.0")

        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let decoded = try JSONDecoder().decode(HealthResponse.self, from: data)

        #expect(decoded.status == "ok")
        #expect(decoded.version == "0.1.0")
    }

    @Test("HealthResponse JSON keys are snake case")
    func healthResponseJsonKeysAreSnakeCase() throws {
        let response = HealthResponse(status: "ok", version: "0.1.0")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"status\""))
        #expect(json.contains("\"version\""))
    }

    @Test("CreateRunRequest codable round trip preserves all fields")
    func createRunRequestCodableRoundTripPreservesAllFields() throws {
        let request = CreateRunRequest(
            task: "open calculator",
            maxSteps: 20,
            maxBatches: 6,
            allowForeground: false
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateRunRequest.self, from: data)

        #expect(decoded.task == "open calculator")
        #expect(decoded.maxSteps == 20)
        #expect(decoded.maxBatches == 6)
        #expect(decoded.allowForeground == false)
    }

    @Test("CreateRunRequest optional fields default to nil")
    func createRunRequestOptionalFieldsDefaultToNil() throws {
        let request = CreateRunRequest(task: "open calculator")

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateRunRequest.self, from: data)

        #expect(decoded.task == "open calculator")
        #expect(decoded.maxSteps == nil)
        #expect(decoded.maxBatches == nil)
        #expect(decoded.allowForeground == nil)
    }

    @Test("CreateRunRequest JSON keys are snake case")
    func createRunRequestJsonKeysAreSnakeCase() throws {
        let request = CreateRunRequest(
            task: "open calculator",
            maxSteps: 20,
            maxBatches: 6,
            allowForeground: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"task\""))
        #expect(json.contains("\"max_steps\""))
        #expect(json.contains("\"max_batches\""))
        #expect(json.contains("\"allow_foreground\""))
    }

    @Test("CreateRunResponse codable round trip preserves all fields")
    func createRunResponseCodableRoundTripPreservesAllFields() throws {
        let response = CreateRunResponse(runId: "20260513-abc123", status: "running")

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(CreateRunResponse.self, from: data)

        #expect(decoded.runId == "20260513-abc123")
        #expect(decoded.status == "running")
    }

    @Test("CreateRunResponse JSON keys are snake case")
    func createRunResponseJsonKeysAreSnakeCase() throws {
        let response = CreateRunResponse(runId: "20260513-abc123", status: "running")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"run_id\""))
        #expect(json.contains("\"status\""))
    }

    @Test("RunStatusResponse codable round trip preserves all fields")
    func runStatusResponseCodableRoundTripPreservesAllFields() throws {
        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        let response = RunStatusResponse(
            runId: "20260513-abc123",
            status: "done",
            task: "open calculator",
            totalSteps: 3,
            durationMs: 8200,
            replanCount: 0,
            submittedAt: "2026-05-13T10:30:00+08:00",
            completedAt: "2026-05-13T10:30:08+08:00",
            steps: [step]
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(RunStatusResponse.self, from: data)

        #expect(decoded.runId == "20260513-abc123")
        #expect(decoded.status == "done")
        #expect(decoded.task == "open calculator")
        #expect(decoded.totalSteps == 3)
        #expect(decoded.durationMs == 8200)
        #expect(decoded.replanCount == 0)
        #expect(decoded.steps.count == 1)
        #expect(decoded.steps[0].tool == "launch_app")
    }

    @Test("RunStatusResponse JSON keys are snake case")
    func runStatusResponseJsonKeysAreSnakeCase() throws {
        let response = RunStatusResponse(
            runId: "20260513-abc123",
            status: "done",
            task: "open calculator",
            totalSteps: 3,
            durationMs: 8200,
            replanCount: 0,
            submittedAt: "2026-05-13T10:30:00+08:00",
            completedAt: "2026-05-13T10:30:08+08:00",
            steps: []
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"run_id\""))
        #expect(json.contains("\"total_steps\""))
        #expect(json.contains("\"duration_ms\""))
        #expect(json.contains("\"replan_count\""))
        #expect(json.contains("\"submitted_at\""))
        #expect(json.contains("\"completed_at\""))
    }

    @Test("StepSummary codable round trip preserves all fields")
    func stepSummaryCodableRoundTripPreservesAllFields() throws {
        let summary = StepSummary(index: 1, tool: "click", purpose: "Input expression", success: true)

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(StepSummary.self, from: data)

        #expect(decoded.index == 1)
        #expect(decoded.tool == "click")
        #expect(decoded.purpose == "Input expression")
        #expect(decoded.success == true)
    }

    @Test("APIErrorResponse codable round trip preserves all fields")
    func apiErrorResponseCodableRoundTripPreservesAllFields() throws {
        let error = APIErrorResponse(error: "missing_task", message: "Request body must include a 'task' field.")

        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(APIErrorResponse.self, from: data)

        #expect(decoded.error == "missing_task")
        #expect(decoded.message == "Request body must include a 'task' field.")
    }

    @Test("APIErrorResponse JSON keys are correct")
    func apiErrorResponseJsonKeysAreCorrect() throws {
        let error = APIErrorResponse(error: "run_not_found", message: "Run 'nonexistent-id' not found.")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(error)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"error\""))
        #expect(json.contains("\"message\""))
    }

    @Test("APIRunStatus raw values match expected strings")
    func apiRunStatusRawValuesMatchExpectedStrings() {
        #expect(APIRunStatus.running.rawValue == "running")
        #expect(APIRunStatus.done.rawValue == "done")
        #expect(APIRunStatus.failed.rawValue == "failed")
        #expect(APIRunStatus.cancelled.rawValue == "cancelled")
    }

    @Test("APIRunStatus decodes from valid strings")
    func apiRunStatusDecodesFromValidStrings() throws {
        let statuses: [(String, APIRunStatus)] = [
            ("\"running\"", .running),
            ("\"done\"", .done),
            ("\"failed\"", .failed),
            ("\"cancelled\"", .cancelled),
        ]

        for (jsonString, expected) in statuses {
            let data = jsonString.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(APIRunStatus.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test("APIRunStatus decoding invalid string throws error")
    func apiRunStatusDecodingInvalidStringThrowsError() {
        let data = "\"unknown_status\"".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(APIRunStatus.self, from: data)
        }
    }

    @Test("TrackedRun codable round trip preserves all fields")
    func trackedRunCodableRoundTripPreservesAllFields() throws {
        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch app", success: true)
        let run = TrackedRun(
            runId: "20260513-abc123",
            task: "open calculator",
            status: .running,
            submittedAt: "2026-05-13T10:30:00+08:00",
            completedAt: nil,
            totalSteps: 1,
            durationMs: nil,
            replanCount: 0,
            steps: [step]
        )

        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(TrackedRun.self, from: data)

        #expect(decoded.runId == "20260513-abc123")
        #expect(decoded.task == "open calculator")
        #expect(decoded.status == .running)
        #expect(decoded.totalSteps == 1)
        #expect(decoded.steps.count == 1)
    }

    @Test("RunOptions codable round trip preserves all fields")
    func runOptionsCodableRoundTripPreservesAllFields() throws {
        let options = RunOptions(
            task: "open calculator",
            maxSteps: 10,
            maxBatches: 3,
            allowForeground: true
        )

        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(RunOptions.self, from: data)

        #expect(decoded.task == "open calculator")
        #expect(decoded.maxSteps == 10)
        #expect(decoded.maxBatches == 3)
        #expect(decoded.allowForeground == true)
    }

    @Test("RunOptions optional fields default to nil")
    func runOptionsOptionalFieldsDefaultToNil() throws {
        let options = RunOptions(task: "open calculator")

        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(RunOptions.self, from: data)

        #expect(decoded.task == "open calculator")
        #expect(decoded.maxSteps == nil)
        #expect(decoded.maxBatches == nil)
        #expect(decoded.allowForeground == nil)
    }

    @Test("SkillSummaryResponse codable round trip")
    func skillSummaryResponseCodableRoundTrip() throws {
        let summary = SkillSummaryResponse(
            name: "open_calculator",
            description: "打开计算器",
            parameterCount: 1,
            stepCount: 3,
            lastUsedAt: "2026-05-15T10:00:00.000Z",
            executionCount: 5
        )
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(SkillSummaryResponse.self, from: data)
        #expect(decoded.name == "open_calculator")
        #expect(decoded.parameterCount == 1)
        #expect(decoded.stepCount == 3)
        #expect(decoded.executionCount == 5)
    }

    @Test("SkillSummaryResponse decodes snake case")
    func skillSummaryResponseDecodesSnakeCase() throws {
        let json = """
        {"name":"test","description":"desc","parameter_count":2,"step_count":4,"last_used_at":null,"execution_count":0}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SkillSummaryResponse.self, from: data)
        #expect(decoded.name == "test")
        #expect(decoded.parameterCount == 2)
        #expect(decoded.lastUsedAt == nil)
    }

    @Test("SkillDetailResponse codable round trip")
    func skillDetailResponseCodableRoundTrip() throws {
        let detail = SkillDetailResponse(
            name: "open_browser",
            description: "打开浏览器",
            version: 1,
            parameters: [SkillParameterResponse(name: "url", defaultValue: nil, description: "URL")],
            stepCount: 2,
            lastUsedAt: nil,
            executionCount: 0
        )
        let data = try JSONEncoder().encode(detail)
        let decoded = try JSONDecoder().decode(SkillDetailResponse.self, from: data)
        #expect(decoded.name == "open_browser")
        #expect(decoded.parameters.count == 1)
        #expect(decoded.parameters[0].name == "url")
    }

    @Test("SkillParameterResponse decodes snake case")
    func skillParameterResponseDecodesSnakeCase() throws {
        let json = #"{"name":"url","default_value":"https://example.com","description":"URL param"}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SkillParameterResponse.self, from: data)
        #expect(decoded.name == "url")
        #expect(decoded.defaultValue == "https://example.com")
    }

    @Test("SkillRunRequest encodes params")
    func skillRunRequestEncodesParams() throws {
        let req = SkillRunRequest(params: ["key": "value"])
        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"params\""))
        #expect(json.contains("\"key\""))
    }

    @Test("SkillRunRequest encodes nil params")
    func skillRunRequestEncodesNilParams() throws {
        let req = SkillRunRequest(params: nil)
        let data = try JSONEncoder().encode(req)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json == "{}")
    }

    @Test("SkillRunResponse codable round trip")
    func skillRunResponseCodableRoundTrip() throws {
        let resp = SkillRunResponse(runId: "20260515-abc", status: "running")
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(SkillRunResponse.self, from: data)
        #expect(decoded.runId == "20260515-abc")
        #expect(decoded.status == "running")
    }

    @Test("SkillRunResponse decodes snake case")
    func skillRunResponseDecodesSnakeCase() throws {
        let json = #"{"run_id":"20260515-xyz","status":"done"}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SkillRunResponse.self, from: data)
        #expect(decoded.runId == "20260515-xyz")
    }
}
