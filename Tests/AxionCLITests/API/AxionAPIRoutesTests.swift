import Testing
import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
@testable import AxionCLI

@Suite("AxionAPIRoutes")
struct AxionAPIRoutesTests {

    @Test("GET /v1/health returns 200 with ok status")
    func healthEndpointReturns200WithOkStatus() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode(HealthResponse.self, from: response.body)
                #expect(body.status == "ok")
                #expect(!body.version.isEmpty)
            }
        }
    }

    @Test("POST /v1/runs without task returns 400")
    func createRunMissingTaskReturns400() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let emptyBody = ByteBuffer(string: "{}")

            try await client.execute(uri: "/v1/runs", method: .post, body: emptyBody) { response in
                #expect(response.status == .badRequest)

                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(!body.error.isEmpty)
                #expect(!body.message.isEmpty)
            }
        }
    }

    @Test("POST /v1/runs with no task field returns 400 with missing_task error")
    func createRunNoTaskFieldReturns400WithMissingTaskError() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let noTaskBody = ByteBuffer(string: "{\"max_steps\": 10}")

            try await client.execute(uri: "/v1/runs", method: .post, body: noTaskBody) { response in
                #expect(response.status == .badRequest)

                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(body.error == "missing_task")
            }
        }
    }

    @Test("POST /v1/runs with valid task returns 202 with runId")
    func createRunValidTaskReturns202WithRunId() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let requestBody = ByteBuffer(string: "{\"task\": \"open calculator\"}")

            try await client.execute(uri: "/v1/runs", method: .post, body: requestBody) { response in
                #expect(response.status == .accepted)

                let body = try JSONDecoder().decode(CreateRunResponse.self, from: response.body)
                #expect(!body.runId.isEmpty)
                #expect(body.status == "running")
            }
        }
    }

    @Test("POST /v1/runs with options returns 202")
    func createRunWithOptionsReturns202() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let requestBody = ByteBuffer(string: """
            {"task": "open calculator", "max_steps": 5, "max_batches": 2, "allow_foreground": false}
            """)

            try await client.execute(uri: "/v1/runs", method: .post, body: requestBody) { response in
                #expect(response.status == .accepted)

                let body = try JSONDecoder().decode(CreateRunResponse.self, from: response.body)
                #expect(!body.runId.isEmpty)
                #expect(body.status == "running")
            }
        }
    }

    @Test("GET /v1/runs/{runId} for running task returns 200 with status")
    func getRunExistingRunReturns200WithStatus() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let app = try await buildTestApplication(runTracker: tracker)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(runId)", method: .get) { response in
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode(RunStatusResponse.self, from: response.body)
                #expect(body.runId == runId)
                #expect(body.status == "running")
                #expect(body.task == "open calculator")
            }
        }
    }

    @Test("GET /v1/runs/{runId} for completed task returns full result")
    func getRunCompletedRunReturnsFullResult() async throws {
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
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode(RunStatusResponse.self, from: response.body)
                #expect(body.status == "done")
                #expect(body.totalSteps == 3)
                #expect(body.durationMs == 8200)
                #expect(body.replanCount == 0)
                #expect(body.steps.count == 3)
            }
        }
    }

    @Test("GET /v1/runs/{runId} for non-existent run returns 404")
    func getRunNonExistentRunReturns404() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/nonexistent-id", method: .get) { response in
                #expect(response.status == .notFound)

                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(body.error == "run_not_found")
            }
        }
    }

    @Test("Health endpoint returns JSON content type")
    func healthEndpointReturnsJsonContentType() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                let contentType = response.headers[.contentType]
                #expect(contentType != nil)
                #expect(contentType?.contains("application/json") ?? false)
            }
        }
    }

    @Test("SSE endpoint non-existent run returns 404")
    func sseEndpointNonExistentRunReturns404() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/nonexistent-id/events", method: .get) { response in
                #expect(response.status == .notFound)

                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(body.error == "run_not_found")
            }
        }
    }

    @Test("SSE endpoint existing run returns event-stream content type")
    func sseEndpointExistingRunReturnsEventStreamContentType() async throws {
        let broadcaster = EventBroadcaster()
        let tracker = RunTracker(eventBroadcaster: broadcaster)
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        await tracker.updateRun(runId: runId, status: .done, steps: [step], durationMs: 5000, replanCount: 0)

        let app = try await buildTestApplication(runTracker: tracker, eventBroadcaster: broadcaster)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(runId)/events", method: .get) { response in
                #expect(response.status == .ok)

                let contentType = response.headers[.contentType]
                #expect(contentType != nil)
                #expect(contentType?.contains("text/event-stream") ?? false)
            }
        }
    }

    @Test("SSE endpoint response headers are correct")
    func sseEndpointResponseHeadersAreCorrect() async throws {
        let broadcaster = EventBroadcaster()
        let tracker = RunTracker(eventBroadcaster: broadcaster)
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        await tracker.updateRun(runId: runId, status: .done, steps: [step], durationMs: 5000, replanCount: 0)

        let app = try await buildTestApplication(runTracker: tracker, eventBroadcaster: broadcaster)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(runId)/events", method: .get) { response in
                let cacheControl = response.headers[.cacheControl]
                #expect(cacheControl != nil)
                #expect(cacheControl?.contains("no-cache") ?? false)
            }
        }
    }

    @Test("Completed run SSE endpoint replays run_completed event")
    func sseEndpointCompletedRunReplaysRunCompletedEvent() async throws {
        let broadcaster = EventBroadcaster()
        let tracker = RunTracker(eventBroadcaster: broadcaster)
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let step = StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true)
        await tracker.updateRun(runId: runId, status: .done, steps: [step], durationMs: 5000, replanCount: 0)

        let app = try await buildTestApplication(runTracker: tracker, eventBroadcaster: broadcaster)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(runId)/events", method: .get) { response in
                #expect(response.status == .ok)

                let bodyString = String(buffer: response.body)
                #expect(bodyString.contains("event: run_completed"))
                #expect(bodyString.contains("\"final_status\":\"done\""))
                #expect(bodyString.contains("data: "))
            }
        }
    }

    @Test("Auth-key enabled POST /v1/runs without Authorization returns 401")
    func createRunWithAuthKeyNoHeaderReturns401() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Correct Bearer token passes auth")
    func createRunWithAuthKeyCorrectTokenPasses() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer testsecret"
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: body) { response in
                #expect(response.status == .accepted)
            }
        }
    }

    @Test("Concurrency limit full returns queued response")
    func createRunConcurrencyLimitFullReturnsQueuedResponse() async throws {
        let tracker = RunTracker()
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let app = try await buildTestApplication(runTracker: tracker, concurrencyLimiter: limiter)

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                #expect(response.status == .accepted)
                let decoded = try JSONDecoder().decode(QueuedRunResponse.self, from: response.body)
                #expect(decoded.status == "queued")
                #expect(decoded.position >= 1)
            }
        }
    }

    @Test("GET /v1/runs/:runId with correct auth returns 200")
    func getRunWithAuthKeyCorrectTokenReturns200() async throws {
        let tracker = RunTracker()
        let runId = await tracker.submitRun(task: "open calculator", options: RunOptions(task: "open calculator"))

        let app = try await buildTestApplication(runTracker: tracker, authKey: "testsecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer testsecret"
            try await client.execute(uri: "/v1/runs/\(runId)", method: .get, headers: headers) { response in
                #expect(response.status == .ok)
                let body = try JSONDecoder().decode(RunStatusResponse.self, from: response.body)
                #expect(body.runId == runId)
                #expect(body.status == "running")
            }
        }
    }

    @Test("GET /v1/runs/:runId without auth returns 401")
    func getRunWithAuthKeyNoHeaderReturns401() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/some-id", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("SSE endpoint with correct auth returns 200")
    func sseEndpointWithAuthKeyCorrectTokenReturns200() async throws {
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
                #expect(response.status == .ok)
            }
        }
    }

    @Test("SSE endpoint without auth returns 401")
    func sseEndpointWithAuthKeyNoHeaderReturns401() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/some-id/events", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Queued response JSON format is valid")
    func queuedResponseJsonFormatIsValid() async throws {
        let tracker = RunTracker()
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let app = try await buildTestApplication(runTracker: tracker, concurrencyLimiter: limiter)

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                #expect(response.status == .accepted)
                let decoded = try JSONDecoder().decode(QueuedRunResponse.self, from: response.body)
                #expect(decoded.status == "queued")
                #expect(decoded.position >= 1)
                #expect(!decoded.runId.isEmpty)
            }
        }
    }

    @Test("No auth + no limiter returns running status (original behavior)")
    func createRunNoAuthNoLimiterReturnsRunningStatus() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                #expect(response.status == .accepted)
                let decoded = try JSONDecoder().decode(CreateRunResponse.self, from: response.body)
                #expect(decoded.status == "running")
                #expect(!decoded.runId.isEmpty)
            }
        }
    }

    @Test("Auth + concurrency limiter combined")
    func createRunAuthAndConcurrencyCombined() async throws {
        let tracker = RunTracker()
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        _ = await limiter.acquire()

        let app = try await buildTestApplication(runTracker: tracker, authKey: "mykey", concurrencyLimiter: limiter)

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                #expect(response.status == .unauthorized)
            }

            var headers = HTTPFields()
            headers[.authorization] = "Bearer mykey"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: body) { response in
                #expect(response.status == .accepted)
                let decoded = try JSONDecoder().decode(QueuedRunResponse.self, from: response.body)
                #expect(decoded.status == "queued")
            }
        }
    }

    @Test("Health endpoint accessible without auth when auth is enabled")
    func healthEndpointAccessibleWithoutAuthWhenAuthEnabled() async throws {
        let app = try await buildTestApplication(authKey: "secret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .ok)
                let body = try JSONDecoder().decode(HealthResponse.self, from: response.body)
                #expect(body.status == "ok")
            }
        }
    }

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
