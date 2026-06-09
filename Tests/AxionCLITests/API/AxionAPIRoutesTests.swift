import Testing
import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

@Suite("AxionAPIRoutes")
struct AxionAPIRoutesTests {

    // MARK: - SDK Route Tests

    @Test("GET /v1/health returns 200 with ok status")
    func healthEndpointReturns200WithOkStatus() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode(OpenAgentSDK.HealthResponse.self, from: response.body)
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

                let body = try JSONDecoder().decode(RunResponse.self, from: response.body)
                #expect(!body.runId.isEmpty)
                #expect(body.status == .queued)
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

                let body = try JSONDecoder().decode(RunResponse.self, from: response.body)
                #expect(!body.runId.isEmpty)
                #expect(body.status == .queued)
            }
        }
    }

    @Test("GET /v1/runs/{runId} for running task returns 200 with status")
    func getRunExistingRunReturns200WithStatus() async throws {
        let ctx = buildTestContext()

        // Submit and start a run via SDK tracker
        let run = await ctx.tracker.submitRun(task: "open calculator")
        try await ctx.tracker.startRun(runId: run.runId)

        try await ctx.app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(run.runId)", method: .get) { response in
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode(RunResponse.self, from: response.body)
                #expect(body.runId == run.runId)
                #expect(body.status == .running)
                #expect(body.task == "open calculator")
            }
        }
    }

    @Test("GET /v1/runs/{runId} for completed task returns full result")
    func getRunCompletedRunReturnsFullResult() async throws {
        let ctx = buildTestContext()

        // Submit, start, and complete a run
        let run = await ctx.tracker.submitRun(task: "open calculator")
        try await ctx.tracker.startRun(runId: run.runId)

        // Set steps and endedAt before completing (completeRun doesn't set these)
        let steps = [
            StepSummary(index: 0, tool: "launch_app", purpose: "Launch Calculator", success: true),
            StepSummary(index: 1, tool: "click", purpose: "Input expression", success: true),
            StepSummary(index: 2, tool: "click", purpose: "Verify result", success: true),
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let endedAt = formatter.string(from: Date())

        await ctx.tracker.updateRun(runId: run.runId, steps: steps, endedAt: endedAt)
        try await ctx.tracker.completeRun(runId: run.runId, resultText: "done", totalSteps: 3, durationMs: 8200)

        try await ctx.app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(run.runId)", method: .get) { response in
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode(RunResponse.self, from: response.body)
                #expect(body.status == .completed)
                #expect(body.steps?.count == 3)
                #expect(body.endedAt != nil)
            }
        }
    }

    @Test("GET /v1/runs/{runId} for non-existent run returns 404")
    func getRunNonExistentRunReturns404() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/nonexistent-id", method: .get) { response in
                #expect(response.status == .notFound)
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
            }
        }
    }

    @Test("SSE endpoint completed run with events returns event-stream content type")
    func sseEndpointCompletedRunReturnsEventStreamContentType() async throws {
        let ctx = buildTestContext()

        // Submit, start run
        let run = await ctx.tracker.submitRun(task: "open calculator")
        try await ctx.tracker.startRun(runId: run.runId)

        // Emit a step event to broadcaster
        let stepEvent = AgentSSEEvent.stepCompleted(StepCompletedData(
            stepIndex: 0,
            tool: "launch_app",
            success: true
        ))
        await ctx.broadcaster.emit(runId: run.runId, event: stepEvent)

        // Complete the run
        try await ctx.tracker.completeRun(runId: run.runId, resultText: "done", totalSteps: 1, durationMs: 5000)

        // Emit run_completed event
        let completedEvent = AgentSSEEvent.runCompleted(RunCompletedData(
            runId: run.runId,
            finalStatus: "completed",
            totalSteps: 1,
            durationMs: 5000
        ))
        await ctx.broadcaster.emit(runId: run.runId, event: completedEvent)
        await ctx.broadcaster.complete(runId: run.runId)

        try await ctx.app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(run.runId)/events", method: .get) { response in
                #expect(response.status == .ok)

                let contentType = response.headers[.contentType]
                #expect(contentType != nil)
                #expect(contentType?.contains("text/event-stream") ?? false)
            }
        }
    }

    @Test("SSE endpoint completed run replay includes event-stream content type")
    func sseEndpointCompletedRunReplayHeaders() async throws {
        let ctx = buildTestContext()

        // Submit, start, emit events, complete
        let run = await ctx.tracker.submitRun(task: "open calculator")
        try await ctx.tracker.startRun(runId: run.runId)

        let stepEvent = AgentSSEEvent.stepCompleted(StepCompletedData(
            stepIndex: 0, tool: "launch_app", success: true
        ))
        await ctx.broadcaster.emit(runId: run.runId, event: stepEvent)

        try await ctx.tracker.completeRun(runId: run.runId, resultText: "done", totalSteps: 1, durationMs: 5000)

        let completedEvent = AgentSSEEvent.runCompleted(RunCompletedData(
            runId: run.runId, finalStatus: "completed", totalSteps: 1, durationMs: 5000
        ))
        await ctx.broadcaster.emit(runId: run.runId, event: completedEvent)
        await ctx.broadcaster.complete(runId: run.runId)

        try await ctx.app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(run.runId)/events", method: .get) { response in
                #expect(response.status == .ok)
                // Completed run replay returns event-stream content type
                let contentType = response.headers[.contentType]
                #expect(contentType != nil)
                #expect(contentType?.contains("text/event-stream") ?? false)
            }
        }
    }

    @Test("Completed run SSE endpoint replays run_completed event")
    func sseEndpointCompletedRunReplaysRunCompletedEvent() async throws {
        let ctx = buildTestContext()

        let run = await ctx.tracker.submitRun(task: "open calculator")
        try await ctx.tracker.startRun(runId: run.runId)

        let completedEvent = AgentSSEEvent.runCompleted(RunCompletedData(
            runId: run.runId, finalStatus: "completed", totalSteps: 1, durationMs: 5000
        ))
        await ctx.broadcaster.emit(runId: run.runId, event: completedEvent)

        try await ctx.tracker.completeRun(runId: run.runId, resultText: "done", totalSteps: 1, durationMs: 5000)
        await ctx.broadcaster.complete(runId: run.runId)

        try await ctx.app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/\(run.runId)/events", method: .get) { response in
                #expect(response.status == .ok)

                let bodyString = String(buffer: response.body)
                #expect(bodyString.contains("event: run_completed"))
                #expect(bodyString.contains("\"final_status\":\"completed\""))
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

    @Test("GET /v1/runs/:runId with correct auth returns 200")
    func getRunWithAuthKeyCorrectTokenReturns200() async throws {
        let ctx = buildTestContext(authKey: "testsecret")

        let run = await ctx.tracker.submitRun(task: "open calculator")
        try await ctx.tracker.startRun(runId: run.runId)

        try await ctx.app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer testsecret"
            try await client.execute(uri: "/v1/runs/\(run.runId)", method: .get, headers: headers) { response in
                #expect(response.status == .ok)
                let body = try JSONDecoder().decode(RunResponse.self, from: response.body)
                #expect(body.runId == run.runId)
                #expect(body.status == .running)
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
        let ctx = buildTestContext(authKey: "testsecret")

        let run = await ctx.tracker.submitRun(task: "open calculator")
        try await ctx.tracker.startRun(runId: run.runId)

        let completedEvent = AgentSSEEvent.runCompleted(RunCompletedData(
            runId: run.runId, finalStatus: "completed", totalSteps: 1, durationMs: 5000
        ))
        await ctx.broadcaster.emit(runId: run.runId, event: completedEvent)

        try await ctx.tracker.completeRun(runId: run.runId, resultText: "done", totalSteps: 1, durationMs: 5000)
        await ctx.broadcaster.complete(runId: run.runId)

        try await ctx.app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer testsecret"
            try await client.execute(uri: "/v1/runs/\(run.runId)/events", method: .get, headers: headers) { response in
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

    @Test("Auth + concurrency limiter combined")
    func createRunAuthAndConcurrencyCombined() async throws {
        let app = try await buildTestApplication(authKey: "mykey")

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "{\"task\": \"open calculator\"}")
            try await client.execute(uri: "/v1/runs", method: .post, body: body) { response in
                #expect(response.status == .unauthorized)
            }

            var headers = HTTPFields()
            headers[.authorization] = "Bearer mykey"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: body) { response in
                #expect(response.status == .accepted)
                let decoded = try JSONDecoder().decode(RunResponse.self, from: response.body)
                #expect(decoded.status == .queued)
            }
        }
    }

    @Test("Health endpoint accessible without auth when auth is enabled")
    func healthEndpointAccessibleWithoutAuthWhenAuthEnabled() async throws {
        let app = try await buildTestApplication(authKey: "secret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .ok)
                let body = try JSONDecoder().decode(OpenAgentSDK.HealthResponse.self, from: response.body)
                #expect(body.status == "ok")
            }
        }
    }

    // MARK: - Capabilities Endpoint Tests (Story 14.2)

    @Test("GET /v1/capabilities returns 200 with complete structure")
    func capabilitiesEndpointReturnsCompleteStructure() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/capabilities", method: .get) { response in
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode(CapabilitiesResponse.self, from: response.body)
                #expect(!body.version.isEmpty)
                #expect(body.supportedRunStatuses == APIRunStatus.allCases.map(\.rawValue))
                #expect(body.supportedResultKinds == TaskResultKind.allCases.map(\.rawValue))
                #expect(body.availableTools == ToolNames.allToolNames)
                #expect(body.maxConcurrentRuns > 0)
                #expect(body.features.contains("memory"))
                #expect(body.features.contains("takeover"))
                #expect(body.features.contains("fast_mode"))
                #expect(body.features.contains("skills"))
            }
        }
    }

    @Test("GET /v1/capabilities returns Cache-Control max-age=300")
    func capabilitiesEndpointReturnsCacheControlHeader() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/capabilities", method: .get) { response in
                let cacheControl = response.headers[.cacheControl]
                #expect(cacheControl != nil)
                #expect(cacheControl?.contains("private") ?? false)
                #expect(cacheControl?.contains("max-age=300") ?? false)
            }
        }
    }

    @Test("GET /v1/capabilities requires auth when auth is enabled")
    func capabilitiesEndpointRequiresAuth() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/capabilities", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("GET /v1/capabilities with correct auth returns 200")
    func capabilitiesEndpointWithAuthReturns200() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer testsecret"
            try await client.execute(uri: "/v1/capabilities", method: .get, headers: headers) { response in
                #expect(response.status == .ok)
                let body = try JSONDecoder().decode(CapabilitiesResponse.self, from: response.body)
                #expect(!body.version.isEmpty)
            }
        }
    }

    @Test("GET /v1/capabilities reflects custom maxConcurrent value")
    func capabilitiesEndpointReflectsCustomMaxConcurrent() async throws {
        let app = try await buildTestApplication(maxConcurrent: 3)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/capabilities", method: .get) { response in
                let body = try JSONDecoder().decode(CapabilitiesResponse.self, from: response.body)
                #expect(body.maxConcurrentRuns == 3)
            }
        }
    }

    @Test("GET /v1/capabilities availableTools matches ToolNames.allToolNames")
    func capabilitiesEndpointAvailableToolsMatchesStaticList() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/capabilities", method: .get) { response in
                let body = try JSONDecoder().decode(CapabilitiesResponse.self, from: response.body)
                #expect(body.availableTools == ToolNames.allToolNames)
            }
        }
    }

    // MARK: - Settings API Tests (Story 14.3)

    @Test("GET /v1/settings/api-key returns 200 with missing status when no key")
    func settingsApiKeyGetReturnsMissingWhenNoKey() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/settings/api-key", method: .get) { response in
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode(ApiKeyStatusResponse.self, from: response.body)
                #expect(body.available == false)
                #expect(body.source == "missing")
                #expect(body.maskedKey == "")
                #expect(body.provider == "anthropic")
            }
        }
    }

    @Test("GET /v1/settings/api-key returns 200 with config status when key in config")
    func settingsApiKeyGetReturnsConfigWhenKeyPresent() async throws {
        let config = AxionConfig(apiKey: "sk-ant-api03-abcdefghijklmnop", provider: .anthropic)
        let app = try await buildTestApplication(config: config)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/settings/api-key", method: .get) { response in
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode(ApiKeyStatusResponse.self, from: response.body)
                #expect(body.available == true)
                #expect(body.source == "config")
                #expect(body.maskedKey == "sk-ant-****mnop")
                #expect(body.provider == "anthropic")
            }
        }
    }

    @Test("GET /v1/settings/api-key returns Cache-Control header")
    func settingsApiKeyGetReturnsCacheControlHeader() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/settings/api-key", method: .get) { response in
                let cacheControl = response.headers[.cacheControl]
                #expect(cacheControl != nil)
                #expect(cacheControl?.contains("private") ?? false)
                #expect(cacheControl?.contains("max-age=300") ?? false)
            }
        }
    }

    @Test("POST /v1/settings/api-key saves key and returns status")
    func settingsApiKeyPostSavesAndReturnsStatus() async throws {
        let tempDir = NSTemporaryDirectory() + "axion-settings-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let app = try await buildTestApplication(configDirectory: tempDir)

        try await app.test(.router) { client in
            let body = ByteBuffer(string: #"{"api_key":"sk-ant-test1234567890abcdefghijklmnop"}"#)
            try await client.execute(uri: "/v1/settings/api-key", method: .post, body: body) { response in
                #expect(response.status == .ok)

                let resp = try JSONDecoder().decode(ApiKeyStatusResponse.self, from: response.body)
                #expect(resp.available == true)
                #expect(resp.maskedKey.contains("****"))
            }

            // Verify the config file was written
            let configPath = (tempDir as NSString).appendingPathComponent("config.json")
            let savedData = try #require(FileManager.default.contents(atPath: configPath))
            let savedConfig = try JSONDecoder().decode(AxionConfig.self, from: savedData)
            #expect(savedConfig.apiKey == "sk-ant-test1234567890abcdefghijklmnop")
        }
    }

    @Test("POST /v1/settings/api-key with empty key returns 400")
    func settingsApiKeyPostEmptyKeyReturns400() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let body = ByteBuffer(string: #"{"api_key":""}"#)
            try await client.execute(uri: "/v1/settings/api-key", method: .post, body: body) { response in
                #expect(response.status == .badRequest)

                let error = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(error.error == "missing_api_key")
            }
        }
    }

    @Test("POST /v1/settings/api-key with invalid JSON returns 400")
    func settingsApiKeyPostInvalidJsonReturns400() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let body = ByteBuffer(string: "not json")
            try await client.execute(uri: "/v1/settings/api-key", method: .post, body: body) { response in
                #expect(response.status == .badRequest)

                let error = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(error.error == "invalid_request")
            }
        }
    }

    @Test("DELETE /v1/settings/api-key clears key and returns missing status")
    func settingsApiKeyDeleteClearsKey() async throws {
        let tempDir = NSTemporaryDirectory() + "axion-settings-delete-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Pre-populate config with a key
        var config = AxionConfig.default
        config.apiKey = "sk-ant-original-key-12345"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let initialData = try encoder.encode(config)
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: (tempDir as NSString).appendingPathComponent("config.json"), contents: initialData)

        let app = try await buildTestApplication(config: config, configDirectory: tempDir)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/settings/api-key", method: .delete) { response in
                #expect(response.status == .ok)

                let body = try JSONDecoder().decode(DeleteApiKeyResponse.self, from: response.body)
                #expect(body.available == false)
                #expect(body.source == "missing")
                #expect(body.provider == "anthropic")
            }

            // Verify config.json was updated
            let savedData = try #require(FileManager.default.contents(atPath: (tempDir as NSString).appendingPathComponent("config.json")))
            let savedConfig = try JSONDecoder().decode(AxionConfig.self, from: savedData)
            #expect(savedConfig.apiKey == nil)
        }
    }

    @Test("Settings API endpoints require auth when auth is enabled")
    func settingsApiRequiresAuth() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/settings/api-key", method: .get) { response in
                #expect(response.status == .unauthorized)
            }

            let body = ByteBuffer(string: #"{"api_key":"sk-test"}"#)
            try await client.execute(uri: "/v1/settings/api-key", method: .post, body: body) { response in
                #expect(response.status == .unauthorized)
            }

            try await client.execute(uri: "/v1/settings/api-key", method: .delete) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Settings API endpoints pass auth with correct token")
    func settingsApiPassesWithCorrectAuth() async throws {
        let app = try await buildTestApplication(authKey: "testsecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer testsecret"
            try await client.execute(uri: "/v1/settings/api-key", method: .get, headers: headers) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("POST writes config file that survives restart")
    func settingsApiKeyPostPersistsToConfigFile() async throws {
        let tempDir = NSTemporaryDirectory() + "axion-settings-roundtrip-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let savedKey = "sk-ant-saved-key-abcdefghijklmnop"
        let app = try await buildTestApplication(configDirectory: tempDir)

        try await app.test(.router) { client in
            let postBody = ByteBuffer(string: #"{"api_key":"\#(savedKey)"}"#)
            try await client.execute(uri: "/v1/settings/api-key", method: .post, body: postBody) { response in
                #expect(response.status == .ok)
            }
        }

        // Verify the key was persisted to disk (survives server restart)
        let configPath = (tempDir as NSString).appendingPathComponent("config.json")
        let savedData = try #require(FileManager.default.contents(atPath: configPath))
        let savedConfig = try JSONDecoder().decode(AxionConfig.self, from: savedData)
        #expect(savedConfig.apiKey == savedKey)

        // Simulate a restart: create a new app instance with the persisted config
        let restartedApp = try await buildTestApplication(config: savedConfig, configDirectory: tempDir)
        try await restartedApp.test(.router) { client in
            try await client.execute(uri: "/v1/settings/api-key", method: .get) { response in
                #expect(response.status == .ok)
                let body = try JSONDecoder().decode(ApiKeyStatusResponse.self, from: response.body)
                #expect(body.available == true)
                #expect(body.source == "config")
                #expect(body.maskedKey == "sk-ant-****mnop")
            }
        }
    }

    // MARK: - Test Helpers

    /// Context holding both the test app and SDK components for pre-populating runs.
    private struct TestContext {
        let app: Application<RouterResponder<BasicRequestContext>>
        let tracker: RunTracker
        let broadcaster: EventBroadcaster
    }

    private func buildTestContext(
        authKey: String? = nil,
        maxConcurrent: Int = 10,
        config: AxionConfig = .default,
        configDirectory: String? = nil
    ) -> TestContext {
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        let server = AgentHTTPServer(
            agent: placeholderAgent,
            authKey: authKey,
            maxConcurrentRuns: maxConcurrent
        )

        let runCoordinator = RunCoordinator()
        server.customRouteBuilder = { [runCoordinator] routerGroup, _, broadcaster, _, _ in
            AxionAPI.registerCustomRoutes(
                on: routerGroup,
                runCoordinator: runCoordinator,
                eventBroadcaster: broadcaster,
                config: config,
                maxConcurrentRuns: maxConcurrent,
                skillRegistry: nil,
                configDirectory: configDirectory
            )
        }

        let app = server.buildTestApplication()
        return TestContext(
            app: app,
            tracker: server.runTracker,
            broadcaster: server.eventBroadcaster
        )
    }

    private func buildTestApplication(
        authKey: String? = nil,
        maxConcurrent: Int = 10,
        config: AxionConfig = .default,
        configDirectory: String? = nil
    ) async throws -> Application<RouterResponder<BasicRequestContext>> {
        let ctx = buildTestContext(
            authKey: authKey,
            maxConcurrent: maxConcurrent,
            config: config,
            configDirectory: configDirectory
        )
        return ctx.app
    }
}
