import XCTest
@testable import AxionCLI

// [P0] ATDD GREEN-PHASE — Story 5.1 AC2-AC6
// All tests now validate the implemented API types.

final class APITypesTests: XCTestCase {

    // MARK: - AC6: HealthResponse

    func test_healthResponse_codable_roundTrip_preservesAllFields() throws {
        let response = HealthResponse(status: "ok", version: "0.1.0")

        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let decoded = try JSONDecoder().decode(HealthResponse.self, from: data)

        XCTAssertEqual(decoded.status, "ok")
        XCTAssertEqual(decoded.version, "0.1.0")
    }

    func test_healthResponse_jsonKeys_areSnakeCase() throws {
        let response = HealthResponse(status: "ok", version: "0.1.0")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"status\""), "HealthResponse JSON should contain 'status' key")
        XCTAssertTrue(json.contains("\"version\""), "HealthResponse JSON should contain 'version' key")
    }

    // MARK: - AC2: CreateRunRequest

    func test_createRunRequest_codable_roundTrip_preservesAllFields() throws {
        let request = CreateRunRequest(
            task: "open calculator",
            maxSteps: 20,
            maxBatches: 6,
            allowForeground: false
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateRunRequest.self, from: data)

        XCTAssertEqual(decoded.task, "open calculator")
        XCTAssertEqual(decoded.maxSteps, 20)
        XCTAssertEqual(decoded.maxBatches, 6)
        XCTAssertFalse(decoded.allowForeground!)
    }

    func test_createRunRequest_optionalFields_defaultToNil() throws {
        let request = CreateRunRequest(task: "open calculator")

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateRunRequest.self, from: data)

        XCTAssertEqual(decoded.task, "open calculator")
        XCTAssertNil(decoded.maxSteps)
        XCTAssertNil(decoded.maxBatches)
        XCTAssertNil(decoded.allowForeground)
    }

    func test_createRunRequest_jsonKeys_areSnakeCase() throws {
        let request = CreateRunRequest(
            task: "open calculator",
            maxSteps: 20,
            maxBatches: 6,
            allowForeground: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"task\""), "CreateRunRequest JSON should contain 'task' key")
        XCTAssertTrue(json.contains("\"max_steps\""), "CreateRunRequest JSON should contain 'max_steps' key")
        XCTAssertTrue(json.contains("\"max_batches\""), "CreateRunRequest JSON should contain 'max_batches' key")
        XCTAssertTrue(json.contains("\"allow_foreground\""), "CreateRunRequest JSON should contain 'allow_foreground' key")
    }

    // MARK: - AC2: CreateRunResponse

    func test_createRunResponse_codable_roundTrip_preservesAllFields() throws {
        let response = CreateRunResponse(runId: "20260513-abc123", status: "running")

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(CreateRunResponse.self, from: data)

        XCTAssertEqual(decoded.runId, "20260513-abc123")
        XCTAssertEqual(decoded.status, "running")
    }

    func test_createRunResponse_jsonKeys_areSnakeCase() throws {
        let response = CreateRunResponse(runId: "20260513-abc123", status: "running")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"run_id\""), "CreateRunResponse JSON should contain 'run_id' key")
        XCTAssertTrue(json.contains("\"status\""), "CreateRunResponse JSON should contain 'status' key")
    }

    // MARK: - AC3/AC4: RunStatusResponse

    func test_runStatusResponse_codable_roundTrip_preservesAllFields() throws {
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

        XCTAssertEqual(decoded.runId, "20260513-abc123")
        XCTAssertEqual(decoded.status, "done")
        XCTAssertEqual(decoded.task, "open calculator")
        XCTAssertEqual(decoded.totalSteps, 3)
        XCTAssertEqual(decoded.durationMs, 8200)
        XCTAssertEqual(decoded.replanCount, 0)
        XCTAssertEqual(decoded.steps.count, 1)
        XCTAssertEqual(decoded.steps[0].tool, "launch_app")
    }

    func test_runStatusResponse_jsonKeys_areSnakeCase() throws {
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
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"run_id\""), "RunStatusResponse JSON should contain 'run_id' key")
        XCTAssertTrue(json.contains("\"total_steps\""), "RunStatusResponse JSON should contain 'total_steps' key")
        XCTAssertTrue(json.contains("\"duration_ms\""), "RunStatusResponse JSON should contain 'duration_ms' key")
        XCTAssertTrue(json.contains("\"replan_count\""), "RunStatusResponse JSON should contain 'replan_count' key")
        XCTAssertTrue(json.contains("\"submitted_at\""), "RunStatusResponse JSON should contain 'submitted_at' key")
        XCTAssertTrue(json.contains("\"completed_at\""), "RunStatusResponse JSON should contain 'completed_at' key")
    }

    // MARK: - StepSummary

    func test_stepSummary_codable_roundTrip_preservesAllFields() throws {
        let summary = StepSummary(index: 1, tool: "click", purpose: "Input expression", success: true)

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(StepSummary.self, from: data)

        XCTAssertEqual(decoded.index, 1)
        XCTAssertEqual(decoded.tool, "click")
        XCTAssertEqual(decoded.purpose, "Input expression")
        XCTAssertTrue(decoded.success)
    }

    // MARK: - AC5: APIErrorResponse

    func test_apiErrorResponse_codable_roundTrip_preservesAllFields() throws {
        let error = APIErrorResponse(error: "missing_task", message: "Request body must include a 'task' field.")

        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(APIErrorResponse.self, from: data)

        XCTAssertEqual(decoded.error, "missing_task")
        XCTAssertEqual(decoded.message, "Request body must include a 'task' field.")
    }

    func test_apiErrorResponse_jsonKeys_areCorrect() throws {
        let error = APIErrorResponse(error: "run_not_found", message: "Run 'nonexistent-id' not found.")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(error)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"error\""), "APIErrorResponse JSON should contain 'error' key")
        XCTAssertTrue(json.contains("\"message\""), "APIErrorResponse JSON should contain 'message' key")
    }

    // MARK: - AC2/AC3: APIRunStatus

    func test_apiRunStatus_rawValues_matchExpectedStrings() {
        XCTAssertEqual(APIRunStatus.running.rawValue, "running")
        XCTAssertEqual(APIRunStatus.done.rawValue, "done")
        XCTAssertEqual(APIRunStatus.failed.rawValue, "failed")
        XCTAssertEqual(APIRunStatus.cancelled.rawValue, "cancelled")
    }

    func test_apiRunStatus_decodesFromValidStrings() throws {
        let statuses: [(String, APIRunStatus)] = [
            ("\"running\"", .running),
            ("\"done\"", .done),
            ("\"failed\"", .failed),
            ("\"cancelled\"", .cancelled),
        ]

        for (jsonString, expected) in statuses {
            let data = jsonString.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(APIRunStatus.self, from: data)
            XCTAssertEqual(decoded, expected, "Failed to decode \(jsonString) to \(expected)")
        }
    }

    func test_apiRunStatus_decodingInvalidString_throwsError() {
        let data = "\"unknown_status\"".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(APIRunStatus.self, from: data))
    }

    // MARK: - TrackedRun

    func test_trackedRun_codable_roundTrip_preservesAllFields() throws {
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

        XCTAssertEqual(decoded.runId, "20260513-abc123")
        XCTAssertEqual(decoded.task, "open calculator")
        XCTAssertEqual(decoded.status, .running)
        XCTAssertEqual(decoded.totalSteps, 1)
        XCTAssertEqual(decoded.steps.count, 1)
    }

    // MARK: - RunOptions

    func test_runOptions_codable_roundTrip_preservesAllFields() throws {
        let options = RunOptions(
            task: "open calculator",
            maxSteps: 10,
            maxBatches: 3,
            allowForeground: true
        )

        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(RunOptions.self, from: data)

        XCTAssertEqual(decoded.task, "open calculator")
        XCTAssertEqual(decoded.maxSteps, 10)
        XCTAssertEqual(decoded.maxBatches, 3)
        XCTAssertTrue(decoded.allowForeground!)
    }

    func test_runOptions_optionalFields_defaultToNil() throws {
        let options = RunOptions(task: "open calculator")

        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(RunOptions.self, from: data)

        XCTAssertEqual(decoded.task, "open calculator")
        XCTAssertNil(decoded.maxSteps)
        XCTAssertNil(decoded.maxBatches)
        XCTAssertNil(decoded.allowForeground)
    }
}
