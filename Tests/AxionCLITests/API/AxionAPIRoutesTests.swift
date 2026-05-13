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

    // MARK: - Story 5.2: SSE endpoint tests (RED-PHASE)

    // AC1/AC4: GET /v1/runs/{runId}/events — non-existent runId returns 404
    func test_sseEndpoint_nonExistentRun_returns404() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/nonexistent-id/events", method: .get) { response in
                XCTAssertEqual(response.status, .notFound, "SSE endpoint should return 404 for non-existent runId")

                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                XCTAssertEqual(body.error, "run_not_found")
            }
        }
    }

    // AC1: GET /v1/runs/{runId}/events — returns text/event-stream content type
    func test_sseEndpoint_existingRun_returnsEventStreamContentType() async throws {
        let broadcaster = EventBroadcaster()
        let tracker = RunTracker(eventBroadcaster: broadcaster)
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        // Complete the run so the SSE response is finite (replay path)
        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        await tracker.updateRun(runId: runId, status: .done, steps: [step], durationMs: 5000, replanCount: 0)

        let app = try await buildTestApplication(runTracker: tracker, eventBroadcaster: broadcaster)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(runId)/events", method: .get) { response in
                XCTAssertEqual(response.status, .ok, "SSE endpoint should return 200 for existing run")

                let contentType = response.headers[.contentType]
                XCTAssertNotNil(contentType, "Response should have content-type header")
                XCTAssertTrue(
                    contentType?.contains("text/event-stream") ?? false,
                    "Content-type should be text/event-stream, got: \(contentType ?? "nil")"
                )
            }
        }
    }

    // AC1: SSE response has correct cache-control and connection headers
    func test_sseEndpoint_responseHeaders_areCorrect() async throws {
        let broadcaster = EventBroadcaster()
        let tracker = RunTracker(eventBroadcaster: broadcaster)
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        // Complete the run so the SSE response is finite (replay path)
        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        await tracker.updateRun(runId: runId, status: .done, steps: [step], durationMs: 5000, replanCount: 0)

        let app = try await buildTestApplication(runTracker: tracker, eventBroadcaster: broadcaster)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(runId)/events", method: .get) { response in
                let cacheControl = response.headers[.cacheControl]
                XCTAssertNotNil(cacheControl, "SSE response should have cache-control header")
                XCTAssertTrue(
                    cacheControl?.contains("no-cache") ?? false,
                    "Cache-control should be no-cache"
                )
            }
        }
    }

    // AC4: completed run returns run_completed event and closes
    func test_sseEndpoint_completedRun_replaysRunCompletedEvent() async throws {
        let broadcaster = EventBroadcaster()
        let tracker = RunTracker(eventBroadcaster: broadcaster)
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        // Complete the run
        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        await tracker.updateRun(runId: runId, status: .done, steps: [step], durationMs: 5000, replanCount: 0)

        let app = try await buildTestApplication(runTracker: tracker, eventBroadcaster: broadcaster)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(runId)/events", method: .get) { response in
                XCTAssertEqual(response.status, .ok)

                let bodyString = String(buffer: response.body)
                XCTAssertTrue(
                    bodyString.contains("event: run_completed"),
                    "SSE response for completed run should contain 'event: run_completed'"
                )
                XCTAssertTrue(
                    bodyString.contains("\"final_status\":\"done\""),
                    "SSE replay should contain the final status"
                )
                XCTAssertTrue(
                    bodyString.contains("data: "),
                    "SSE response should contain 'data: ' lines"
                )
            }
        }
    }

    // MARK: - Story 5.3: Auth + Concurrency tests

    // AC1: Auth-key enabled, POST /v1/runs without Authorization → 401
    func test_createRun_withAuthKey_noHeader_returns401() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }
        }
    }

    // AC2: Correct Bearer token → request passes
    func test_createRun_withAuthKey_correctToken_passes() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer testsecret"
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: body) { response in
                XCTAssertEqual(response.status, .accepted)
            }
        }
    }

    // AC4: Concurrency limit — queued response
    func test_createRun_concurrencyLimitFull_returnsQueuedResponse() async throws {
        let tracker = RunTracker()
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        // Fill the slot
        _ = await limiter.acquire()

        let app = try await buildTestApplication(runTracker: tracker, concurrencyLimiter: limiter)

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                XCTAssertEqual(response.status, .accepted)
                let decoded = try JSONDecoder().decode(QueuedRunResponse.self, from: response.body)
                XCTAssertEqual(decoded.status, "queued")
                XCTAssertGreaterThanOrEqual(decoded.position, 1)
            }
        }
    }

    // MARK: - Story 5.3: E2E auth + concurrency scenarios

    // AC2: GET /v1/runs/:runId with correct auth → 200
    func test_getRun_withAuthKey_correctToken_returns200() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let app = try await buildTestApplication(runTracker: tracker, authKey: "testsecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer testsecret"
            try await client.execute(uri: "/v1/runs/\(runId)", method: .get, headers: headers) { response in
                XCTAssertEqual(response.status, .ok)
                let body = try JSONDecoder().decode(RunStatusResponse.self, from: response.body)
                XCTAssertEqual(body.runId, runId)
                XCTAssertEqual(body.status, "running")
            }
        }
    }

    // AC1: GET /v1/runs/:runId without auth → 401
    func test_getRun_withAuthKey_noHeader_returns401() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/some-id", method: .get) { response in
                XCTAssertEqual(response.status, .unauthorized, "GET run without auth should return 401")
            }
        }
    }

    // AC2: SSE endpoint with correct auth → 200
    func test_sseEndpoint_withAuthKey_correctToken_returns200() async throws {
        let broadcaster = EventBroadcaster()
        let tracker = RunTracker(eventBroadcaster: broadcaster)
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        await tracker.updateRun(runId: runId, status: .done, steps: [step], durationMs: 5000, replanCount: 0)

        let app = try await buildTestApplication(runTracker: tracker, eventBroadcaster: broadcaster, authKey: "testsecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer testsecret"
            try await client.execute(uri: "/v1/runs/\(runId)/events", method: .get, headers: headers) { response in
                XCTAssertEqual(response.status, .ok, "SSE with correct auth should return 200")
            }
        }
    }

    // AC1: SSE endpoint without auth → 401
    func test_sseEndpoint_withAuthKey_noHeader_returns401() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/some-id/events", method: .get) { response in
                XCTAssertEqual(response.status, .unauthorized, "SSE without auth should return 401")
            }
        }
    }

    // AC4: Queued response JSON format — run_id not empty, status = "queued", position >= 1
    func test_queuedResponse_jsonFormatIsValid() async throws {
        let tracker = RunTracker()
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let app = try await buildTestApplication(runTracker: tracker, concurrencyLimiter: limiter)

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                XCTAssertEqual(response.status, .accepted)
                let decoded = try JSONDecoder().decode(QueuedRunResponse.self, from: response.body)
                XCTAssertEqual(decoded.status, "queued", "Queued response status should be 'queued'")
                XCTAssertGreaterThanOrEqual(decoded.position, 1, "Queued position should be >= 1")
                XCTAssertFalse(decoded.runId.isEmpty, "Queued response should have a non-empty runId")
            }
        }
    }

    // Regression: no auth + no limiter = original behavior (Story 5.1)
    func test_createRun_noAuthNoLimiter_returnsRunningStatus() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                XCTAssertEqual(response.status, .accepted)
                let decoded = try JSONDecoder().decode(CreateRunResponse.self, from: response.body)
                XCTAssertEqual(decoded.status, "running", "Without limiter, status should be 'running'")
                XCTAssertFalse(decoded.runId.isEmpty)
            }
        }
    }

    // AC1+AC4: Auth + concurrency limiter combined
    func test_createRun_authAndConcurrency_combined() async throws {
        let tracker = RunTracker()
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let app = try await buildTestApplication(runTracker: tracker, authKey: "mykey", concurrencyLimiter: limiter)

        try await app.test(.router) { client in
            // Without auth → 401 (not queued)
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                XCTAssertEqual(response.status, .unauthorized, "Auth should be checked before concurrency")
            }

            // With auth → queued (concurrency full)
            var headers = HTTPFields()
            headers[.authorization] = "Bearer mykey"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: body) { response in
                XCTAssertEqual(response.status, .accepted)
                let decoded = try JSONDecoder().decode(QueuedRunResponse.self, from: response.body)
                XCTAssertEqual(decoded.status, "queued")
            }
        }
    }

    // AC5: Health endpoint accessible without auth even when auth is configured
    func test_healthEndpoint_accessibleWithoutAuth_whenAuthEnabled() async throws {
        let app = try await buildTestApplication(authKey: "secret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let body = try JSONDecoder().decode(HealthResponse.self, from: response.body)
                XCTAssertEqual(body.status, "ok")
            }
        }
    }

    // MARK: - Helper

    private func buildTestApplication(
        runTracker: RunTracker? = nil,
        eventBroadcaster: EventBroadcaster? = nil,
        authKey: String? = nil,
        concurrencyLimiter: ConcurrencyLimiter? = nil
    ) async throws -> Application<RouterResponder<BasicRequestContext>> {
        let broadcaster = eventBroadcaster ?? EventBroadcaster()
        let tracker = runTracker ?? RunTracker(eventBroadcaster: broadcaster)
        let router = Router()
        AxionAPI.registerRoutes(
            on: router,
            runTracker: tracker,
            eventBroadcaster: broadcaster,
            config: .default,
            authKey: authKey,
            concurrencyLimiter: concurrencyLimiter
        )

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
        return app
    }
}
