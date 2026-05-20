import XCTest
import Hummingbird
@testable import OpenAgentSDK

// MARK: - Mock LLM Client

/// Mock LLMClient that returns a simple text-only streaming response.
/// Produces: .assistant → .result SDKMessages (no tool calls).
private struct MockLLMClient: LLMClient, Sendable {
    let responseText: String

    init(responseText: String = "mock response") {
        self.responseText = responseText
    }

    nonisolated func sendMessage(
        model: String, messages: [[String: Any]], maxTokens: Int,
        system: String?, tools: [[String: Any]]?, toolChoice: [String: Any]?,
        thinking: [String: Any]?, temperature: Double?
    ) async throws -> [String: Any] {
        return [
            "id": "msg_mock",
            "content": [["type": "text", "text": responseText]],
            "stop_reason": "end_turn",
            "model": model
        ]
    }

    nonisolated func streamMessage(
        model: String, messages: [[String: Any]], maxTokens: Int,
        system: String?, tools: [[String: Any]]?, toolChoice: [String: Any]?,
        thinking: [String: Any]?, temperature: Double?
    ) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let text = responseText
        return AsyncThrowingStream { continuation in
            continuation.yield(.messageStart(message: [
                "type": "message_start",
                "message": ["model": model, "usage": ["input_tokens": 10]]
            ]))
            continuation.yield(.contentBlockStart(index: 0, contentBlock: ["type": "text"]))
            continuation.yield(.contentBlockDelta(index: 0, delta: [
                "type": "text_delta", "text": text
            ]))
            continuation.yield(.contentBlockStop(index: 0))
            continuation.yield(.messageDelta(delta: [
                "stop_reason": "end_turn"
            ], usage: ["output_tokens": 5]))
            continuation.yield(.messageStop)
            continuation.finish()
        }
    }
}

// MARK: - HTTP Integration Tests

/// Integration tests that start AgentHTTPServer on a real port
/// and make actual HTTP requests via URLSession.
final class HTTPIntegrationTests: XCTestCase {

    private var server: AgentHTTPServer!
    private var tempDir: String!
    private let port = 54291 + Int(arc4random_uniform(1000))
    private let authKey = "test-secret-key"

    override func setUp() async throws {
        tempDir = NSTemporaryDirectory()
            .appending("HTTPIntegrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true
        )

        let mockClient = MockLLMClient(responseText: "integration test result")
        let agent = Agent(
            options: AgentOptions(apiKey: "mock-key"),
            client: mockClient
        )

        server = AgentHTTPServer(
            agent: agent,
            host: "127.0.0.1",
            port: port,
            authKey: authKey,
            dataDir: tempDir
        )

        // Start server in background — app.runService() blocks
        let capturedServer = server!
        _Concurrency.Task {
            try? await capturedServer.start()
        }

        // Wait for server to become ready
        try await _Concurrency.Task.sleep(for: .milliseconds(300))
    }

