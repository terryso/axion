import XCTest
import Hummingbird
import HummingbirdTesting
import HTTPTypes
@testable import AxionCLI

final class AuthMiddlewareTests: XCTestCase {

    // MARK: - No auth-key: all requests pass

    func test_noAuthKey_allRequestsPass() async throws {
        let app = try await buildTestApplication(authKey: nil)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs", method: .post, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                XCTAssertEqual(response.status, .accepted, "Without auth-key, requests should pass")
            }
        }
    }

    // MARK: - Auth-key set, no Authorization header → 401

    func test_authKey_noHeader_returns401() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs", method: .post, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                XCTAssertEqual(response.status, .unauthorized, "Missing Authorization should return 401")
            }
        }
    }

    // MARK: - Auth-key set, wrong token → 401

    func test_authKey_wrongToken_returns401() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer wrongtoken"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                XCTAssertEqual(response.status, .unauthorized, "Wrong token should return 401")
            }
        }
    }

    // MARK: - Auth-key set, correct Bearer token → passes

    func test_authKey_correctBearerToken_passes() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer mysecret"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                XCTAssertEqual(response.status, .accepted, "Correct token should be accepted")
            }
        }
    }

    // MARK: - Health endpoint bypasses auth

    func test_healthEndpoint_noAuthRequired() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                XCTAssertEqual(response.status, .ok, "Health endpoint should not require auth")
            }
        }
    }

    // MARK: - Authorization header wrong format (e.g., Basic) → 401

    func test_authKey_basicAuth_returns401() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Basic dXNlcjpwYXNz"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                XCTAssertEqual(response.status, .unauthorized, "Basic auth should return 401")
            }
        }
    }

    // MARK: - Auth-key set, GET run also requires auth

    func test_authKey_getRun_requiresAuth() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/nonexistent", method: .get) { response in
                // Should be 401 (auth) not 404 (not found)
                XCTAssertEqual(response.status, .unauthorized, "GET runs should require auth when key is set")
            }
        }
    }

    // MARK: - Story 5.3: Additional edge cases

    // Empty Bearer token (just "Bearer " with nothing after) → 401
    func test_authKey_emptyBearerToken_returns401() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer "
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                XCTAssertEqual(response.status, .unauthorized, "Empty Bearer token should return 401")
            }
        }
    }

    // 401 response body has correct JSON error structure
    func test_authKey_401Response_hasCorrectErrorBody() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs", method: .post, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                XCTAssertEqual(response.status, .unauthorized)
                let body = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                XCTAssertEqual(body.error, "unauthorized")
                XCTAssertFalse(body.message.isEmpty, "Error message should not be empty")
            }
        }
    }

    // Health endpoint with trailing slash also bypasses auth
    func test_healthEndpoint_trailingSlash_noAuthRequired() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health/", method: .get) { response in
                XCTAssertEqual(response.status, .ok, "Health endpoint with trailing slash should not require auth")
            }
        }
    }

    // SSE endpoint also requires auth
    func test_authKey_sseEndpoint_requiresAuth() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/runs/nonexistent-id/events", method: .get) { response in
                XCTAssertEqual(response.status, .unauthorized, "SSE endpoint should require auth when key is set")
            }
        }
    }

    // Bearer token with extra spaces → 401
    func test_authKey_bearerWithExtraSpaces_returns401() async throws {
        let app = try await buildTestApplication(authKey: "mysecret")

        try await app.test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer  mysecret"
            try await client.execute(uri: "/v1/runs", method: .post, headers: headers, body: ByteBuffer(string: "{\"task\": \"open calc\"}")) { response in
                XCTAssertEqual(response.status, .unauthorized, "Token with extra spaces should return 401")
            }
        }
    }

    // MARK: - Helper

    private func buildTestApplication(
        authKey: String?,
        runTracker: RunTracker? = nil,
        eventBroadcaster: EventBroadcaster? = nil
    ) async throws -> Application<RouterResponder<BasicRequestContext>> {
        let broadcaster = eventBroadcaster ?? EventBroadcaster()
        let tracker = runTracker ?? RunTracker(eventBroadcaster: broadcaster)
        let router = Router()
        AxionAPI.registerRoutes(
            on: router,
            runTracker: tracker,
            eventBroadcaster: broadcaster,
            config: .default,
            authKey: authKey
        )
        return Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
    }
}
