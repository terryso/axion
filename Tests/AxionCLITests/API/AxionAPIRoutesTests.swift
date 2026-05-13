import XCTest
import Hummingbird
import HummingbirdTesting
import HTTPTypes
@testable import AxionCLI

// [P0] ATDD GREEN-PHASE — Story 5.1 AC1-AC6
// Tests using Hummingbird 2.x router-based testing framework.

final class AxionAPIRoutesTests: XCTestCase {

    // MARK: - AC6: GET /v1/health

    func test_healthEndpoint_returns200WithOkStatus() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                XCTAssertEqual(response.status, .ok, "Health endpoint should return 200")

                let body = try JSONDecoder().decode(HealthResponse.self, from: response.body)
                XCTAssertEqual(body.status, "ok")
                XCTAssertFalse(body.version.isEmpty, "Version should not be empty")
            }
        }
    }

    // MARK: - AC5: POST /v1/runs without task returns 400

    func test_createRun_missingTask_returns400() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let emptyBody = ByteBuffer(string: "{}")

            try await client.execute(uri: "/v1/runs", method: .post, body: emptyBody) { response in
                XCTAssertEqual(response.status, .badRequest, "Missing task should return 400")

                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                XCTAssertFalse(body.error.isEmpty, "Error code should not be empty")
                XCTAssertFalse(body.message.isEmpty, "Error message should not be empty")
            }
        }
    }

    func test_createRun_noTaskField_returns400WithMissingTaskError() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let noTaskBody = ByteBuffer(string: "{\"max_steps\": 10}")

            try await client.execute(uri: "/v1/runs", method: .post, body: noTaskBody) { response in
                XCTAssertEqual(response.status, .badRequest)

                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                XCTAssertEqual(body.error, "missing_task")
            }
        }
    }

    // MARK: - AC2: POST /v1/runs with valid task returns 202

    func test_createRun_validTask_returns202WithRunId() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let requestBody = ByteBuffer(string: "{\"task\": \"open calculator\"}")

            try await client.execute(uri: "/v1/runs", method: .post, body: requestBody) { response in
                XCTAssertEqual(response.status, .accepted, "Valid task submission should return 202 Accepted")

                let body = try JSONDecoder().decode(CreateRunResponse.self, from: response.body)
                XCTAssertFalse(body.runId.isEmpty, "Response should contain a non-empty runId")
                XCTAssertEqual(body.status, "running")
            }
        }
    }

    func test_createRun_withOptions_returns202() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let requestBody = ByteBuffer(string: """
            {"task": "open calculator", "max_steps": 5, "max_batches": 2, "allow_foreground": false}
            """)

            try await client.execute(uri: "/v1/runs", method: .post, body: requestBody) { response in
                XCTAssertEqual(response.status, .accepted)

                let body = try JSONDecoder().decode(CreateRunResponse.self, from: response.body)
                XCTAssertFalse(body.runId.isEmpty)
                XCTAssertEqual(body.status, "running")
            }
        }
    }

    // MARK: - AC3: GET /v1/runs/{runId} for running task

    func test_getRun_existingRun_returns200WithStatus() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let app = try await buildTestApplication(runTracker: tracker)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(runId)", method: .get) { response in
                XCTAssertEqual(response.status, .ok, "Existing run should return 200")

                let body = try JSONDecoder().decode(RunStatusResponse.self, from: response.body)
                XCTAssertEqual(body.runId, runId)
                XCTAssertEqual(body.status, "running")
                XCTAssertEqual(body.task, "open calculator")
            }
        }
    }

    // MARK: - AC4: GET /v1/runs/{runId} for completed task

    func test_getRun_completedRun_returnsFullResult() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))
        let steps = [
            StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true),
            StepSummary(index: 1, tool: "click", purpose: "Input expression", success: true),
            StepSummary(index: 2, tool: "click", purpose: "Verify result", success: true),
        ]
        await tracker.updateRun(runId: runId, status: .done, steps: steps, durationMs: 8200, replanCount: 0)

        let app = try await buildTestApplication(runTracker: tracker)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(runId)", method: .get) { response in
                XCTAssertEqual(response.status, .ok)

                let body = try JSONDecoder().decode(RunStatusResponse.self, from: response.body)
                XCTAssertEqual(body.status, "done")
                XCTAssertEqual(body.totalSteps, 3)
                XCTAssertEqual(body.durationMs, 8200)
                XCTAssertEqual(body.replanCount, 0)
                XCTAssertEqual(body.steps.count, 3)
            }
        }
    }

    // MARK: - GET /v1/runs/{runId} for non-existent run

    func test_getRun_nonExistentRun_returns404() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/nonexistent-id", method: .get) { response in
                XCTAssertEqual(response.status, .notFound, "Non-existent run should return 404")

                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                XCTAssertEqual(body.error, "run_not_found")
            }
        }
    }

    // MARK: - AC1: Server startup response format

    func test_healthEndpoint_returnsJsonContentType() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                let contentType = response.headers[.contentType]
                XCTAssertNotNil(contentType, "Response should have content-type header")
                XCTAssertTrue(contentType?.contains("application/json") ?? false, "Content-type should be application/json, got: \(contentType ?? "nil")")
            }
        }
    }

    // MARK: - Helper

    private func buildTestApplication(runTracker: RunTracker? = nil) async throws -> Application<RouterResponder<BasicRequestContext>> {
        let tracker = runTracker ?? RunTracker()
        let router = Router()
        AxionAPI.registerRoutes(on: router, runTracker: tracker, config: .default)

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
        return app
    }
}