    override func tearDown() async throws {
        await server.stop()
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    // MARK: - Helpers

    private var baseURL: String { "http://127.0.0.1:\(port)" }

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        authenticated: Bool = true
    ) async throws -> (statusCode: Int, data: Data) {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated {
            request.setValue("Bearer \(authKey)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (statusCode, data)
    }

    // MARK: - Health Endpoint (no auth required)

    func testHealthEndpointReturns200() async throws {
        let (status, data) = try await makeRequest(
            path: "/v1/health", authenticated: false
        )
        XCTAssertEqual(status, 200)

        let body = try JSONDecoder().decode(
            [String: String].self, from: data
        )
        XCTAssertEqual(body["status"], "ok")
        XCTAssertEqual(body["version"], "1.0.0")
    }

    func testHealthEndpointBypassesAuth() async throws {
        // No auth header — health should still work
        let (status, _) = try await makeRequest(
            path: "/v1/health", authenticated: false
        )
        XCTAssertEqual(status, 200)
    }

    // MARK: - Auth Middleware

    func testUnauthenticatedRequestReturns401() async throws {
        let (status, _) = try await makeRequest(
            path: "/v1/runs", authenticated: false
        )
        XCTAssertEqual(status, 401)
    }

    func testInvalidTokenReturns401() async throws {
        let url = URL(string: "\(baseURL)/v1/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer wrong-key", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        XCTAssertEqual(statusCode, 401)
    }

    func testValidTokenReturns200() async throws {
        let (status, _) = try await makeRequest(
            path: "/v1/runs", method: "GET", authenticated: true
        )
        XCTAssertEqual(status, 200)
    }

    // MARK: - POST /v1/runs

    func testPostRunReturns202() async throws {
        let body = try JSONEncoder().encode(CreateRunRequest(task: "test task"))
        let (status, data) = try await makeRequest(
            path: "/v1/runs", method: "POST", body: body
        )
        XCTAssertEqual(status, 202)

        let response = try JSONDecoder().decode(RunResponse.self, from: data)
        XCTAssertFalse(response.runId.isEmpty)
        XCTAssertEqual(response.status, .queued)
        XCTAssertEqual(response.task, "test task")
    }

    func testPostRunWithEmptyTaskReturns400() async throws {
        let body = try JSONEncoder().encode(CreateRunRequest(task: ""))
        let (status, _) = try await makeRequest(
            path: "/v1/runs", method: "POST", body: body
        )
        XCTAssertEqual(status, 400)
    }

    func testPostRunWithInvalidJSONReturns400() async throws {
        let body = Data("{ invalid json }".utf8)
        let (status, _) = try await makeRequest(
            path: "/v1/runs", method: "POST", body: body
        )
        XCTAssertEqual(status, 400)
    }

    // MARK: - GET /v1/runs

    func testListRunsReturnsEmptyInitially() async throws {
        let (status, data) = try await makeRequest(
            path: "/v1/runs", method: "GET"
        )
        XCTAssertEqual(status, 200)

        let runs = try JSONDecoder().decode([RunResponse].self, from: data)
        XCTAssertTrue(runs.isEmpty)
    }

    func testListRunsAfterPost() async throws {
        // Submit a run
        let body = try JSONEncoder().encode(CreateRunRequest(task: "list test"))
        let (_, postData) = try await makeRequest(
            path: "/v1/runs", method: "POST", body: body
        )
        let posted = try JSONDecoder().decode(RunResponse.self, from: postData)

        // List runs
        let (status, listData) = try await makeRequest(
            path: "/v1/runs", method: "GET"
        )
        XCTAssertEqual(status, 200)

        let runs = try JSONDecoder().decode([RunResponse].self, from: listData)
        XCTAssertTrue(runs.contains { $0.runId == posted.runId })
    }

    // MARK: - GET /v1/runs/{id}

    func testGetRunStatus() async throws {
        // Submit a run
        let body = try JSONEncoder().encode(CreateRunRequest(task: "status test"))
        let (_, postData) = try await makeRequest(
            path: "/v1/runs", method: "POST", body: body
        )
        let posted = try JSONDecoder().decode(RunResponse.self, from: postData)

        // Get run status
        let (status, data) = try await makeRequest(
            path: "/v1/runs/\(posted.runId)", method: "GET"
        )
        XCTAssertEqual(status, 200)

        let run = try JSONDecoder().decode(RunResponse.self, from: data)
        XCTAssertEqual(run.runId, posted.runId)
        XCTAssertEqual(run.task, "status test")
    }

    func testGetNonexistentRunReturns404() async throws {
        let (status, _) = try await makeRequest(
            path: "/v1/runs/nonexistent-id", method: "GET"
        )
        XCTAssertEqual(status, 404)
    }

    // MARK: - No Auth Key Configured

    func testServerWithoutAuthAllowsAllRequests() async throws {
        // Create server without auth key
        let noAuthTempDir = NSTemporaryDirectory()
            .appending("HTTPIntegrationNoAuth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            atPath: noAuthTempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: noAuthTempDir) }

        let noAuthPort = port + 500
        let mockClient = MockLLMClient()
        let agent = Agent(
            options: AgentOptions(apiKey: "mock"),
            client: mockClient
        )
        let noAuthServer = AgentHTTPServer(
            agent: agent,
            host: "127.0.0.1",
            port: noAuthPort,
            authKey: nil,
            dataDir: noAuthTempDir
        )

        _Concurrency.Task { try? await noAuthServer.start() }
        try await _Concurrency.Task.sleep(for: .milliseconds(300))

        // Request without auth header should succeed
        let url = URL(string: "http://127.0.0.1:\(noAuthPort)/v1/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        XCTAssertEqual(statusCode, 200)

        await noAuthServer.stop()
    }
}
